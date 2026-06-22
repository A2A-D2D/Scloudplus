# Scloud+ MsgEnc/MsgDec 接入 SPUV3 RCE 说明

本文记录 Scloud+ Barnes-Wall MsgEnc/MsgDec 加速器接入 SPUV3 RCE 的当前实现。目标是在保持 RCE 既有 SFR/DPRAM/RSA 类旁路模型的前提下获得较好的 PPA；不把 384/512-bit BW32 数据强行塞入 320-bit VPU VR 通路，也不复用 RSA 算法 datapath。当前基线已经完成 factor-8 半展开与 BDD32/BDD16 8-lane 精确距离共享，综合结果为 9,271 LUT、4,471 FF、48 DSP48。

## 1. 接入原则

第一版建议把 Scloud+ MsgFunc 作为 RCE top-level 的 DPRAM 旁路加速单元接入：

```text
Host / SPU core 配置 SFR
  -> spu_subsystem opcode dispatch
  -> scloud_msgfunc_rce_accel
  -> DPRAM Port A
  -> Scloud+ MsgEnc / MsgDec BW32 engine
```

数据面走 DPRAM，不走 SFR。SFR 只承担 opcode、tau、block_count、base address 和 done/int 状态。这样符合 RCE “控制寄存器少量配置 + 本地 SRAM 承载 payload”的模型。

第一版不建议走 VPU/VR，原因是：

- SPUV3 VR 是 320-bit，Scloud+ BW32 Q block 是 32 x 12 = 384-bit，软件自然布局是 32 x uint16 = 512-bit，宽度不匹配。
- MsgDecode 的 BDD 是递归选择、phi 变换和分层共享距离计算，不是规则 SIMD lane 算术。
- 每次 KEM 只有 2 或 4 个 BW32 block，VPU 指令拆分和 VR pack/unpack 开销摊销不划算。
- 如果最后在 VPU 内部再挂一个 Scloud 专用 BDD 子单元，控制复杂度反而高于直接挂在 DPRAM 旁路。

第一版也不建议复用 RSA datapath。RSA 的可复用部分是 top-level 挂接风格、DPRAM 仲裁方式、busy/done/int 模型；RSA 大数乘法/模幂 datapath 与 Barnes-Wall BDD 无关。

## 2. 当前仓库需要带入真实 RCE 的 RTL 文件

### 2.1 第一版最小接入集合

真实 RCE 工程最少需要带入以下文件：

| 文件 | 是否必须 | 作用 |
| --- | --- | --- |
| `rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v` | 必须 | RCE-facing DPRAM wrapper，负责 op/tau/block 调度、DPRAM 读写、Q block pack/unpack、add/sub 融合 |
| `rtl/msgfunc/param/scloud_msgfunc_param.v` | 必须 | C-model aligned MsgEnc/MsgDec 参数化主实现，包含 tau=3/4 bit packing、phi encode/decode、label/Q 转换 |
| `rtl/msgfunc/bdd/scloud_bdd_seq_rt.v` | 必须 | Runtime-tau factor-8 BDD，BDD32/BDD16 单 child 四阶段复用，接入 8-lane distance engine |
| `rtl/msgfunc/bdd/scloud_bdd_recursive.v` | 必须 | BDD 公共 helper：phi、inv_phi、并行/顺序 distance、round 基础模块 |

这组文件负责把 Scloud+ 的单 BW32 block MsgEnc/MsgDec 接成 RCE 可启动的多 block DPRAM 加速器。

旧 fixed-tau sequential BDD 文件 `scloud_bdd32_seq.v/scloud_bdd16_seq.v/scloud_bdd8_seq.v/scloud_bdd4_seq.v` 不再是 RCE wrapper 必需依赖，可保留在验证目录中与 runtime-tau BDD 做回归对比。

### 2.2 建议一并带入的验证文件

| 文件 | 是否必须 | 作用 |
| --- | --- | --- |
| `tb/rce/tb_scloud_msgfunc_rce_accel.v` | 建议 | 当前 wrapper 的最小自检，含 256-bit DPRAM 同步读写模型 |
| `tb/param/tb_scloud_msgfunc_param.v` | 建议 | 原始 MsgFunc 参数化路径 tau=3/tau=4 roundtrip 验证 |
| `tb/param/tb_scloud_msgfunc_cfg_reg.v` | 可选 | 原 runtime BW8/BW16/BW32 wrapper 验证，可作为行为参考 |

