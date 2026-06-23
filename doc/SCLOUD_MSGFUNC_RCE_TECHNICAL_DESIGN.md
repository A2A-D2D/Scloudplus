# Scloud+ MsgEnc/MsgDec RCE 加速器技术设计文档

## 1. 文档目的

本文描述 Scloud+ MsgEnc/MsgDec 加速器接入 SPUV3 RCE 的 RTL 设计方案，包括设计目标、模块划分、数据布局、控制流程、DPRAM 接口、runtime-tau BDD 优化、PPA 考量和验证方案。

本文面向：

- RCE subsystem 集成工程师
- Scloud+ RTL 设计与验证工程师
- 后端综合/时序/PPA 分析工程师

当前实现文件：

```text
rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v
rtl/msgfunc/rce/spuv3_cfg_sfr_scloud.v
rtl/msgfunc/bdd/scloud_bdd_seq_rt.v
rtl/msgfunc/param/scloud_msgfunc_param.v
rtl/msgfunc/bdd/scloud_bdd_recursive.v
tb/rce/tb_scloud_msgfunc_rce_accel.v
tb/rce/tb_spuv3_cfg_sfr_scloud.v
```

## 2. 设计目标

### 2.1 功能目标

加速 Scloud+ KEM 中的 Barnes-Wall message function：

- `MsgEnc`: message bits -> BW32 Q-domain vector
- `MsgDec`: noisy Q-domain vector -> recovered message bits
- `MsgEncAdd`: `q_out = q_in + MsgEnc(msg) mod 2^12`
- `SubMsgDec`: `msg_out = MsgDec(q_in - q_aux mod 2^12)`

支持参数：

| 参数 | 支持值 | 说明 |
| --- | --- | --- |
| `Q_WIDTH` | 12 | Scloud+ Q-domain 坐标宽度 |
| `tau` | 3 / 4 | runtime 选择 |
| BW block | BW32 | 32 real coordinates, 16 complex coordinates |
| block count | 2 / 4 | ss=16/24 使用 2 block，ss=32 使用 4 block |

### 2.2 PPA 目标

本设计的 PPA 目标如下：

- 不复制 tau3/tau4 两套 BW32 BDD datapath。
- 不通过 VPU VR 搬运 384/512-bit BW32 block。
- 不复用 RSA 算法 datapath，避免不匹配的面积和控制开销。
- 数据面直接使用 RCE DPRAM，减少 host/core 参与。
- 对 Encaps/Decaps 相邻操作做融合，减少中间矩阵写回和主核软件循环。

## 3. 总体架构

Scloud+ MsgFunc 作为 RCE top-level 的 DPRAM side accelerator 接入。

```text
Host / SPU core
  -> SFR config
  -> spu_subsystem opcode dispatch
  -> scloud_msgfunc_rce_accel
  -> DPRAM Port A
  -> Scloud MsgEnc / MsgDec datapath
```

[图 1：Scloud+ MsgFunc 接入 SPUV3 RCE 的系统框图]

建议图中包含：

- Host AHB config path
- SPU core
- `spuv3_cfg_sfr`
- `spu_subsystem`
- DPRAM Port A mux
- RSA accelerator
- Scloud MsgFunc accelerator
- DPRAM memory
- done/busy/int 返回路径

## 4. 为什么不走 VPU

SPUV3 VPU VR 宽度为 320-bit，而 Scloud+ BW32 Q block 有两种自然视角：

```text
packed Q payload : 32 x 12-bit  = 384-bit
software layout  : 32 x uint16  = 512-bit
SPUV3 VR         : 320-bit
```

因此 VPU/VR 不是自然数据承载路径。若强行使用 VPU：

- 一个 BW32 block 需要拆成多次 VR load/store。
- 需要额外 pack/unpack。
- BDD 是递归选择与 distance tree，不是规则 SIMD lane 运算。
- 每个 KEM 只有 2 或 4 个 BW32 block，VPU 指令调度开销难以摊销。

因此本设计选择 DPRAM side accelerator 模型。

## 5. 顶层模块

### 5.1 模块名

```verilog
module scloud_msgfunc_rce_accel;
```

该模块是唯一需要作为 MsgFunc 算法顶层实例化到 `spu_subsystem` 的模块。`spuv3_cfg_sfr_scloud` 是并列的可选 SFR 模块；`scloud_bdd32_seq_rt`、`scloud_msgenc_param` 等均为内部子模块，不能作为 RCE 算法顶层。

工程统一使用：

```text
filelist = rtl/msgfunc/rce/scloud_msgfunc_rce.f
top      = scloud_msgfunc_rce_accel
```

### 5.2 顶层接口

| 信号 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | input | 1 | RCE 工作时钟 |
| `rst_n` | input | 1 | 低有效复位 |
| `start` | input | 1 | 启动脉冲 |
| `op` | input | 2 | 操作类型 |
| `tau_sel` | input | 1 | 0=tau3，1=tau4 |
| `block_count` | input | 3 | BW32 block 数 |
| `dec_write_q` | input | 1 | decode 类 op 是否写回 rounded Q |
| `msg_in_base` | input | parameter | message input DPRAM word base |
| `msg_out_base` | input | parameter | message output DPRAM word base |
| `q_in_base` | input | parameter | Q input DPRAM word base |
| `q_aux_base` | input | parameter | auxiliary Q input DPRAM word base |
| `q_out_base` | input | parameter | Q output DPRAM word base |
| `start_ready` | output | 1 | 可接收 start |
| `busy` | output | 1 | 正在运行 |
| `done` | output | 1 | 完成脉冲 |
| `error` | output | 1 | 非法配置错误 |
| `dpram_en` | output | 1 | DPRAM enable |
| `dpram_wr_en` | output | 1 | DPRAM write enable |
| `dpram_be` | output | 32 | DPRAM byte enable |
| `dpram_addr` | output | parameter | DPRAM word address |
| `dpram_wdata` | output | 256 | DPRAM write data |
| `dpram_rdata` | input | 256 | DPRAM read data |

参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `DPRAM_ADDR_WIDTH` | 16 | DPRAM word address 位宽 |
| `Q_WIDTH` | 12 | Q-domain coordinate width |

## 6. 操作定义

Wrapper 内部使用 2-bit `op`：

```verilog
localparam [1:0] OP_MSGENC     = 2'd0;
localparam [1:0] OP_MSGDEC     = 2'd1;
localparam [1:0] OP_MSGENC_ADD = 2'd2;
localparam [1:0] OP_SUB_MSGDEC = 2'd3;
```

