`timescale 1ns/1ps
// Module: scloudplus_bmm_block
// Purpose: fixed 8x8 block multiply using explicit PE instances.

module scloudplus_bmm_block #(
    parameter B = 8,
    parameter Q_WIDTH = 12,
    parameter ACC_WIDTH = 16,
    parameter CFG_WIDTH = 8
) (
    input  wire [CFG_WIDTH-1:0]   cfg_b_active,
    input  wire [CFG_WIDTH-1:0]   cfg_q_active,
    input  wire [1:0]             cfg_coeff_mode,
    input  wire [B*B*Q_WIDTH-1:0] a_block,
    input  wire [B*B*2-1:0]       s_block,
    output wire [B*B*Q_WIDTH-1:0] c_block
);

`define SCLOUDPLUS_ROW_VEC(R) \
    {a_block[((R)*8+7)*Q_WIDTH +: Q_WIDTH], a_block[((R)*8+6)*Q_WIDTH +: Q_WIDTH], \
     a_block[((R)*8+5)*Q_WIDTH +: Q_WIDTH], a_block[((R)*8+4)*Q_WIDTH +: Q_WIDTH], \
     a_block[((R)*8+3)*Q_WIDTH +: Q_WIDTH], a_block[((R)*8+2)*Q_WIDTH +: Q_WIDTH], \
     a_block[((R)*8+1)*Q_WIDTH +: Q_WIDTH], a_block[((R)*8+0)*Q_WIDTH +: Q_WIDTH]}

`define SCLOUDPLUS_COL_VEC(C) \
    {s_block[(7*8+(C))*2 +: 2], s_block[(6*8+(C))*2 +: 2], \
     s_block[(5*8+(C))*2 +: 2], s_block[(4*8+(C))*2 +: 2], \
     s_block[(3*8+(C))*2 +: 2], s_block[(2*8+(C))*2 +: 2], \
     s_block[(1*8+(C))*2 +: 2], s_block[(0*8+(C))*2 +: 2]}

`define SCLOUDPLUS_PE(R,C) \
    wire [Q_WIDTH-1:0] pe_``R``_``C``_y; \
    scloudplus_bmm_pe #(.B(8), .Q_WIDTH(Q_WIDTH), .ACC_WIDTH(ACC_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_pe_``R``_``C`` ( \
        .cfg_b_active(cfg_b_active), .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), \
        .a_vec(`SCLOUDPLUS_ROW_VEC(R)), .s_vec(`SCLOUDPLUS_COL_VEC(C)), .y(pe_``R``_``C``_y)); \
    assign c_block[((R)*8+(C))*Q_WIDTH +: Q_WIDTH] = ((cfg_b_active > (R)) && (cfg_b_active > (C))) ? pe_``R``_``C``_y : {Q_WIDTH{1'b0}};

    `SCLOUDPLUS_PE(0,0) `SCLOUDPLUS_PE(0,1) `SCLOUDPLUS_PE(0,2) `SCLOUDPLUS_PE(0,3)
    `SCLOUDPLUS_PE(0,4) `SCLOUDPLUS_PE(0,5) `SCLOUDPLUS_PE(0,6) `SCLOUDPLUS_PE(0,7)
    `SCLOUDPLUS_PE(1,0) `SCLOUDPLUS_PE(1,1) `SCLOUDPLUS_PE(1,2) `SCLOUDPLUS_PE(1,3)
    `SCLOUDPLUS_PE(1,4) `SCLOUDPLUS_PE(1,5) `SCLOUDPLUS_PE(1,6) `SCLOUDPLUS_PE(1,7)
    `SCLOUDPLUS_PE(2,0) `SCLOUDPLUS_PE(2,1) `SCLOUDPLUS_PE(2,2) `SCLOUDPLUS_PE(2,3)
    `SCLOUDPLUS_PE(2,4) `SCLOUDPLUS_PE(2,5) `SCLOUDPLUS_PE(2,6) `SCLOUDPLUS_PE(2,7)
    `SCLOUDPLUS_PE(3,0) `SCLOUDPLUS_PE(3,1) `SCLOUDPLUS_PE(3,2) `SCLOUDPLUS_PE(3,3)
    `SCLOUDPLUS_PE(3,4) `SCLOUDPLUS_PE(3,5) `SCLOUDPLUS_PE(3,6) `SCLOUDPLUS_PE(3,7)
    `SCLOUDPLUS_PE(4,0) `SCLOUDPLUS_PE(4,1) `SCLOUDPLUS_PE(4,2) `SCLOUDPLUS_PE(4,3)
    `SCLOUDPLUS_PE(4,4) `SCLOUDPLUS_PE(4,5) `SCLOUDPLUS_PE(4,6) `SCLOUDPLUS_PE(4,7)
    `SCLOUDPLUS_PE(5,0) `SCLOUDPLUS_PE(5,1) `SCLOUDPLUS_PE(5,2) `SCLOUDPLUS_PE(5,3)
    `SCLOUDPLUS_PE(5,4) `SCLOUDPLUS_PE(5,5) `SCLOUDPLUS_PE(5,6) `SCLOUDPLUS_PE(5,7)
    `SCLOUDPLUS_PE(6,0) `SCLOUDPLUS_PE(6,1) `SCLOUDPLUS_PE(6,2) `SCLOUDPLUS_PE(6,3)
    `SCLOUDPLUS_PE(6,4) `SCLOUDPLUS_PE(6,5) `SCLOUDPLUS_PE(6,6) `SCLOUDPLUS_PE(6,7)
    `SCLOUDPLUS_PE(7,0) `SCLOUDPLUS_PE(7,1) `SCLOUDPLUS_PE(7,2) `SCLOUDPLUS_PE(7,3)
    `SCLOUDPLUS_PE(7,4) `SCLOUDPLUS_PE(7,5) `SCLOUDPLUS_PE(7,6) `SCLOUDPLUS_PE(7,7)

`undef SCLOUDPLUS_PE
`undef SCLOUDPLUS_COL_VEC
`undef SCLOUDPLUS_ROW_VEC

endmodule
