# Scloud+ MsgFunc 接入 `spu_subsystem` 顶层补丁说明

本文基于当前提供的 `spu_subsystem` 代码，说明 `scloud_msgfunc_rce_accel` 的真实插入位置、状态机修改、DPRAM Port A 仲裁和剩余依赖。

> 注意：当前提供的是粘贴文本，包含较多语法和命名错误，不能直接作为可编译源文件修改。下面代码应合入内网真实 `spu_subsystem.v`。

## 1. 已确认的接入位置

Scloud 加速器应接在：

```text
spuv3_cfg_sfr
  -> spu_subsystem opcode dispatch
  -> scloud_msgfunc_rce_accel
  -> DPRAM Port A mux
  -> spuv3_mems.dpram_a
```

不修改 VPU，不修改 `spuv3_core` 内部执行单元。

本方案中唯一进入 `spu_subsystem` 的 MsgFunc 算法顶层是：

```verilog
scloud_msgfunc_rce_accel
```

`spuv3_cfg_sfr_scloud` 是并列的寄存器模块，不是 MsgFunc 算法顶层。`scloud_bdd32_seq_rt` 等模块只能由 `scloud_msgfunc_rce_accel` 内部实例化。

使用 filelist：

```text
rtl/msgfunc/rce/scloud_msgfunc_rce.f
```

## 2. Opcode 定义

加入 subsystem localparam 或公共 defines：

```verilog
localparam [7:0] OPC_SCLOUD_MSGENC      = 8'h80;
localparam [7:0] OPC_SCLOUD_MSGDEC      = 8'h81;
localparam [7:0] OPC_SCLOUD_MSGENC_ADD  = 8'h82;
localparam [7:0] OPC_SCLOUD_SUB_MSGDEC  = 8'h83;
```

解码：

```verilog
wire is_scloud_op =
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGENC)     ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGDEC)     ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGENC_ADD) ||
    (spuv3_cfg[7:0] == OPC_SCLOUD_SUB_MSGDEC);

wire [1:0] scloud_op =
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGENC)     ? 2'd0 :
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGDEC)     ? 2'd1 :
    (spuv3_cfg[7:0] == OPC_SCLOUD_MSGENC_ADD) ? 2'd2 :
                                                2'd3;

wire       scloud_tau_sel     = spuv3_cfg[11];
wire [2:0] scloud_block_count = spuv3_cfg[10:8];
wire       scloud_dec_write_q = spuv3_cfg[12];
```

## 3. 固定 DPRAM 布局建议

当前仓库已新增 `spuv3_cfg_sfr_scloud.v`，支持五个可配置 base address。复位默认值仍采用以下固定 DPRAM word layout：

```verilog
localparam [31:0] SCLOUD_MSG_IN_BASE  = 32'h0000_0000;
localparam [31:0] SCLOUD_MSG_OUT_BASE = 32'h0000_0004;
localparam [31:0] SCLOUD_Q_IN_BASE    = 32'h0000_0008;
localparam [31:0] SCLOUD_Q_AUX_BASE   = 32'h0000_0010;
localparam [31:0] SCLOUD_Q_OUT_BASE   = 32'h0000_0018;
```

以上均为 256-bit DPRAM word address：

| 区域 | word 范围 | 最大占用 |
| --- | --- | --- |
| msg_in | 0-3 | 4 blocks |
| msg_out | 4-7 | 4 blocks |
| q_in | 8-15 | 4 x 2 words |
| q_aux | 16-23 | 4 x 2 words |
| q_out | 24-31 | 4 x 2 words |

共使用 32 个 256-bit word，即 1KB DPRAM。该区域可以与 RSA 工作区复用，但 RSA 与 Scloud 必须互斥运行。

## 4. Scloud 信号与实例

在 DPRAM Port A mux 前声明：

```verilog
wire        scloud_start;
wire        scloud_start_ready;
wire        scloud_busy;
wire        scloud_done;
wire        scloud_error;
wire        scloud_dpram_en;
wire        scloud_dpram_wr_en;
wire [31:0] scloud_dpram_be;
wire [31:0] scloud_dpram_addr;
wire [255:0] scloud_dpram_wdata;

reg scloud_active;
```

