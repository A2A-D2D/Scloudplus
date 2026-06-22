`timescale 1ns/1ps

/*
 * SPUV3 configuration SFR with Scloud+ MsgFunc address extensions.
 *
 * All parameter addresses are byte addresses.  sfr_addr is a 32-bit word
 * address, matching the current AHB bridge in spu_subsystem.
 *
 * Register map:
 *   +0x00 SPUV3_CFG
 *   +0x04 SPUV3_CFG_INT
 *   +0x08 SCLOUD_MSG_IN_BASE
 *   +0x0c SCLOUD_MSG_OUT_BASE
 *   +0x10 SCLOUD_Q_IN_BASE
 *   +0x14 SCLOUD_Q_AUX_BASE
 *   +0x18 SCLOUD_Q_OUT_BASE
 *
 * Scloud base values are 256-bit DPRAM word addresses.
 */
module spuv3_cfg_sfr_scloud
#(
    parameter SFR_CFG_BASE_ADDR       = 32'h0000_4000,
    parameter SFR_CFG_INT_BASE_ADDR   = SFR_CFG_BASE_ADDR + 32'h0000_0004,
    parameter SCLOUD_MSG_IN_ADDR      = SFR_CFG_BASE_ADDR + 32'h0000_0008,
    parameter SCLOUD_MSG_OUT_ADDR     = SFR_CFG_BASE_ADDR + 32'h0000_000c,
    parameter SCLOUD_Q_IN_ADDR        = SFR_CFG_BASE_ADDR + 32'h0000_0010,
    parameter SCLOUD_Q_AUX_ADDR       = SFR_CFG_BASE_ADDR + 32'h0000_0014,
    parameter SCLOUD_Q_OUT_ADDR       = SFR_CFG_BASE_ADDR + 32'h0000_0018,
    parameter SCLOUD_MSG_IN_RESET     = 32'h0000_0000,
    parameter SCLOUD_MSG_OUT_RESET    = 32'h0000_0004,
    parameter SCLOUD_Q_IN_RESET       = 32'h0000_0008,
    parameter SCLOUD_Q_AUX_RESET      = 32'h0000_0010,
    parameter SCLOUD_Q_OUT_RESET      = 32'h0000_0018
)
(
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    input  wire [31:0] sfr_addr,
    input  wire        sfr_write,
    input  wire [31:0] sfr_wdata,
    input  wire        sfr_sel,
    output reg  [31:0] sfr_rdata,

    input  wire [31:0] spuv3_wr_mstatus,
    input  wire        spuv3_cfg_clr,

    output reg  [31:0] spuv3_cfg,
    output reg  [31:0] spuv3_cfg_int,
    output reg  [31:0] scloud_msg_in_base,
    output reg  [31:0] scloud_msg_out_base,
    output reg  [31:0] scloud_q_in_base,
    output reg  [31:0] scloud_q_aux_base,
    output reg  [31:0] scloud_q_out_base
);

    wire spuv3_cfg_cs;
    wire spuv3_cfg_int_cs;
    wire scloud_msg_in_cs;
    wire scloud_msg_out_cs;
    wire scloud_q_in_cs;
    wire scloud_q_aux_cs;
    wire scloud_q_out_cs;

    wire spuv3_cfg_wr;
    wire spuv3_cfg_int_wr;
    wire scloud_msg_in_wr;
    wire scloud_msg_out_wr;
    wire scloud_q_in_wr;
    wire scloud_q_aux_wr;
    wire scloud_q_out_wr;

    assign spuv3_cfg_cs =
        sfr_sel && (sfr_addr == (SFR_CFG_BASE_ADDR >> 2));
    assign spuv3_cfg_int_cs =
        sfr_sel && (sfr_addr == (SFR_CFG_INT_BASE_ADDR >> 2));
    assign scloud_msg_in_cs =
        sfr_sel && (sfr_addr == (SCLOUD_MSG_IN_ADDR >> 2));
    assign scloud_msg_out_cs =
        sfr_sel && (sfr_addr == (SCLOUD_MSG_OUT_ADDR >> 2));
    assign scloud_q_in_cs =
        sfr_sel && (sfr_addr == (SCLOUD_Q_IN_ADDR >> 2));
    assign scloud_q_aux_cs =
        sfr_sel && (sfr_addr == (SCLOUD_Q_AUX_ADDR >> 2));
    assign scloud_q_out_cs =
        sfr_sel && (sfr_addr == (SCLOUD_Q_OUT_ADDR >> 2));

    assign spuv3_cfg_wr       = spuv3_cfg_cs       && sfr_write;
    assign spuv3_cfg_int_wr   = spuv3_cfg_int_cs   && sfr_write;
    assign scloud_msg_in_wr   = scloud_msg_in_cs   && sfr_write;
    assign scloud_msg_out_wr  = scloud_msg_out_cs  && sfr_write;
    assign scloud_q_in_wr     = scloud_q_in_cs     && sfr_write;
    assign scloud_q_aux_wr    = scloud_q_aux_cs    && sfr_write;
    assign scloud_q_out_wr    = scloud_q_out_cs    && sfr_write;

    /*
     * SPUV3_CFG:
     *   [31]    done, sticky until the next CFG write
     *   [30]    start
     *   [29:13] result/config field
     *   [12]    Scloud dec_write_q
     *   [11]    Scloud tau_sel
     *   [10:8]  Scloud block_count
     *   [7:0]   opcode
     *
     * SPUV3_CFG_INT:
     *   [0] interrupt enable
     *   [1] interrupt flag, write one to clear
     */
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            spuv3_cfg          <= 32'b0;
            spuv3_cfg_int      <= 32'b0;
            scloud_msg_in_base <= SCLOUD_MSG_IN_RESET;
            scloud_msg_out_base <= SCLOUD_MSG_OUT_RESET;
            scloud_q_in_base   <= SCLOUD_Q_IN_RESET;
            scloud_q_aux_base  <= SCLOUD_Q_AUX_RESET;
            scloud_q_out_base  <= SCLOUD_Q_OUT_RESET;
        end else begin
            spuv3_cfg_int[31:2] <= 30'b0;

            if (spuv3_cfg_clr) begin
                spuv3_cfg[31]   <= 1'b1;
                spuv3_cfg[30]   <= 1'b0;
                spuv3_cfg[29:8] <= spuv3_wr_mstatus[21:0];
                spuv3_cfg[7:0]  <= 8'b0;
                if (spuv3_cfg_int[0])
                    spuv3_cfg_int[1] <= 1'b1;
            end else begin
                if (spuv3_cfg_wr) begin
                    spuv3_cfg[31]   <= 1'b0;
                    spuv3_cfg[30:0] <= sfr_wdata[30:0];
                end

                if (spuv3_cfg_int_wr) begin
                    spuv3_cfg_int[0] <= sfr_wdata[0];
                    if (sfr_wdata[1])
                        spuv3_cfg_int[1] <= 1'b0;
                end
            end

            if (scloud_msg_in_wr)
                scloud_msg_in_base <= sfr_wdata;
            if (scloud_msg_out_wr)
                scloud_msg_out_base <= sfr_wdata;
            if (scloud_q_in_wr)
                scloud_q_in_base <= sfr_wdata;
            if (scloud_q_aux_wr)
                scloud_q_aux_base <= sfr_wdata;
            if (scloud_q_out_wr)
                scloud_q_out_base <= sfr_wdata;
        end
    end

    always @(*) begin
        sfr_rdata = 32'b0;
        if (!sfr_write) begin
            if (spuv3_cfg_cs)
                sfr_rdata = spuv3_cfg;
            else if (spuv3_cfg_int_cs)
                sfr_rdata = spuv3_cfg_int;
            else if (scloud_msg_in_cs)
                sfr_rdata = scloud_msg_in_base;
            else if (scloud_msg_out_cs)
                sfr_rdata = scloud_msg_out_base;
            else if (scloud_q_in_cs)
                sfr_rdata = scloud_q_in_base;
            else if (scloud_q_aux_cs)
                sfr_rdata = scloud_q_aux_base;
            else if (scloud_q_out_cs)
                sfr_rdata = scloud_q_out_base;
        end
    end

endmodule
