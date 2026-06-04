`timescale 1ns/1ps
// Module: scloudplus_bmm_pe
// Purpose: one Scloud+ block-matrix PE for sum_j A[i,j] * S[j,k] mod 2^q.

module scloudplus_bmm_pe #(
    parameter B = 8,
    parameter Q_WIDTH = 12,
    parameter ACC_WIDTH = 16,
    parameter CFG_WIDTH = 8
) (
    input  wire [CFG_WIDTH-1:0] cfg_b_active,
    input  wire [CFG_WIDTH-1:0] cfg_q_active,
    input  wire [1:0]           cfg_coeff_mode,
    input  wire [B*Q_WIDTH-1:0] a_vec,
    input  wire [B*2-1:0]       s_vec,
    output wire [Q_WIDTH-1:0]   y
);

    localparam [1:0] MODE_TERNARY = 2'd0;
    localparam [1:0] MODE_BINARY  = 2'd1;
    localparam [1:0] MODE_SIGNED2 = 2'd2;

    wire [Q_WIDTH-1:0] q_mask;
    wire [ACC_WIDTH-1:0] sum_stage [0:B];
    wire [Q_WIDTH-1:0] y_raw;
    genvar j;
    genvar bit_idx;

    assign sum_stage[0] = {ACC_WIDTH{1'b0}};

    generate
        for (bit_idx = 0; bit_idx < Q_WIDTH; bit_idx = bit_idx + 1) begin : g_q_mask
            assign q_mask[bit_idx] = (bit_idx[CFG_WIDTH-1:0] < cfg_q_active);
        end
    endgenerate

    generate
        for (j = 0; j < B; j = j + 1) begin : g_pre_add
            wire [Q_WIDTH-1:0] a_j;
            wire [1:0]         s_j;
            wire               lane_active;
            wire [Q_WIDTH-1:0] a_masked_j;
            wire [Q_WIDTH-1:0] neg_a_j;
            wire [Q_WIDTH-1:0] dbl_a_j;
            wire [Q_WIDTH-1:0] neg_dbl_a_j;
            reg  [Q_WIDTH-1:0] term_sel_j;
            wire [Q_WIDTH-1:0] term_j;

            assign a_j         = a_vec[j*Q_WIDTH +: Q_WIDTH];
            assign s_j         = s_vec[j*2 +: 2];
            assign lane_active = (j[CFG_WIDTH-1:0] < cfg_b_active);
            assign a_masked_j  = a_j & q_mask;
            assign neg_a_j     = ((~a_masked_j) + {{(Q_WIDTH-1){1'b0}}, 1'b1}) & q_mask;
            assign dbl_a_j     = (a_masked_j << 1) & q_mask;
            assign neg_dbl_a_j = ((~dbl_a_j) + {{(Q_WIDTH-1){1'b0}}, 1'b1}) & q_mask;

            always @(*) begin
                term_sel_j = {Q_WIDTH{1'b0}};
                case (cfg_coeff_mode)
                    MODE_TERNARY: begin
                        if (s_j == 2'b01) begin
                            term_sel_j = a_masked_j;
                        end else if (s_j == 2'b10) begin
                            term_sel_j = neg_a_j;
                        end
                    end
                    MODE_BINARY: begin
                        if (s_j[0]) begin
                            term_sel_j = a_masked_j;
                        end
                    end
                    MODE_SIGNED2: begin
                        if (s_j == 2'b01) begin
                            term_sel_j = a_masked_j;
                        end else if (s_j == 2'b10) begin
                            term_sel_j = neg_dbl_a_j;
                        end else if (s_j == 2'b11) begin
                            term_sel_j = neg_a_j;
                        end
                    end
                    default: begin
                        if (s_j == 2'b01) begin
                            term_sel_j = a_masked_j;
                        end else if (s_j == 2'b10) begin
                            term_sel_j = neg_a_j;
                        end
                    end
                endcase
            end

            assign term_j = lane_active ? term_sel_j : {Q_WIDTH{1'b0}};
            assign sum_stage[j+1] = sum_stage[j] + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term_j};
        end
    endgenerate

    assign y_raw = sum_stage[B][Q_WIDTH-1:0];
    assign y = y_raw & q_mask;

endmodule