### 2.3 暂不建议带入真实 RCE 的文件

以下 legacy 文件使用旧参数或演示路径，不建议作为 RCE 集成依据：

- `archive/legacy_msgfunc/rtl/bw32_*`
- `archive/legacy_msgfunc/rtl/bw16/*`
- `archive/legacy_msgfunc/rtl/bw8/*`

原因是 legacy 路径使用的参数与 C-model aligned 主线不同，例如旧 `Q_WIDTH=10`、`TAU=2`，不匹配当前 Scloud+ KEM 参数。

## 3. 当前新增 wrapper 职责

`scloud_msgfunc_rce_accel.v` 是真实 RCE 中推荐直接实例化的边界模块。它负责：

```text
唯一 MsgFunc 算法顶层：scloud_msgfunc_rce_accel
```

`spuv3_cfg_sfr_scloud` 是与其并列的可选 SFR 扩展模块，不是算法顶层。`scloud_bdd32_seq_rt`、`scloud_msgenc_param`、`q_to_label/phi_decode/label_to_msg` 均为内部子模块，不能作为 RCE synthesis top。

- 接收 RCE top-level 解码后的 `start/op/tau_sel/block_count`。
- 从 DPRAM 读取 message block、Q block、aux Q block。
- 把两个 256-bit DPRAM word 还原成 32 x 12-bit Q 坐标。
- 根据 `tau_sel` 选择 tau=3 或 tau=4 MsgEnc/MsgDec。
- 支持 2 或 4 个 BW32 block 顺序处理。
- 支持 `MSGENC_ADD` 和 `SUB_MSGDEC` 两个 PPA 融合操作。
- 支持 `dec_write_q` 控制 decode 类 op 是否写回 rounded Q；Decaps 只需要 message 时可关闭以减少 DPRAM 写回。
- 把结果写回 DPRAM，并输出 `busy/done/error`。

当前 wrapper 内部实例化：

```text
scloud_msgenc_param tau=3
scloud_msgenc_param tau=4
scloud_bdd32_seq_rt       ; one shared runtime-tau factor-8 BDD
  scloud_bdd16_seq_rt     ; one child reused for YL/YR/ZA/ZB
    scloud_bdd8_seq_rt    ; resident lower-level kernel
  u_dist_seq x 2          ; exact 8-lane EdC at BDD32/BDD16
q_to_label/phi_decode/label_to_msg tau=3
q_to_label/phi_decode/label_to_msg tau=4
```

其中 MsgEnc 基本是组合路径；MsgDec 的面积大头 BDD 已经合并为一套 runtime-tau datapath，并通过 factor-8 层级复用和 8-lane 高层距离共享把 DSP 从 256 降到 48。tau3/tau4 仍各保留一套轻量 label/message 后处理，避免把 C-model aligned 的硬编码 bit packing 变成复杂动态网络。

工程 filelist：

```text
rtl/msgfunc/rce/scloud_msgfunc_rce.f
```

综合/elaboration 必须显式指定：

```text
top = scloud_msgfunc_rce_accel
```

## 4. 新增 RCE opcode 建议

wrapper 内部使用 2-bit op：

```verilog
localparam [1:0] OP_MSGENC     = 2'd0;
localparam [1:0] OP_MSGDEC     = 2'd1;
localparam [1:0] OP_MSGENC_ADD = 2'd2;
localparam [1:0] OP_SUB_MSGDEC = 2'd3;
```

真实 RCE SFR 仍建议使用 8-bit opcode，示例：

```verilog
localparam [7:0] OPC_SCLOUD_MSGENC      = 8'h80;
localparam [7:0] OPC_SCLOUD_MSGDEC      = 8'h81;
localparam [7:0] OPC_SCLOUD_MSGENC_ADD  = 8'h82;
localparam [7:0] OPC_SCLOUD_SUB_MSGDEC  = 8'h83;
```

含义如下：

| opcode | 作用 | 写 msg_out | 写 q_out |
| --- | --- | --- | --- |
| `OPC_SCLOUD_MSGENC` | `q_out = MsgEnc(msg_in)` | 否 | 是 |
| `OPC_SCLOUD_MSGDEC` | `msg_out = MsgDec(q_in)`，`dec_write_q=1` 时写 rounded Q | 是 | 可选 |
| `OPC_SCLOUD_MSGENC_ADD` | `q_out = q_in + MsgEnc(msg_in) mod 2^12` | 否 | 是 |
| `OPC_SCLOUD_SUB_MSGDEC` | `msg_out = MsgDec(q_in - q_aux)`，`dec_write_q=1` 时写 rounded Q | 是 | 可选 |