启动脉冲：

```verilog
assign scloud_start =
    (state == SPUV3_CFG) && is_scloud_op && scloud_start_ready;
```

实例化：

```verilog
scloud_msgfunc_rce_accel #(
    .DPRAM_ADDR_WIDTH(32),
    .Q_WIDTH         (12)
) u_scloud_msgfunc_rce_accel (
    .clk          (clk),
    .rst_n        (rst_n),
    .start        (scloud_start),
    .op           (scloud_op),
    .tau_sel      (scloud_tau_sel),
    .block_count  (scloud_block_count),
    .dec_write_q  (scloud_dec_write_q),
    .msg_in_base  (SCLOUD_MSG_IN_BASE),
    .msg_out_base (SCLOUD_MSG_OUT_BASE),
    .q_in_base    (SCLOUD_Q_IN_BASE),
    .q_aux_base   (SCLOUD_Q_AUX_BASE),
    .q_out_base   (SCLOUD_Q_OUT_BASE),
    .start_ready  (scloud_start_ready),
    .busy         (scloud_busy),
    .done         (scloud_done),
    .error        (scloud_error),
    .dpram_en     (scloud_dpram_en),
    .dpram_wr_en  (scloud_dpram_wr_en),
    .dpram_be     (scloud_dpram_be),
    .dpram_addr   (scloud_dpram_addr),
    .dpram_wdata  (scloud_dpram_wdata),
    .dpram_rdata  (dpram_rd_data_a)
);
```

## 5. `spuv3_core` 启动门控

当前代码直接把 `spuv3_cfg_en` 接到 `spuv3_core.cfg_enable_i`。Scloud opcode 期间必须禁止 core 接收该配置：

```verilog
wire spuv3_core_cfg_en = spuv3_cfg_en && !is_scloud_op;
```

修改实例：

```verilog
.cfg_enable_i(spuv3_core_cfg_en),
.cfg_data_i  (spuv3_cfg),
```

否则 Scloud opcode 会同时启动 SPU core 和 Scloud accelerator。

## 6. Active、done 与状态机修改

锁存当前算法属于 Scloud：

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scloud_active <= 1'b0;
    end else begin
        if ((state == SPUV3_CFG) && is_scloud_op)
            scloud_active <= 1'b1;
        else if (state == SPUV3_DONE)
            scloud_active <= 1'b0;
    end
end
```

原代码：

```verilog
assign spuv3_cfg_clr = spuv3_mstatus_o[31];
```

修改为：

```verilog
wire selected_alg_done = scloud_active ? scloud_done : spuv3_mstatus_o[31];
assign spuv3_cfg_clr = selected_alg_done;
```

状态机仍可保持：

```text
IDLE -> SPUV3_CFG -> SPUV3_WORKING -> SPUV3_DONE -> IDLE
```

但 `SPUV3_WORKING` 的退出条件必须使用 `selected_alg_done`。

顶层 busy/done：

```verilog
assign spu_busy = (state != IDLE);
assign spu_done = (state == SPUV3_DONE);
```

若 `spu_done` 需要中断使能门控：

```verilog
assign spu_done = (state == SPUV3_DONE) && spuv3_cfg_int[0];
```

## 7. DPRAM Port A mux 修改

当前 Port A 为 RSA/SPU core 二选一：

```verilog
assign dpram_en_a = rsa_ram_ena | spu_dpram_en_a;
```

修改为 RSA/Scloud/SPU core：

```verilog
assign dpram_en_a =
    rsa_ram_ena | scloud_dpram_en | spu_dpram_en_a;

assign dpram_be_a =
    rsa_ram_ena       ? rsa_ram_bea_mapped :
    scloud_dpram_en   ? scloud_dpram_be :
                         spu_dpram_be_a;