推荐 RCE SFR 侧使用 8-bit opcode：

```verilog
localparam [7:0] OPC_SCLOUD_MSGENC      = 8'h80;
localparam [7:0] OPC_SCLOUD_MSGDEC      = 8'h81;
localparam [7:0] OPC_SCLOUD_MSGENC_ADD  = 8'h82;
localparam [7:0] OPC_SCLOUD_SUB_MSGDEC  = 8'h83;
```

| 操作 | 输入 | 输出 | 用途 |
| --- | --- | --- | --- |
| `MSGENC` | `msg_in` | `q_out` | 单独生成 message matrix |
| `MSGDEC` | `q_in` | `msg_out`, optional `q_out` | 单独 decode Q-domain block |
| `MSGENC_ADD` | `msg_in`, `q_in` | `q_out` | Encaps 中融合 `C2 += MsgEnc(msg)` |
| `SUB_MSGDEC` | `q_in`, `q_aux` | `msg_out`, optional `q_out` | Decaps 中融合 `MsgDecode(C2 - temp)` |

## 7. DPRAM 数据布局

### 7.1 地址单位

所有 base address 都是 DPRAM 256-bit word address，不是 byte address。

### 7.2 Message block

每个 BW32 message block 占 1 个 256-bit word。

```text
address = msg_base + block_idx
tau=3: word[63:0]
tau=4: word[95:0]
```

写回 byte enable：

```text
tau=3: dpram_be = 32'h000000ff
tau=4: dpram_be = 32'h00000fff
```

### 7.3 Q block

每个 BW32 Q block 占 2 个 256-bit word。

```text
low  half address = q_base + block_idx * 2
high half address = q_base + block_idx * 2 + 1
```

每个 256-bit word 存 16 个 `uint16_t` lane：

```text
lane[i][11:0]  = Q coordinate
lane[i][15:12] = ignored on read, written as zero on writeback
```

[图 2：DPRAM 中 message block 和 Q block 的存储布局]

建议图中画出：

- 1 个 256-bit message word
- 2 个 256-bit Q words
- 16 个 uint16 lane
- 每个 lane 的低 12 bit / 高 4 bit

## 8. 内部模块划分

当前 wrapper 内部由四部分组成：

```text
scloud_msgfunc_rce_accel
  |-- DPRAM access FSM
  |-- MsgEnc tau3
  |-- MsgEnc tau4
  |-- runtime-tau BDD
  |-- MsgDec post-process tau3
  |-- MsgDec post-process tau4
```

[图 3：`scloud_msgfunc_rce_accel` 内部模块框图]

建议图中包含：

- DPRAM read/write FSM
- `msg_word_r`
- `q_in_flat_r`
- `q_aux_flat_r`
- `scloud_msgenc_param tau3`
- `scloud_msgenc_param tau4`
- `scloud_bdd32_seq_rt`
- tau3/tau4 `q_to_label -> phi_decode -> label_to_msg`
- `q_write_flat`
- `msg_result_r`

## 9. Runtime-Tau BDD 设计

### 9.1 设计动机

初始设计中 tau=3 和 tau=4 各实例化一套 `scloud_msgdec_param`。这样功能简单，但面积不理想，因为 MsgDec 的主要面积来自 BW32 BDD。

优化后，重 datapath 合并为一套：

```text
scloud_bdd32_seq_rt
  -> scloud_bdd16_seq_rt
  -> scloud_bdd8_seq_rt
  -> scloud_bdd4_seq_rt
  -> scloud_bdd_round_coord_q_rt
```

`tau_sel` 只影响 leaf rounding：

```text
tau=3:
  HALF_DELTA = 1 << 8
  ROUND_MASK = 12'b111_000000000

tau=4:
  HALF_DELTA = 1 << 7
  ROUND_MASK = 12'b1111_00000000
```

### 9.2 Runtime-tau rounding

`scloud_bdd_round_coord_q_rt` 同时计算 tau3/tau4 rounding，然后用 `tau_sel` 选择：

```text
round_tau3 = (x + HALF_DELTA_TAU3) & ROUND_MASK_TAU3
round_tau4 = (x + HALF_DELTA_TAU4) & ROUND_MASK_TAU4
y_q        = tau_sel ? round_tau4 : round_tau3
```

### 9.3 Tau 启动拍传递

BDD 父节点在 `IDLE` 接收 start 的同一拍会启动 child BDD。因此 runtime-tau 版本中 child tau 选择为：

```text
child_tau_sel = state == IDLE ? tau_sel : tau_sel_r
```

这样可以避免启动首拍 child 使用上一笔操作的 tau。

[图 4：Runtime-tau BDD 递归结构和 tau_sel 传递]

建议图中包含：

- BW32/BW16/BW8/BW4 层级
- 每层 child_start
- `tau_sel` 在 IDLE start 拍直接传递
- `tau_sel_r` 在运行阶段保持

## 10. MsgDecode 后处理

BDD 输出 `rounded_rt_flat` 后，仍保留两套轻量后处理：

```text
tau3:
  q_to_label tau3
  phi_decode label_width=7
  label_to_msg tau3, 64-bit msg

tau4:
  q_to_label tau4
  phi_decode label_width=8
  label_to_msg tau4, 96-bit msg
```

保留两套后处理的原因：

- `label_to_msg` 中包含 C-model aligned 的硬编码 bit packing。
- 这部分面积远小于 BDD。
- 若强行做 runtime 统一，会引入复杂动态 bit extraction 网络，风险和面积未必更优。

因此当前方案是：

```text
重 BDD 共享
轻后处理分 tau 保留
```

## 11. 控制状态机

`scloud_msgfunc_rce_accel` 使用单 FSM 控制 DPRAM 访问和计算流程。

主要状态：