## 5. SFR 配置建议

如果沿用现有 `spuv3_cfg[31:0]`，建议：

```text
spuv3_cfg[31]    done，由硬件置位或通过 cfg_clr 更新
spuv3_cfg[30]    start
spuv3_cfg[29:12] reserved / result_len
spuv3_cfg[11]    tau_sel, 0=tau3, 1=tau4
spuv3_cfg[10:8]  block_count, legal value: 2 or 4
spuv3_cfg[7:0]   opcode
```

地址可以先使用固定 DPRAM layout。若希望软件灵活调度 KEM 中间矩阵，建议新增 SFR：

| SFR | 作用 |
| --- | --- |
| `SCLOUD_MSG_IN_BASE` | message input 的 256-bit word base address |
| `SCLOUD_MSG_OUT_BASE` | message output 的 256-bit word base address |
| `SCLOUD_Q_IN_BASE` | Q input 的 256-bit word base address |
| `SCLOUD_Q_AUX_BASE` | SUB_MSGDEC 的第二个 Q operand |
| `SCLOUD_Q_OUT_BASE` | Q output 的 256-bit word base address |

这些 base address 都是 DPRAM 256-bit word 地址，不是 byte 地址。

## 6. DPRAM 数据布局

### 6.1 message block

每个 BW32 message block 占一个 256-bit DPRAM word：

```text
address = msg_base + block_idx
tau=3 uses word[63:0]
tau=4 uses word[95:0]
```

写回时 byte enable：

```text
tau=3: dpram_be = 32'h000000ff
tau=4: dpram_be = 32'h00000fff
```

### 6.2 Q block

每个 BW32 Q block 按 32 个 `uint16_t` 存储，占两个 256-bit DPRAM word：

```text
address low  half = q_base + block_idx*2
address high half = q_base + block_idx*2 + 1
```

每个 256-bit word 存 16 个 `uint16_t` lane：

```text
lane[i][11:0]  = Q coordinate
lane[i][15:12] = ignored on read, written as zero on wrapper writeback
```

这样与当前 HAL/C 侧 `uint16_t[32]` 的数组形态一致，RCE 侧也只需两拍读写一个 BW32 Q block。

## 7. `spu_subsystem` 接入方式

### 7.1 opcode dispatch

在 `spu_subsystem` 中增加 Scloud opcode 判断：

```verilog
wire is_scloud_op =
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGENC)     ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGDEC)     ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGENC_ADD) ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_SUB_MSGDEC);
```

当 `is_scloud_op` 为 1 时，不启动 `spuv3_core` 执行路径，而是启动 `scloud_msgfunc_rce_accel`：

```text
spuv3_cfg_en && is_scloud_op -> scloud_start
spuv3_cfg_en && !is_scloud_op -> original core/RSA path
```

done 选择：

```text
alg_done = scloud_active ? scloud_done : spuv3_mstatus_o[31]
```

`spuv3_busy` 需要包含 `scloud_busy`，避免 host 在 Scloud 运行期间访问 DPRAM。

### 7.2 DPRAM Port A mux

建议在现有 RSA mux 后增加 Scloud 分支：

```verilog
assign dpram_en_a =
    rsa_ram_ena | scloud_dpram_en | spu_dpram_en_a;

assign dpram_wr_en_a =
    rsa_ram_ena       ? rsa_ram_wea :
    scloud_dpram_en   ? scloud_dpram_wr_en :
                         spu_dpram_wr_en_a;

assign dpram_be_a =
    rsa_ram_ena       ? rsa_ram_bea_mapped :
    scloud_dpram_en   ? scloud_dpram_be :
                         spu_dpram_be_a;

assign dpram_addr_a =
    rsa_ram_ena       ? {26'b0, rsa_ram_addra_mapped} :
    scloud_dpram_en   ? scloud_dpram_addr :
                         spu_dpram_addr_a;

assign dpram_wr_data_a =
    rsa_ram_ena       ? rsa_ram_dina_mapped :
    scloud_dpram_en   ? scloud_dpram_wdata :
                         spu_dpram_wr_data_a;
```

优先级建议为：

```text
RSA > Scloud > SPU core
```

更好的方式是通过 subsystem state 保证三者互斥；mux 优先级只是兜底。

