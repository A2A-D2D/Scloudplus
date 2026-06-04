`timescale 1ns/1ps
// Module: scloudplus_bmm_pe
// Purpose: fixed 8-lane Scloud+ PE using explicit lane instances.

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

    assign q_one_ext = {{Q_WIDTH{1'b0}}, 1'b1};
    assign q_mask_ext = (cfg_q_active >= Q_WIDTH[CFG_WIDTH-1:0]) ? {1'b0, {Q_WIDTH{1'b1}}} :
                        ((q_one_ext << cfg_q_active) - {{Q_WIDTH{1'b0}}, 1'b1});
    assign q_mask = q_mask_ext[Q_WIDTH-1:0];
    assign a_masked = a_value & q_mask;
    assign neg_a = ((~a_masked) + {{(Q_WIDTH-1){1'b0}}, 1'b1}) & q_mask;
    assign dbl_a = (a_masked << 1) & q_mask;
    assign neg_dbl_a = ((~dbl_a) + {{(Q_WIDTH-1){1'b0}}, 1'b1}) & q_mask;

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

    wire [Q_WIDTH:0]   q_one_ext;
    wire [Q_WIDTH:0]   q_mask_ext;
    wire [Q_WIDTH-1:0] q_mask;
    wire [Q_WIDTH-1:0] term0;
    wire [Q_WIDTH-1:0] term1;
    wire [Q_WIDTH-1:0] term2;
    wire [Q_WIDTH-1:0] term3;
    wire [Q_WIDTH-1:0] term4;
    wire [Q_WIDTH-1:0] term5;
    wire [Q_WIDTH-1:0] term6;
    wire [Q_WIDTH-1:0] term7;
    wire [ACC_WIDTH-1:0] sum0;
    wire [ACC_WIDTH-1:0] sum1;
    wire [ACC_WIDTH-1:0] sum2;
    wire [ACC_WIDTH-1:0] sum3;
    wire [ACC_WIDTH-1:0] sum4;
    wire [ACC_WIDTH-1:0] sum5;
    wire [ACC_WIDTH-1:0] sum6;
    wire [ACC_WIDTH-1:0] sum7;
    wire [ACC_WIDTH-1:0] sum8;
    wire [Q_WIDTH-1:0] y_raw;

    assign q_one_ext = {{Q_WIDTH{1'b0}}, 1'b1};
    assign q_mask_ext = (cfg_q_active >= Q_WIDTH[CFG_WIDTH-1:0]) ? {1'b0, {Q_WIDTH{1'b1}}} :
                        ((q_one_ext << cfg_q_active) - {{Q_WIDTH{1'b0}}, 1'b1});
    assign q_mask = q_mask_ext[Q_WIDTH-1:0];

    scloudplus_bmm_term #(.Q_WIDTH(Q_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_term0 (
        .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), .lane_active(cfg_b_active > 0),
        .a_value(a_vec[0*Q_WIDTH +: Q_WIDTH]), .s_value(s_vec[0*2 +: 2]), .term_value(term0));
    scloudplus_bmm_term #(.Q_WIDTH(Q_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_term1 (
        .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), .lane_active(cfg_b_active > 1),
        .a_value(a_vec[1*Q_WIDTH +: Q_WIDTH]), .s_value(s_vec[1*2 +: 2]), .term_value(term1));
    scloudplus_bmm_term #(.Q_WIDTH(Q_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_term2 (
        .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), .lane_active(cfg_b_active > 2),
        .a_value(a_vec[2*Q_WIDTH +: Q_WIDTH]), .s_value(s_vec[2*2 +: 2]), .term_value(term2));
    scloudplus_bmm_term #(.Q_WIDTH(Q_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_term3 (
        .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), .lane_active(cfg_b_active > 3),
        .a_value(a_vec[3*Q_WIDTH +: Q_WIDTH]), .s_value(s_vec[3*2 +: 2]), .term_value(term3));
    scloudplus_bmm_term #(.Q_WIDTH(Q_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_term4 (
        .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), .lane_active(cfg_b_active > 4),
        .a_value(a_vec[4*Q_WIDTH +: Q_WIDTH]), .s_value(s_vec[4*2 +: 2]), .term_value(term4));
    scloudplus_bmm_term #(.Q_WIDTH(Q_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_term5 (
        .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), .lane_active(cfg_b_active > 5),
        .a_value(a_vec[5*Q_WIDTH +: Q_WIDTH]), .s_value(s_vec[5*2 +: 2]), .term_value(term5));
    scloudplus_bmm_term #(.Q_WIDTH(Q_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_term6 (
        .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), .lane_active(cfg_b_active > 6),
        .a_value(a_vec[6*Q_WIDTH +: Q_WIDTH]), .s_value(s_vec[6*2 +: 2]), .term_value(term6));
    scloudplus_bmm_term #(.Q_WIDTH(Q_WIDTH), .CFG_WIDTH(CFG_WIDTH)) u_term7 (
        .cfg_q_active(cfg_q_active), .cfg_coeff_mode(cfg_coeff_mode), .lane_active(cfg_b_active > 7),
        .a_value(a_vec[7*Q_WIDTH +: Q_WIDTH]), .s_value(s_vec[7*2 +: 2]), .term_value(term7));

    assign sum0 = {ACC_WIDTH{1'b0}};
    assign sum1 = sum0 + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term0};
    assign sum2 = sum1 + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term1};
    assign sum3 = sum2 + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term2};
    assign sum4 = sum3 + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term3};
    assign sum5 = sum4 + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term4};
    assign sum6 = sum5 + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term5};
    assign sum7 = sum6 + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term6};
    assign sum8 = sum7 + {{(ACC_WIDTH-Q_WIDTH){1'b0}}, term7};
    assign y_raw = sum8[Q_WIDTH-1:0];
    assign y = y_raw & q_mask;

endmodule
