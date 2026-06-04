`timescale 1ns/1ps
// Module: scloudplus_block_add
// Purpose: element-wise block addition modulo 2^q.

module scloudplus_block_add #(
    parameter B = 8,
    parameter Q_WIDTH = 12,
    parameter CFG_WIDTH = 8
) (
    input  wire [CFG_WIDTH-1:0]     cfg_q_active,
    input  wire [B*B*Q_WIDTH-1:0] a_block,
    input  wire [B*B*Q_WIDTH-1:0] b_block,
    output wire [B*B*Q_WIDTH-1:0] y_block
);

    wire [Q_WIDTH-1:0] q_mask;
    genvar p;
    genvar bit_idx;

    generate
        for (bit_idx = 0; bit_idx < Q_WIDTH; bit_idx = bit_idx + 1) begin : g_q_mask
            assign q_mask[bit_idx] = (bit_idx[CFG_WIDTH-1:0] < cfg_q_active);
        end
    endgenerate

    generate
        for (p = 0; p < B*B; p = p + 1) begin : g_add
            assign y_block[p*Q_WIDTH +: Q_WIDTH] = (a_block[p*Q_WIDTH +: Q_WIDTH] + b_block[p*Q_WIDTH +: Q_WIDTH]) & q_mask;
        end
    endgenerate

endmodule