assign dpram_addr_a =
    rsa_ram_ena       ? {26'b0, rsa_ram_addra_mapped} :
    scloud_dpram_en   ? scloud_dpram_addr :
                         spu_dpram_addr_a;

assign dpram_wr_en_a =
    rsa_ram_ena       ? rsa_ram_wea :
    scloud_dpram_en   ? scloud_dpram_wr_en :
                         spu_dpram_wr_en_a;

assign dpram_wr_data_a =
    rsa_ram_ena       ? rsa_ram_dina_mapped :
    scloud_dpram_en   ? scloud_dpram_wdata :
                         spu_dpram_wr_data_a;
```

建议优先级：

```text
RSA > Scloud > SPU core
```

正常运行时应由 subsystem state 保证三者互斥，mux 优先级只是保护。

## 8. DPRAM Port B 必须修正

当前粘贴代码先定义了 `ahb_dpram_*`，但 Port B mux 使用了未定义的 `spu_dpram_*_b`：

```verilog
assign dpram_en_b = rsa_ram_enb | spu_dpram_en_b;
```

应改为：

```verilog
assign dpram_en_b = rsa_ram_enb | ahb_dpram_en_b;

assign dpram_be_b =
    rsa_ram_enb ? rsa_ram_beb_mapped : ahb_dpram_be_b;

assign dpram_addr_b =
    rsa_ram_enb ? {26'b0, rsa_ram_addrb_mapped} : ahb_dpram_addr_b;

assign dpram_wr_en_b =
    rsa_ram_enb ? rsa_ram_web : ahb_dpram_wr_en_b;

assign dpram_wr_data_b =
    rsa_ram_enb ? rsa_ram_dinb_mapped : ahb_dpram_wr_data_b;
```

Scloud 使用 Port A，不需要占用 Port B。Scloud busy 时现有 `dpram_clk_b_int` 通过 `spuv3_busy` 切到内部 `clk`，因此 `spu_busy`/内部 busy 状态必须正确覆盖 Scloud 运行周期。

## 9. 当前粘贴源码中的阻塞问题

在接入 Scloud 前，真实源码中需要确认以下问题是否只是粘贴错误：

1. `DLM_SIZE_KB` 错误引用 `SPUV3_DPRAM_SIZE_KB`，应检查是否应为 `SPUV3_DLM_SIZE_KB`。
2. `spuv3_alg_done/spuv3_done_int/spuv3_idone_int` 命名不一致。
3. 顶层端口是 `spu_busy/spu_done`，内部却使用 `spuv3_busy/spuv3_alg_done`。
4. `.cfg-data_i` 应为 `.cfg_data_i`。
5. 多处缺少逗号、分号、右括号和 `end`。
6. `spu_rsa_db-addr`、`spu_rsa_ad-addr` 含非法减号。
7. RSA M/H 两套信号在同一作用域重复声明。
8. `hwdata_sel` 重复声明且语义不同。
9. `dlm_din_extend/dlm_wdata_extend` 命名不一致。
10. `h_sel_qpram/h_sel_dpram` 命名不一致。
11. `dpran_hclk` 拼写错误，应为 `dpram_hclk`。
12. `u _dpram_b_clk_mux` 实例名中有空格。
13. `spuv3_cfg_sfr` 实例连接中 `.` 与 `,` 错误。
14. `spuv3_mstatus` 被赋值但未见声明。
15. Port B mux 使用未定义的 `spu_dpram_*_b`。

必须以真实内网源文件为准逐项确认。

## 10. 仍缺少的文件

当前仓库已提供：

```text
rtl/msgfunc/rce/spuv3_cfg_sfr_scloud.v
tb/rce/tb_spuv3_cfg_sfr_scloud.v
```

真实 RCE 侧还需要确认：

```text
SPUV3 memory/size defines 文件
真实 RCE filelist/sources.tcl
真实 spu_subsystem.v 可编译源码
```

接入时可以用 `spuv3_cfg_sfr_scloud` 替换原 `spuv3_cfg_sfr`，也可以把新增寄存器和修复逻辑手工合回原模块。

## 11. 推荐接入顺序

1. 先修正/确认 `spu_subsystem` 原有语法和命名问题。
2. 使用固定 1KB DPRAM layout 实例化 Scloud wrapper。
3. 完成 opcode dispatch 和 core cfg gate。
4. 完成 DPRAM Port A 三路 mux。
5. 修改状态机 done source，跑 polling 模式。
6. 再修改 `spuv3_cfg_sfr`，接通 interrupt/status。
7. 最后增加可配置 DPRAM base address。
