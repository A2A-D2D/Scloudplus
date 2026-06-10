`timescale 1ns/1ps
// Module: scloudplus_block_add
// Purpose: element-wise block addition modulo 2^q.

module scloudplus_block_add #(
    parameter B = 8,
    parameter Q_WIDTH = 12,
    parameter CFG_WIDTH = 8
) (
    input  wire [CFG_WIDTH-1:0]   cfg_q_active,
    input  wire [B*B*Q_WIDTH-1:0] a_block,
    input  wire [B*B*Q_WIDTH-1:0] b_block,
    output wire [B*B*Q_WIDTH-1:0] y_block
);

    wire [Q_WIDTH:0]   q_one_ext;
    wire [Q_WIDTH:0]   q_mask_ext;
    wire [Q_WIDTH-1:0] q_mask;
    genvar idx;
    localparam [CFG_WIDTH-1:0] Q_WIDTH_CFG = Q_WIDTH;

    assign q_one_ext  = {{Q_WIDTH{1'b0}}, 1'b1};
    assign q_mask_ext = (cfg_q_active >= Q_WIDTH_CFG) ? {1'b0, {Q_WIDTH{1'b1}}} :
                        ((q_one_ext << cfg_q_active) - {{Q_WIDTH{1'b0}}, 1'b1});
    assign q_mask     = q_mask_ext[Q_WIDTH-1:0];

    generate
        for (idx = 0; idx < B*B; idx = idx + 1) begin : g_add
            assign y_block[idx*Q_WIDTH +: Q_WIDTH] =
                (a_block[idx*Q_WIDTH +: Q_WIDTH] + b_block[idx*Q_WIDTH +: Q_WIDTH]) & q_mask;
        end
    endgenerate

endmodule