## 8. `scloud_msgfunc_rce_accel` 顶层接口

方向以 wrapper 模块为准：

| 信号 | 方向 | 位宽 | 作用 |
| --- | --- | --- | --- |
| `clk` | IN | 1 | RCE 内部工作时钟 |
| `rst_n` | IN | 1 | 低有效复位 |
| `start` | IN | 1 | 启动脉冲，`start_ready=1` 时接受 |
| `op` | IN | 2 | 0=`MSGENC`，1=`MSGDEC`，2=`MSGENC_ADD`，3=`SUB_MSGDEC` |
| `tau_sel` | IN | 1 | 0=tau3，1=tau4 |
| `block_count` | IN | 3 | BW32 block 数，合法值建议 2 或 4 |
| `dec_write_q` | IN | 1 | decode 类 op 是否写回 rounded Q；Decaps 只需 msg 时建议置 0 |
| `msg_in_base` | IN | parameter | message input base，DPRAM word address |
| `msg_out_base` | IN | parameter | message output base，DPRAM word address |
| `q_in_base` | IN | parameter | Q input base，DPRAM word address |
| `q_aux_base` | IN | parameter | auxiliary Q input base，DPRAM word address |
| `q_out_base` | IN | parameter | Q output base，DPRAM word address |
| `start_ready` | OUT | 1 | wrapper 空闲、可接受 start |
| `busy` | OUT | 1 | wrapper 正在处理 |
| `done` | OUT | 1 | 完成脉冲 |
| `error` | OUT | 1 | 当前只检查非法 block_count |
| `dpram_en` | OUT | 1 | DPRAM 访问使能 |
| `dpram_wr_en` | OUT | 1 | DPRAM 写使能 |
| `dpram_be` | OUT | 32 | 256-bit word 的 byte enable |
| `dpram_addr` | OUT | parameter | DPRAM word address |
| `dpram_wdata` | OUT | 256 | DPRAM write data |
| `dpram_rdata` | IN | 256 | DPRAM read data |

参数：

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `DPRAM_ADDR_WIDTH` | 16 | DPRAM word address 位宽 |
| `Q_WIDTH` | 12 | Q 坐标位宽，当前 Scloud+ 固定为 12 |

## 9. PPA 方案比较

| 方案 | 面积 | 性能 | 集成风险 | 结论 |
| --- | --- | --- | --- | --- |
| VPU/VR 接入 | 中高 | 不稳定，pack/unpack 开销大 | 高 | 不建议首选 |
| RSA datapath 复用 | 高 | 不匹配算法 | 高 | 不建议 |
| 独立 AHB/AXI 外设 | 中 | 总线搬运多 | 中 | 不适合 RCE 内部集成 |
| DPRAM/RSA-like 旁路 + Scloud 专用 engine | 中 | 最直接利用本地 SRAM | 中低 | 推荐 |

当前 wrapper 已经把 PPA 最有价值的两个融合 opcode 放进去：

```text
MSGENC_ADD:
  Encaps 中直接做 C2 = C2 + MsgEnc(msg)
  避免单独写 matrixM，再由主核读 matrixM 做 sw_add_mod_q

SUB_MSGDEC:
  Decaps 中直接做 MsgDecode(C2 - temp)
  避免单独写 diff，再读 diff 做 MsgDecode
```

此外 wrapper 已做三项面积/效率优化：

- 去掉 384-bit Q result 暂存寄存器，写回 DPRAM 时直接从 MsgEnc/add/BDD rounded 结果组合选择，减少一组 384-bit flop。
- decode 类 op 新增 `dec_write_q`，当 Decaps 只需要 recovered message 时可置 0，每个 BW32 block 少 2 拍 DPRAM 写回，也减少 256-bit 总线翻转。
- tau3/tau4 MsgDec 不再各自实例化一套 BW32 BDD，改为 `scloud_bdd32_seq_rt` 一套 runtime-tau BDD，共享 BW32/BW16/BW8/BW4 递归 datapath。

## 10. 验证方式

当前仓库已新增最小自检：

```text
tb/rce/tb_scloud_msgfunc_rce_accel.v
```

运行命令：

```bash
iverilog -g2001 -Wall -o sim_build/tb_scloud_msgfunc_rce_accel.vvp \
  rtl/msgfunc/bdd/*.v \
  rtl/msgfunc/param/scloud_msgfunc_param.v \
  rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v \
  tb/rce/tb_scloud_msgfunc_rce_accel.v

vvp sim_build/tb_scloud_msgfunc_rce_accel.vvp
```

