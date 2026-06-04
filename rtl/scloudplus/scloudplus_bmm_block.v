`timescale 1ns/1ps
// Module: scloudplus_bmm_block
// Purpose: parameterized b x b block multiply for A_block * ternary_S_block mod 2^q.

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

    genvar row;
    genvar col;
    genvar lane;

    generate
        for (row = 0; row < B; row = row + 1) begin : g_row
            for (col = 0; col < B; col = col + 1) begin : g_col
                wire [B*Q_WIDTH-1:0] row_vec;
                wire [B*2-1:0]       col_vec;
                wire [Q_WIDTH-1:0]   pe_y;
                wire                 row_active;
                wire                 col_active;

                for (lane = 0; lane < B; lane = lane + 1) begin : g_gather
                    assign row_vec[lane*Q_WIDTH +: Q_WIDTH] = a_block[(row*B+lane)*Q_WIDTH +: Q_WIDTH];
                    assign col_vec[lane*2 +: 2]             = s_block[(lane*B+col)*2 +: 2];
                end

                assign row_active = (row[CFG_WIDTH-1:0] < cfg_b_active);
                assign col_active = (col[CFG_WIDTH-1:0] < cfg_b_active);

                scloudplus_bmm_pe #(
                    .B(B),
                    .Q_WIDTH(Q_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH),
                    .CFG_WIDTH(CFG_WIDTH)
                ) u_pe (
                    .cfg_b_active(cfg_b_active),
                    .cfg_q_active(cfg_q_active),
                    .cfg_coeff_mode(cfg_coeff_mode),
                    .a_vec(row_vec),
                    .s_vec(col_vec),
                    .y(pe_y)
                );

                assign c_block[(row*B+col)*Q_WIDTH +: Q_WIDTH] =
                    (row_active && col_active) ? pe_y : {Q_WIDTH{1'b0}};
            end
        end
    endgenerate

endmodule
