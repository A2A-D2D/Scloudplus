`timescale 1ns/1ps
// Module: scloudplus_bmm_block
// Purpose: one-cycle b x b block multiply for A_block * ternary_S_block mod 2^q.

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

    genvar i;
    genvar k;
    genvar j;

    generate
        for (i = 0; i < B; i = i + 1) begin : g_row
            for (k = 0; k < B; k = k + 1) begin : g_col
                wire [B*Q_WIDTH-1:0] row_vec;
                wire [B*2-1:0]       col_vec;
                wire [Q_WIDTH-1:0]   pe_y;
                wire                 row_active;
                wire                 col_active;

                for (j = 0; j < B; j = j + 1) begin : g_gather
                    assign row_vec[j*Q_WIDTH +: Q_WIDTH] = a_block[(i*B+j)*Q_WIDTH +: Q_WIDTH];
                    assign col_vec[j*2 +: 2]             = s_block[(j*B+k)*2 +: 2];
                end

                assign row_active = (i[CFG_WIDTH-1:0] < cfg_b_active);
                assign col_active = (k[CFG_WIDTH-1:0] < cfg_b_active);

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

                assign c_block[(i*B+k)*Q_WIDTH +: Q_WIDTH] = (row_active && col_active) ? pe_y : {Q_WIDTH{1'b0}};
            end
        end
    endgenerate

endmodule