已覆盖：

- tau=3，2 blocks，`MSGENC -> MSGDEC` roundtrip。
- tau=4，2 blocks，`MSGENC_ADD -> SUB_MSGDEC` fused roundtrip。
- 256-bit DPRAM 同步读模型。
- 32 x uint16 Q block lane packing。
- 64-bit/96-bit message writeback byte enable。
- `dec_write_q=0` 的高效 decode 路径。

当前结果：

```text
TEST 1: tau3 MSGENC -> MSGDEC
OK tau3 block=0 msg=0123456789abcdef
OK tau3 block=1 msg=fedcba9876543210
TEST 2: tau4 MSGENC_ADD -> SUB_MSGDEC
OK tau4 block=0 msg=13579bdffdb97531a5a55a5a
OK tau4 block=1 msg=c001d00d0123456789abcdef
TB_PASS scloud_msgfunc_rce_accel
```

同时已用纯 Verilog 检查脚本检查：

```text
rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v
rtl/msgfunc/bdd/scloud_bdd_seq_rt.v
tb/rce/tb_scloud_msgfunc_rce_accel.v
```

结果均为：

```text
[OK] No common SystemVerilog-only tokens or style issues were found.
```

## 11. 后续真实 RCE 集成检查项

真实内网 RCE 工程接线时建议重点检查：

- SFR `spuv3_cfg_int_wr` 不能自引用，应由 chip-select 与 write 生成。
- `spuv3_cfg[29:8]` 与代码中 result/config bit slice 要统一，不要混成 `[28:7]`。
- SFR byte address 与 word address 要统一，`SFR_CFG_INT_BASE_ADDR` 建议按 byte `+4`，比较时再 `>>2`。
- Scloud 运行期间 host 不能通过 AHB DPRAM Port B 访问同一 DPRAM。
- RSA/Scloud/SPU core 对 DPRAM Port A 必须互斥，或有明确优先级。
- `scloud_done` 要进入原有 done/int/status 路径，不能只拉 wrapper 内部 done。
- tau=3/tau=4 的 message byte enable 与软件 pack/unpack 一致。
- `SUB_MSGDEC` 的 mod 2^12 减法必须保持 12-bit wrap，不要做饱和减法。
- BDD tie-breaking 必须保持当前 RTL/C-model aligned 的 strict `<`，不要改成 `<=`。

## 12. 建议落地顺序

1. 把 `scloud_msgfunc_rce_accel.v` 和 MsgFunc/Bdd 依赖加入真实 RCE filelist。
2. 在 `spu_subsystem` 增加 Scloud opcode decode 和 `scloud_start`。
3. 增加 DPRAM Port A mux 分支，先只跑 `MSGENC`/`MSGDEC`。
4. 接通 `done/busy/int` 状态，确认 host busy 期间不能访问 DPRAM。
5. 再打开 `MSGENC_ADD`/`SUB_MSGDEC`，把 KEM 中间矩阵区域直接作为 q base。
6. 加真实 RCE 仿真：2-block tau=3、2-block tau=4、4-block tau=3。
7. 加入真实 RCE 时钟约束并做 subsystem 综合；只有约束后时序仍紧，才对 8-lane distance 或 select 阶段加流水。

## 13. 最新 PPA 与 HW/SW 验证状态

当前 Vivado 2019.1、XC7A200T、顶层 `scloud_msgfunc_rce_accel` 的最终综合结果为：

```text
Total LUT = 9,271
FF        = 4,471
DSP48     = 48
BDD LUT   = 7,351
BDD FF    = 3,394
```

相对最初 19,515 LUT、7,050 FF、256 DSP 的全并行版本，LUT 下降 52.5%，FF 下降 36.6%，DSP 下降 81.25%。功耗报告为 213.135 W，但因缺少时钟和活动约束且置信度为 Low，只能用于判断下降方向；Timing 仍无有效 WNS/TNS。

DS 辅助 HW/SW 验证链已经确认 9/9 KAT-derived SW MsgFunc roundtrip 和 2/2 RTL/SW MsgFunc cosim。完整 openHiTLS `pk/sk/ct/ss` 逐字节 KAT 尚未闭环，具体边界和后续任务见 `doc/SCLOUD_HW_SW_KAT_VERIFICATION.md`。
