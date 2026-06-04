`timescale 1ns/1ps
// Module: scloudplus_bmm_pe
// Purpose: parameterized Scloud+ PE for sum_j A[i,j] * S[j,k] mod 2^q.

module scloudplus_bmm_term #(
    parameter Q_WIDTH = 12,
    parameter CFG_WIDTH = 8
) (
    input  wire [CFG_WIDTH-1:0] cfg_q_active,
    input  wire [1:0]           cfg_coeff_mode,
    input  wire                 lane_active,
    input  wire [Q_WIDTH-1:0]   a_value,
    input  wire [1:0]           s_value,
    output wire [Q_WIDTH-1:0]   term_value
);

    localparam [1:0] MODE_TERNARY = 2'd0;
    localparam [1:0] MODE_BINARY  = 2'd1;
    localparam [1:0] MODE_SIGNED2 = 2'd2;

    wire [Q_WIDTH:0]   q_one_ext;
    wire [Q_WIDTH:0]   q_mask_ext;
    wire [Q_WIDTH-1:0] q_mask;
    wire [Q_WIDTH-1:0] a_masked;
    wire [Q_WIDTH-1:0] neg_a;
    wire [Q_WIDTH-1:0] dbl_a;
    wire [Q_WIDTH-1:0] neg_dbl_a;
    reg  [Q_WIDTH-1:0] term_sel;

    assign q_one_ext  = {{Q_WIDTH{1'b0}}, 1'b1};
    assign q_mask_ext = (cfg_q_active >= Q_WIDTH[CFG_WIDTH-1:0]) ? {1'b0, {Q_WIDTH{1'b1}}} :
                        ((q_one_ext << cfg_q_active) - {{Q_WIDTH{1'b0}}, 1'b1});
    assign q_mask     = q_mask_ext[Q_WIDTH-1:0];
    assign a_masked   = a_value & q_mask;
    assign neg_a      = ((~a_masked) + {{(Q_WIDTH-1){1'b0}}, 1'b1}) & q_mask;
    assign dbl_a      = (a_masked << 1) & q_mask;
    assign neg_dbl_a  = ((~dbl_a) + {{(Q_WIDTH-1){1'b0}}, 1'b1}) & q_mask;

    always @(*) begin
        term_sel = {Q_WIDTH{1'b0}};
        case (cfg_coeff_mode)
            MODE_TERNARY: begin
                if (s_value == 2'b01) begin
                    term_sel = a_masked;
                end else if (s_value == 2'b10) begin
                    term_sel = neg_a;
                end
            end
            MODE_BINARY: begin
                if (s_value[0]) begin
                    term_sel = a_masked;
                end
            end
            MODE_SIGNED2: begin
                if (s_value == 2'b01) begin
                    term_sel = a_masked;
                end else if (s_value == 2'b10) begin
                    term_sel = neg_dbl_a;
                end else if (s_value == 2'b11) begin
                    term_sel = neg_a;
                end
            end
            default: begin
                if (s_value == 2'b01) begin
                    term_sel = a_masked;
                end else if (s_value == 2'b10) begin
                    term_sel = neg_a;
                end
            end
        endcase
    end

    assign term_value = lane_active ? term_sel : {Q_WIDTH{1'b0}};

endmodule

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

    wire [Q_WIDTH:0]     q_one_ext;
    wire [Q_WIDTH:0]     q_mask_ext;
    wire [Q_WIDTH-1:0]   q_mask;
    wire [Q_WIDTH-1:0]   term_vec [0:B-1];
    wire [ACC_WIDTH-1:0] sum_stage [0:B];
    wire [Q_WIDTH-1:0]   y_raw;
    genvar lane;

    assign q_one_ext     = {{Q_WIDTH{1'b0}}, 1'b1};
    assign q_mask_ext    = (cfg_q_active >= Q_WIDTH[CFG_WIDTH-1:0]) ? {1'b0, {Q_WIDTH{1'b1}}} :
                           ((q_one_ext << cfg_q_active) - {{Q_WIDTH{1'b0}}, 1'b1});
    assign q_mask        = q_mask_ext[Q_WIDTH-1:0];
    assign sum_stage[0]  = {ACC_WIDTH{1'b0}};

    generate
        for (lane = 0; lane < B; lane = lane + 1) begin : g_terms
            scloudplus_bmm_term #(
                .Q_WIDTH(Q_WIDTH),
                .CFG_WIDTH(CFG_WIDTH)
            ) u_term (
                .cfg_q_active(cfg_q_active),
                .cfg_coeff_mode(cfg_coeff_mode),
                .lane_active(lane[CFG_WIDTH-1:0] < cfg_b_active),
                .a_value(a_vec[lane*Q_WIDTH +: Q_WIDTH]),
                .s_value(s_vec[lane*2 +: 2]),
                .term_value(term_vec[lane])
            );

            assign sum_stage[lane+1] = sum_stage[lane] + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term_vec[lane]};
        end
    endgenerate

    assign y_raw = sum_stage[B][Q_WIDTH-1:0];
    assign y     = y_raw & q_mask;

endmodule