| 状态 | 作用 |
| --- | --- |
| `ST_IDLE` | 等待 start |
| `ST_READ_MSG` / `ST_CAP_MSG` | 读取 message word |
| `ST_PREP_ENC` | message 寄存后一拍，准备 MsgEnc 输出 |
| `ST_READ_Q0` / `ST_CAP_Q0` | 读取 Q block low half |
| `ST_READ_Q1` / `ST_CAP_Q1` | 读取 Q block high half |
| `ST_READ_AUX0` / `ST_CAP_AUX0` | 读取 aux Q block low half |
| `ST_READ_AUX1` / `ST_CAP_AUX1` | 读取 aux Q block high half |
| `ST_START_DEC` | 启动 runtime-tau BDD |
| `ST_WAIT_DEC` | 等待 BDD done |
| `ST_WRITE_Q0` / `ST_WRITE_Q1` | 写 Q output |
| `ST_WRITE_MSG` | 写 message output |
| `ST_NEXT_BLOCK` | block index 递增 |
| `ST_DONE` | 输出 done pulse |

[图 5：`scloud_msgfunc_rce_accel` FSM 状态转换图]

建议图中至少画出四条路径：

- `MSGENC`
- `MSGDEC dec_write_q=0`
- `MSGENC_ADD`
- `SUB_MSGDEC dec_write_q=0`

## 12. 四种操作的数据流

### 12.1 MSGENC

```text
READ msg
PREP_ENC
WRITE q_out low half
WRITE q_out high half
NEXT_BLOCK / DONE
```

### 12.2 MSGDEC

```text
READ q_in low half
READ q_in high half
START_DEC
WAIT_DEC
WRITE msg_out
NEXT_BLOCK / DONE
```

如果 `dec_write_q=1`：

```text
WAIT_DEC
WRITE q_out low half
WRITE q_out high half
WRITE msg_out
```

### 12.3 MSGENC_ADD

```text
READ msg
READ q_in low half
READ q_in high half
q_write = q_in + MsgEnc(msg)
WRITE q_out low half
WRITE q_out high half
```

### 12.4 SUB_MSGDEC

```text
READ q_in low half
READ q_in high half
READ q_aux low half
READ q_aux high half
dec_input = q_in - q_aux
START_DEC
WAIT_DEC
WRITE msg_out
```

如果 `dec_write_q=1`，额外写回 rounded Q。

[图 6：四种 op 的数据流时序图]

建议图中按 cycle 展开：

- DPRAM read request
- DPRAM capture
- BDD start/done
- DPRAM write
- done pulse

## 13. PPA 优化点

### 13.1 已实现优化

| 优化 | 类型 | 收益 |
| --- | --- | --- |
| Runtime-tau BDD | 面积 | tau3/tau4 共享一套 BW32/BW16/BW8/BW4 BDD datapath |
| 去掉 `q_result_flat_r` | 面积/功耗 | 少一组 384-bit flop 和写入切换 |
| `dec_write_q` | 性能/功耗 | decode 不需要 rounded Q 时每 block 少 2 拍 256-bit 写回 |
| `MSGENC_ADD` | 性能/功耗 | Encaps 中减少 matrixM 中间写读和主核 add loop |
| `SUB_MSGDEC` | 性能/功耗 | Decaps 中减少 diff 中间写读和主核 sub loop |

### 13.2 后续可选优化

| 优化方向 | 收益 | 风险 |
| --- | --- | --- |
| BDD distance tree pipeline | 提高 Fmax | 增加少量 latency 和寄存器 |
| MsgEnc tau3/tau4 runtime 合并 | 小幅面积降低 | bit packing 动态化复杂，收益可能有限 |
| 后处理 tau3/tau4 runtime 合并 | 小幅面积降低 | C-model aligned hardcoded mapping 复杂 |
| SKU 参数裁剪 | 大幅面积降低 | 只适合固定安全等级产品 |
| operand isolation | 降低动态功耗 | 增加门控控制和验证项 |

## 14. 与 RCE subsystem 的集成

### 14.1 Opcode dispatch

`spu_subsystem` 中建议增加：

```verilog
wire is_scloud_op =
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGENC)     ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGDEC)     ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGENC_ADD) ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_SUB_MSGDEC);
```

启动选择：

```text
spuv3_cfg_en && is_scloud_op  -> scloud_start
spuv3_cfg_en && !is_scloud_op -> original SPU/RSA path
```

### 14.2 Done/busy 选择

```text
alg_done = scloud_active ? scloud_done : spuv3_core_done
busy     = original_busy | scloud_busy
```

Scloud busy 时 host 不应访问 DPRAM。

### 14.3 DPRAM Port A mux

建议优先级：

```text
RSA > Scloud > SPU core
```

示意：

```verilog
assign dpram_en_a =
    rsa_ram_ena | scloud_dpram_en | spu_dpram_en_a;

assign dpram_wr_en_a =
    rsa_ram_ena     ? rsa_ram_wea :
    scloud_dpram_en ? scloud_dpram_wr_en :
                       spu_dpram_wr_en_a;

assign dpram_addr_a =
    rsa_ram_ena     ? rsa_ram_addr :
    scloud_dpram_en ? scloud_dpram_addr :
                       spu_dpram_addr_a;
```

[图 7：DPRAM Port A 仲裁/mux 结构图]

建议图中包含：

- RSA DPRAM request
- Scloud DPRAM request
- SPU core DPRAM request
- mux priority
- DPRAM Port A

## 15. SFR 建议

沿用 `spuv3_cfg` 时建议：

```text
spuv3_cfg[31]    done/status
spuv3_cfg[30]    start
spuv3_cfg[29:12] reserved/result_len
spuv3_cfg[11]    tau_sel
spuv3_cfg[10:8]  block_count
spuv3_cfg[7:0]   opcode
```

建议新增地址 SFR：

| SFR | 说明 |
| --- | --- |
| `SCLOUD_MSG_IN_BASE` | message input base |
| `SCLOUD_MSG_OUT_BASE` | message output base |
| `SCLOUD_Q_IN_BASE` | Q input base |
| `SCLOUD_Q_AUX_BASE` | auxiliary Q input base |
| `SCLOUD_Q_OUT_BASE` | Q output base |

如果不想新增 SFR，第一版也可以使用固定 DPRAM layout。

## 16. 错误处理

当前 wrapper 的 `error` 只检查非法 `block_count`：

```text
block_count == 0
block_count > 4
```

建议 RCE 集成后扩展：

- illegal opcode
- busy 时重复 start
- address range overflow
- host DPRAM access conflict

## 17. 验证方案

### 17.1 当前已实现 testbench

```text
tb/rce/tb_scloud_msgfunc_rce_accel.v
```

运行方式：

```bash
iverilog -g2001 -Wall -o sim_build/tb_scloud_msgfunc_rce_accel.vvp \
  rtl/msgfunc/bdd/*.v \
  rtl/msgfunc/param/scloud_msgfunc_param.v \
  rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v \
  tb/rce/tb_scloud_msgfunc_rce_accel.v

vvp sim_build/tb_scloud_msgfunc_rce_accel.vvp
```

当前覆盖：

- tau=3，2 blocks，`MSGENC -> MSGDEC`
- tau=4，2 blocks，`MSGENC_ADD -> SUB_MSGDEC`
- runtime-tau BDD 的 tau 切换
- DPRAM 256-bit 同步读写
- `uint16_t[32]` Q block packing
- `dec_write_q=0`

当前结果：

```text
TB_PASS scloud_msgfunc_rce_accel
```

### 17.2 建议补充用例

| 用例 | 目的 |
| --- | --- |
| tau=3, 4 blocks | 覆盖 ss=32 |
| tau=4, `MSGDEC`, `dec_write_q=1` | 覆盖 rounded Q 写回 |
| illegal block_count | 覆盖 `error` |
| back-to-back start | 覆盖 `start_ready` |
| random DPRAM base address | 覆盖地址计算 |
| non-zero high 4 bits in uint16 lane | 确认 high bits ignored |
| fixed-tau BDD vs runtime-tau BDD 对比 | 确认 runtime-tau BDD 等价 |

## 18. 后端关注点

综合和 STA 时重点关注：

- `scloud_bdd_distance_tree`
- `dist_a < dist_b` select path
- `q_add_mod` / `q_sub_mod`
- `q_half_to_word` / `word_to_q_half` packing fanout
- runtime-tau round mux

若 timing 不满足，优先考虑：

1. distance tree pipeline
2. select 前后加寄存
3. BDD 子层状态边界重定时
4. DPRAM output register 对齐

## 19. 当前设计基线与设计理念

截至 2026-06-22，当前可综合、可回归的基线采用：

```text
DPRAM side accelerator
+ Scloud 专用 MsgEnc/MsgDec datapath
+ one shared runtime-tau BDD32
+ Fast Scloud+ unfold-factor-8 recursion reuse
+ exact 8-lane sequential distance at BDD32/BDD16
+ parallel distance retained at BDD8/BDD4
+ tau3/tau4 lightweight post-processing
+ Encaps/Decaps fused op
```

设计取舍遵循四条原则：

1. **算法专用而非强塞 VPU**：384-bit BW32 数据和递归 BDD 不适合 320-bit VR 的规则 SIMD 数据流，因此采用 DPRAM 旁路专用核。
2. **递归层级复用**：BDD32/BDD16 各保留一个 child，通过 YL/YR/ZA/ZB 四阶段调度复用常驻 BDD8 核，每次 BDD32 共 16 次 BDD8 调用。
3. **高层共享、低层并行**：BDD32 持有一个同时服务 BDD32/BDD16 EdC 请求的 8-lane 精确顺序平方累加引擎；BDD8/BDD4 保持双候选并行距离核，避免面积最小化导致延迟过度增长。
4. **精确性优先**：保留 12-bit 模差值、32-bit 距离累加和 strict `<` tie-break。论文中的 4-bit 平方只有在范围证明后才允许启用。

性能效率主要来自 `MSGENC_ADD`、`SUB_MSGDEC` 和 `dec_write_q=0`，它们减少 KEM 中间矩阵写回与再次读取。面积收益主要来自 runtime-tau BDD 共享、factor-8 半展开和 8-lane distance sharing。

当前综合基线为：

```text
Total: 8,680 LUT / 7,274 FF / 40 DSP48
BDD:   7,189 LUT / 5,860 FF / 40 DSP48
Timing: 200 MHz standalone synthesis, WNS +0.020 ns / TNS 0
```

该方案是当前 Scloud+ MsgEnc/MsgDec 接入 SPUV3 RCE 的 PPA-oriented RTL 基线。

## 20. 历史全并行综合结果与优化依据

本章保留最初 256 DSP 全并行版本以及后续 48 DSP 无约束版本的历史分析，用于解释优化来源，不代表当前实现。当前 40 DSP 约束综合结果以第 19 章和第 22.16 节为准。

综合环境：

```text
Vivado 2019.1
Device: xc7a200tfbg484-1
Top: scloud_msgfunc_rce_accel
```

### 20.1 初始全并行版本资源结果

| 层级 | LUT | FF | DSP48 |
| --- | ---: | ---: | ---: |
| 整个 `scloud_msgfunc_rce_accel` | 19,515 | 7,050 | 256 |
| wrapper 自身 | 2,527 | 1,083 | 0 |
| `u_bdd_rt` | 15,760 | 5,967 | 256 |
| `u_msgenc_tau3` | 376 | 0 | 0 |
| `u_msgenc_tau4` | 418 | 0 | 0 |
| `u_phi_decode_tau3` | 198 | 0 | 0 |
| `u_phi_decode_tau4` | 236 | 0 | 0 |

结论：

- BDD 占约 81% LUT、85% FF 和全部 DSP48。
- tau3/tau4 后处理不是当前面积瓶颈。
- 下一轮不应优先合并 MsgEnc 或 label packing，应优先重构 BDD distance 计算。

### 20.2 初始版本 DSP 产生原因

初始 `scloud_bdd_distance_tree` 为每个坐标实例化：

```text
diff = candidate - target
square = diff * diff
distance = sum(square)
```

初始 BW32/BW16/BW8/BW4 的所有递归节点都保留两棵并行 distance tree。综合结果总计 256 个并行平方乘法器，因此使用 256 个 DSP48。

DRC 对这些 DSP 给出：

```text
DPIP-1: 512 input pipeline warnings
DPOP-1: 256 PREG warnings
DPOP-2: 256 MREG warnings
```

这说明当前乘法器既高度并行，又没有使用 DSP 内部 pipeline。

### 20.3 当时提出的面积优先重构

新增可复用顺序距离单元：

```text
scloud_bdd_distance_seq
  input candidate_flat
  input target_flat
  input coord_count
  configurable DIST_LANES = 1 / 2 / 4 / 8
  output distance
  output done
```

一个 BDD 节点不再同时保留两棵 distance tree，而是：

```text
calculate distance(candidate_a, target)
store dist_a
calculate distance(candidate_b, target)
store dist_b
select dist_a < dist_b
```

当时建议从以下配置开始评估：

```text
DIST_LANES = 4
```

预期权衡：

| 方案 | 乘法并行度 | DSP 预期 | 延迟 | 适用目标 |
| --- | ---: | ---: | ---: | --- |
| 初始全并行 | 256 | 256 | 最低 | 面积不敏感 |
| 每节点单 DSP | 约 15 | 约 15 | 较高 | 面积优先 |
| 全局 4-lane shared engine | 4 | 约 4 | 高 | 极限面积 |
| 4-lane/node 或分层共享 | 约 32-60 | 约 32-60 | 中 | 推荐折中 |

该阶段落地方案选择 factor-8 分层复用加 BDD32/BDD16 各 8-lane distance engine，当时实测为 48 DSP；后续将两套互斥高层引擎进一步合并为 BDD32 所有的单套共享引擎，当前实测为 40 DSP。

### 20.4 历史性能优先备选

若必须保留 256 DSP 全并行结构，则应给平方乘法路径增加输入、MREG 和 PREG pipeline，以消除 DRC 的 DSP pipeline 警告并提高 Fmax。但该方案会继续占用 256 DSP，并增加寄存器和流水控制，不符合当前面积优先目标。

### 20.5 Timing 报告限制

历史 48 DSP timing report 当时显示：

```text
There are no user specified timing constraints.
WNS/TNS = NA
4,471 register/latch pins have no constrained clock
```

因此目前不能根据该报告判断实际 Fmax，也不能据此决定需要几级 pipeline。下一次综合至少需要：

```tcl
create_clock -name clk -period 5.000 [get_ports clk]
```

若 RCE 目标频率不是 200MHz，应使用实际周期。

### 20.6 Power 报告限制

历史 48 DSP power report 当时给出 213.135W，但：

- Overall confidence 为 Low。
- 没有 clock constraint。
- 没有 SAIF/VCD switching activity。
- 616 个宽数据端口被当作 FPGA 外部 I/O。
- 设计只完成 synthesis，未 place/route。

因此该绝对功耗值无效。报告仍能定性说明 DSP、组合逻辑和大总线切换是主要动态功耗来源。下一次应在 RCE subsystem 内综合，并导入仿真活动文件后重新评估。

### 20.7 DRC 中与 RTL 无关的项目

`NSTD-1`、`UCIO-1` 和 616 个外部端口来自单独综合 accelerator top。真实设计中这些端口是 RCE 内部信号，不应分配 FPGA 引脚。应使用内部 integration wrapper 或 OOC synthesis，而不是为 256-bit DPRAM 内部总线逐个添加板级 LOC。

### 20.8 当前后续优化优先级

1. 为综合加入真实 clock constraint。
2. 将 BDD 增加 two-beat target load 接口，直接接收 DPRAM low/high Q half。
3. 删除 wrapper 中重复的 384-bit `q_in_flat_r`/`q_aux_flat_r` 全块缓存，改为 half-beat 流式 add/sub/load。
4. 把 `msg_word_r` 从 256-bit 缩减为实际需要的 96-bit。
5. 为未运行阶段增加 operand isolation，降低 distance/phi 大总线翻转。
6. 在真实 RCE subsystem 内重新综合，避免 standalone I/O 对功耗和 DRC 的干扰。
7. 只有在 48 DSP 共享方案加入真实约束后 timing 仍不满足时，才增加 DSP pipeline。
8. 完成 openHiTLS `pk/sk/ct/ss` 逐字节 KAT 闭环并修复 ss24 Encaps heap corruption。

### 20.9 Wrapper 寄存器优化

Wrapper 自身当前使用约 1,077 FF，主要来源为：

```text
msg_word_r     = 256 bit，实际只需要 96 bit
q_in_flat_r    = 384 bit
q_aux_flat_r   = 384 bit
msg_result_r   = 96 bit
```

同时 BDD 内部还会再次锁存 384-bit target，存在重复存储。推荐增加：

```text
bdd_load_valid
bdd_load_half_sel
bdd_load_data[191:0]
```

数据流改为：

```text
MSGDEC:
  DPRAM Q low  -> BDD target low
  DPRAM Q high -> BDD target high

SUB_MSGDEC:
  read q_in half
  read q_aux half
  subtract 16 lanes
  -> BDD target half

MSGENC_ADD:
  read q_in half
  add 16 MsgEnc lanes
  write q_out half
```

该方案可以删除大部分 wrapper Q block 全宽寄存器，并把 32-lane add/sub 缩减为 DPRAM beat 对齐的 16-lane datapath。

## 21. Fast Scloud+ 展开因子 8 的 BDD32 优化

### 21.1 论文依据

参考 `fast-scloud+.pdf` 的 Table 4 和 Figure 7，BDD32 采用展开因子 8：常驻一个 BDD8 计算核，BDD16 与 BDD32 由外围寄存器和 ALU 进行循环复用。Table 4 对应 16 次迭代，硬件操作集合为：

```text
16 BW2 + 4 BW4 + 1 BW8 + 1 BW16
 4 EdC2 + 1 EdC4 + 1 EdC8 + 1 EdC16
```

### 21.2 当前 RTL 映射

当前实现保持 `scloud_bdd32_seq_rt` 的接口不变，只调整内部层级：

```text
scloud_bdd32_seq_rt
  `-- 1 x scloud_bdd16_seq_rt，顺序执行 YL/YR/ZA/ZB
        `-- 1 x scloud_bdd8_seq_rt，顺序执行 YL/YR/ZA/ZB
              `-- 2 x scloud_bdd4_seq_rt
```

因此每次 BDD32 共调用 BDD8 16 次。`scloud_msgfunc_rce_accel` 仍然是唯一接入 RCE 的算法顶层，SFR、DPRAM 和 start/busy/done 接口均不变化。

### 21.3 半展开阶段的面积与延迟结果

结构平方单元计数由 256 降为 128；BDD16 实例数由 2 降为 1，BDD8 由 4 降为 1，BDD4 由 8 降为 2。代价是 BDD 子调用串行化，块延迟增加。RTL 回归中 tau3 MSGENC/MSGDEC 与 tau4 MSGENC_ADD/SUB_MSGDEC 均通过。

该阶段随后由 Vivado 确认为 11,522 LUT、4,443 FF、128 DSP，并作为继续引入 8-lane distance sharing 的中间基线。

### 21.4 尚未照搬的 4-bit 平方优化

论文指出其 EdC 平方操作数只有 4 bit。当前设计的 Q 数据宽度为 12 bit，并按模 q 差值参与距离比较。在没有完成差值范围证明和 C-model/RTL 等价回归前，不能直接截成 4 bit，否则可能改变最小距离候选选择。

后续优化顺序为：记录 C-model 全测试集的每层差值峰值，证明安全位宽；增加窄位宽平方模式；完成随机、边界和消息向量回归；最后重新综合确认 DSP 是否转为 LUT 或显著减少。

### 21.5 半展开综合实测结果

Vivado 2019.1、XC7A200T、综合顶层 `scloud_msgfunc_rce_accel` 的新报告已确认使用单 `u_child` 层级。与全并行版本比较：

| 指标 | 全并行版本 | 展开因子 8 | 变化 |
| --- | ---: | ---: | ---: |
| Total LUT | 19,515 | 11,522 | -41.0% |
| FF | 7,050 | 4,443 | -37.0% |
| DSP48 | 256 | 128 | -50.0% |
| BDD LUT | 15,760 | 8,479 | -46.2% |
| BDD FF | 5,967 | 3,358 | -43.7% |

层级资源与预期一致：BDD32 自身 64 DSP，单 BDD16 子核总计 64 DSP；BDD16 内的单 BDD8 子核为 32 DSP；BDD8 内两个 BDD4 各为 8 DSP。

功耗报告从 481.835 W 降至 281.310 W，动态功耗从 480.161 W 降至 279.635 W，DSP 估算功耗从 171.205 W 降至 87.648 W。由于报告仍无用户时钟约束、总体置信度为 Low，绝对功耗值不可作为设计指标，只能说明资源和默认翻转模型下的功耗方向下降。

Timing 报告仍显示 `There are no user specified timing constraints`，WNS/TNS 无有效值。下一轮必须加入真实 RCE `clk` 约束后再判断是否需要 DSP 输入、MREG 或 PREG 流水。

## 22. 8-lane 精确距离共享优化

### 22.1 优化范围

在展开因子 8 的基础上，将 BDD32 和 BDD16 各自的候选 A/B 全宽并行距离树替换为一个 `scloud_bdd_distance_seq`。每个引擎包含 8 个 12-bit 平方通道，先扫描候选 A，再扫描候选 B，分别累加为原有 32-bit 距离后执行严格小于比较。

BDD8 和 BDD4 继续使用并行距离树，以控制嵌套递归带来的延迟增长。该版本没有采用论文中的 4-bit 截位，因此距离判决保持精确等价。

### 22.2 调度与延迟

```text
BDD16 EdC: 16 coordinates / 8 lanes x 2 candidates = 4 accumulate cycles
BDD32 EdC: 32 coordinates / 8 lanes x 2 candidates = 8 accumulate cycles
```

加上启动和完成握手，RCE 两块端到端回归的总仿真时间由约 13,165 拍增加到约 14,525 拍，增幅约 10.3%。

### 22.3 已实现资源结构

```text
BDD32 distance: 64 DSP -> 8 DSP
BDD16 distance: 32 DSP -> 8 DSP
BDD8 hierarchy: 保持 32 DSP
Total: 128 DSP -> 48 DSP
```

DSP 实测下降 62.5%，相对最初 256 DSP 全并行版本下降 81.25%。共享引擎增加了候选/目标 chunk 选择 mux、累加寄存器和控制状态，但总 LUT 仍由 11,522 下降到 9,271，FF 仅由 4,443 增加到 4,471。

### 22.4 验证结果

- 200 组随机 32 坐标测试中，共享引擎的候选 A 距离、候选 B 距离和选择结果均与原并行距离树逐位一致。
- tau3 MSGENC/MSGDEC 和 tau4 MSGENC_ADD/SUB_MSGDEC 端到端回归通过。
- SFR 与矩阵乘法回归通过。
- C-model aligned 的 ss16、ss24、ss32 自测全部通过。

综合网表已确认 BDD32 和 BDD16 下各有一个 `u_dist_seq`，总 DSP48 为 48。

### 22.5 8-lane 版本综合实测结果

Vivado 2019.1、XC7A200T 的新综合网表已确认 BDD32 和 BDD16 各实例化一个 `u_dist_seq`：

| 指标 | 展开因子 8 | 8-lane 距离共享 | 相对变化 |
| --- | ---: | ---: | ---: |
| Total LUT | 11,522 | 9,271 | -19.5% |
| FF | 4,443 | 4,471 | +0.6% |
| DSP48 | 128 | 48 | -62.5% |
| BDD LUT | 8,479 | 7,351 | -13.3% |
| BDD FF | 3,358 | 3,394 | +1.1% |

相对最初全并行版本，总 LUT 下降 52.5%，DSP48 下降 81.25%。功耗报告为 213.135 W，其中 DSP 估算为 40.876 W；由于仍缺少用户时钟约束且置信度为 Low，只能将其作为下降趋势。

DRC 总数由半展开版本的 516 降至 196，其中 DPIP/DPOP 警告随 DSP 数量降为 96/48/48。Timing 仍无用户约束，不能给出有效 WNS/TNS。

### 22.6 BDD8 并行距离流水

加入 5.000 ns XDC 并对 BDD32/BDD16 共享距离引擎流水后，WNS 从 -17.908 ns 改善到 -13.357 ns，但最差路径转移到常驻 BDD8：`phi -> DSP square -> sum tree -> strict compare/select`，路径延迟为 18.205 ns。因此下一步只对 BDD8 的两棵 8 坐标距离树做性能优先流水，BDD4 保持不变。

`scloud_bdd_distance_pair_pipe` 保留候选 A/B 两路完全并行和原有 16 个 BDD8 DSP，将计算拆为模差值寄存、平方乘法、乘积寄存、并行求和、严格比较。该改动不改变总 40 DSP 架构、12-bit 模差值、32-bit 距离或 tie 选 B 规则。BDD32 随机 tau3/tau4 回归实测固定为 634 拍；新增 BDD8 流水单测通过 200 组随机向量和 2 组 tie，BDD32 20 组随机参考等价及 RCE 端到端回归均通过。

该节只记录 RTL 和仿真证据。流水后的 WNS/TNS、DSP 内部寄存器吸收情况和资源变化必须以重新运行 Vivado 2019.1 综合后的报告为准。

### 22.7 BDD4 最末级距离流水

BDD8 流水后的综合结果为 8,877 LUT、5,008 FF、40 DSP，WNS 改善到 -11.392 ns，但 16.240 ns 最差数据路径下沉到 `scloud_bdd4_seq_rt`。该路径仍在一拍内穿过 phi/candidate 运算、DSP 平方、距离加法树、A/B 严格比较和 decoded 选择，共 21 级逻辑。DRC 剩余的 32 个 DSP 输入流水告警和 16 个 PREG 告警也全部属于两个 BDD4 子核。

因此 BDD4 的两棵四坐标组合距离树也改用 `scloud_bdd_distance_pair_pipe`，通过已有 start/done 握手向上层传播固定延迟。该改动不增加 DSP，不修改模差值、距离位宽或 tie-break；目标是消除当前设计最后一段 `phi -> DSP -> sum -> compare` 单拍组合链。BDD4 对递归 tau3/tau4 参考的 100 组随机等价测试通过；更新后的时序与资源结果仍以重新综合报告为准。

### 22.8 MsgDec 四级 phi 后处理流水

BDD4 流水后的综合结果为 8,850 LUT、5,546 FF、40 DSP，WNS 从 -11.392 ns 改善到 -6.627 ns，TNS 从 -3006.201 ns 改善到 -2671.024 ns。最差路径已经离开 BDD distance 层级，转移到 BDD32 输出至 `msg_result_r` 的 tau4 后处理：一拍内依次穿过 Q-to-label、四层递归 inverse-phi、label reduction 和消息寄存，共 19 级逻辑、11.476 ns 数据路径。

新增 `scloud_msgfunc_phi_decode_layer` 与 `scloud_msgfunc_phi_decode_seq`，按 Barnes-Wall 递归深度将四层 inverse-phi 各自放入独立时钟拍。RCE 只启动当前 tau 对应的流水，完成后再经 `label_to_msg` 写入 96-bit `msg_result_r`。每个解码块增加约 5 拍固定延迟，不改变 Q/label packing、模回绕、消息映射、DPRAM 格式或外部接口。tau3/tau4 流水与原组合递归实现的 200 组随机标签等价测试及 RCE 端到端回归均通过；更新后的 WNS/TNS 仍以重新综合为准。

### 22.9 分层候选快照流水

四级 MsgDec phi 流水后的综合结果为 8,605 LUT、6,449 FF、40 DSP，WNS 从 -6.627 ns 改善到 -3.380 ns。最差路径回到 BDD32 候选准备：`z_b_r -> phi -> candidate add -> distance diff -> DSP input register`，一拍内包含 5 级 carry，数据路径为 7.568 ns。

BDD4、BDD8、BDD16 和 BDD32 均新增候选 A/B 快照寄存器。各层先锁存完整候选，下一拍通过独立 launch 状态启动 distance，使 candidate modular add 与 candidate-to-target subtraction 分属不同周期。显式 launch 状态同时避免本地 distance 的 `done`/`ready` 重叠造成重复 start。该改动保持 40 DSP、12-bit 模回绕、32-bit 精确距离、strict `<` tie-break 和外部接口不变；BDD4 100 组随机参考等价及 RCE 端到端回归通过，更新后的时序和资源仍以重新综合为准。

### 22.10 共享距离 chunk 快照

分层候选快照后的综合结果为 8,923 LUT、7,643 FF、40 DSP。WNS 从 -3.380 ns 改善到 -2.663 ns，TNS 从 -2169.470 ns 改善到 -1382.924 ns，失败端点从 1,386 降到 899。最差路径位于共享 `scloud_bdd_distance_seq`：`phase_b/chunk_idx -> candidate/target宽mux与移位 -> 12-bit diff -> DSP input register`，数据路径为 6.854 ns，其中路由占 69%。

共享距离引擎在差值前新增一个 8-lane candidate/target chunk 快照状态，将宽总线选择与模差值/DSP 输入拆成两拍。只增加 192-bit 共享数据寄存器，不增加全宽候选缓存，不修改 40 DSP、距离精度、tie-break 或接口；每个 8-lane chunk 增加 1 拍。顺序距离 200 组随机加 2 组 tie、BDD4 100 组随机参考以及 RCE 端到端回归通过。DRC 已只剩 40 个 MREG 告警及 standalone I/O 告警；更新时序仍以重新综合为准。

### 22.11 DSP MREG 推断补拍

当前 DRC 中 DPIP 与 PREG 告警已经清零，只剩全部 40 个 DSP 的 `MREG=0`。按照 Vivado 2019.1 对 inferred multiplier 的建议，在并行双候选距离核和共享顺序距离核的平方乘积后再增加一级连续产品寄存器，求和树改为读取第三级产品寄存器。该改动不改变平方、累加顺序、strict `<`、DSP 数量或接口；本地距离事务增加 1 拍，共享引擎每个 8-lane chunk 增加 1 拍。两类距离单测各 200 组随机加 2 组 tie 以及 RCE 端到端回归通过。MREG 是否被吸收到 DSP48、slice FF 是否增加以及时序/功耗变化必须由新综合报告确认。

### 22.12 BDD ready 控制链去耦与无效 MREG 补拍回收

补充第三级产品寄存后的综合结果为 8,704 LUT、8,867 FF、40 DSP，WNS 从 -2.663 ns 改善到 -1.966 ns，TNS 从 -1382.924 ns 改善到 -560.686 ns，失败端点降到 513。但 40 个 MREG 告警完全未减少，额外寄存器成为约 1,224 个 slice FF。最差路径也转移为 BDD4/BDD8/BDD16 间的 `child_ready/start_ready` 组合回传链，终点为目标寄存器 CE，6.584 ns 中路由占 77.5%。

BDD4、BDD8 和 BDD16 的对外 `start_ready` 改为仅由本节点 IDLE 产生；BDD32 再附加 two-half loaded 条件。节点 `done` 已保证子核和本地 distance 完成，独立 launch 状态又阻止 ready/done 重叠重复启动，因此无需把内部 ready 层层组合回传。同时撤销未被 DSP 吸收的第三级产品寄存，保留 chunk snapshot 与原两级产品寄存，预计回收约 1K slice FF 并降低时钟及控制路由负载。全部距离、BDD4 参考和 RCE 回归通过；更新 PPA 以新综合为准。

### 22.13 距离求和树两级归约

ready 控制链去耦后的综合结果为 8,668 LUT、7,824 FF、40 DSP。WNS 从 -1.966 ns 改善到 -1.326 ns，TNS 从 -560.686 ns 大幅改善到 -60.878 ns，失败端点从 513 降到 72。当前最差路径为已寄存平方乘积到 `sum_a_r` 的 8 项求和树，包含 13 级逻辑和 10 个 CARRY4，数据路径 6.192 ns；QoR 统计同类关键路径 138 条。

并行双候选距离核将 8 项平方分为 4+4 两组，先分别求和并寄存，再用下一拍完成最终 32-bit 相加；共享 8-lane 顺序距离核采用相同结构。四坐标 BDD4 也按 2+2 分组复用该参数化实现。该改动保持精确 32-bit 距离、strict `<`、40 DSP 和接口不变，本地距离事务及共享引擎每个 chunk 各增加 1 拍。两类距离单测各 200 组随机加 2 组 tie 与 RCE 回归通过；更新时序和 FF 代价以新综合为准。

### 22.14 200 MHz 约束综合时序收敛

距离求和树两级归约后的 Vivado 2019.1、XC7A200T standalone 综合已经满足 5.000 ns 时钟约束：WNS 为 +0.435 ns、TNS 为 0、setup 失败端点为 0。当前最差路径为 BDD8 并行距离核中已寄存平方到四项 half-sum 寄存器，数据路径 4.187 ns、10 级逻辑，已留出 0.435 ns 综合裕量。资源为 8,618 LUT、8,211 FF、40 DSP；相对归约前 LUT 减少 50、FF 增加 387。

DRC 仍有 40 个 MREG 建议和 standalone I/O 告警，但 MREG 已不是当前时序阻塞项，不应继续用 fabric 补拍换取无效告警消除。功耗报告为 0.659 W、动态 0.526 W，置信度仍为 Low，不能用于 sign-off。至此停止 standalone RTL 流水扩张，下一阶段应在真实 RCE subsystem 内进行 place/route，使用内部 DPRAM 连线、真实时钟树和切换活动验证 post-route timing 与功耗；只有集成实现出现明确内部坏路径时再重开 RTL 流水。

### 22.15 BDD 寄存存储压缩

在 200 MHz 约束综合已经达到 `WNS = +0.435 ns` 后，本轮不再删除距离流水级，而是压缩 BDD4/8/16/32 中与关键路径无关的重复存储。各层不再保存 `target_l_r/target_r_r`，直接从事务期间保持稳定的 `target_r` 取低、高手；候选快照也由两份全宽寄存器改为只保存新生成的 A 高半和 B 低半，A 低半复用 `y_l_r`，B 高半复用 `y_r_r`。

该变更按实际展开层级（包括两个常驻 BDD4 实例）合计减少 1,536 bit 显式寄存存储，不改变端口、周期数、定点环绕、严格 `<` 平局规则或 DSP 数量。BDD4 100 组随机回归、RCE tau3/tau4 与融合操作回归、以及 200 组随机加 2 组平局的距离等价回归均通过；实际 FF 数与约束时序需由下一轮 Vivado 综合报告确认。

### 22.16 分层首次子调用启动隔离

寄存存储压缩后的实测资源为 8,552 LUT、7,268 FF、40 DSP，相对压缩前回收 943 个综合 FF；功耗估算由 0.659 W 降到 0.582 W，但仍为 Low confidence。与此同时 WNS 从 +0.435 ns 回退到 -0.634 ns，TNS 为 -76.255 ns、失败端点 212 个。最差路径不经过距离运算，而是由 BDD32 状态位穿过 BDD16、BDD8 的同拍 `child_start` 组合传播，最终到达 BDD4 `target_r/tau_sel_r` 的 CE，5.252 ns 数据路径中路由占 73.9%。

BDD8、BDD16、BDD32 因此各增加一个显式首次子调用 launch 状态：父节点先在本层锁存事务，下一拍再由本层状态启动子节点，从结构上切断跨三级 start/CE 控制链。新增编码仍使用原有 4-bit 状态寄存器，不恢复已删除的宽目标或候选缓存；一次 BDD32 调用固定增加 21 拍，不改变算术、严格 `<` 平局规则、40 DSP 架构或外部握手。纯 Verilog 检查、BDD4 100 组、距离 200 随机加 2 平局及完整 RCE 回归均通过。

隔离后的 Vivado 2019.1 standalone 约束综合为 8,680 LUT、7,274 FF、40 DSP，5.000 ns 时钟下 WNS 为 +0.020 ns、TNS 为 0、setup 失败端点为 0；相对隔离前仅增加 6 FF，基本保留寄存压缩收益。最差路径缩短为单层 BDD32 状态到 BDD16 状态 CE，数据路径 4.598 ns、5 级 LUT、路由占 72.9%，QoR suggestions 为 `No Issues Found`。DRC 仍有 40 个非关键 MREG 建议及 standalone I/O/configuration 告警。功耗为 0.578 W、动态 0.446 W且置信度 Low。由于综合裕量仅 20 ps，该结果只能视为 standalone synthesis pass，不能视为实现级 sign-off；真实 RCE subsystem place/route 应至少争取 +0.2 至 +0.3 ns routed WNS，并检查软件固定超时能否容纳每个 BDD32 增加的 21 拍。

## 23. DS 辅助 HW/SW KAT 验证状态

DS 辅助加入了 openHiTLS KAT 解析、SW HAL、KEM 功能模型和 RTL cosim 验证链。KAT 输入共 9 组，ss16、ss24、ss32 各 3 组。

当前已确认：

| 验证项 | 结果 |
| --- | --- |
| KAT randM 驱动 SW MsgFunc roundtrip | 9/9 PASS |
| SHAKE256 本地重复一致性 | 9/9 PASS |
| RTL MsgEncode/MsgDecode HW/SW cosim | 2/2 PASS |
| C HAL 功能套件 | 8/8 PASS |
| 8-lane distance 与并行树随机等价 | 200/200 PASS |

需要注意：上述结果属于 KAT-derived MsgFunc 与 HW/SW 功能验证，不等同于完整官方 KAT。当前本地模型仍使用简化 A 生成/采样，尚未对全部 `pk/sk/ciphertext/shared secret` 做逐字节 expected-value 比较；本地 KEM 复跑还在 ss24 Encaps 出现 heap corruption。因此完整 openHiTLS KAT 状态应标记为 `NOT YET CLOSED`。

详细证据、复现入口和闭环任务见 `doc/SCLOUD_HW_SW_KAT_VERIFICATION.md`。
