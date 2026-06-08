`timescale 1ns/1ps

module scloud_msgenc_bw16_block
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [19:0]                 msg_block,
    output wire [(16*Q_WIDTH)-1:0]     code_q_flat
);

    localparam DELTA_SHIFT = Q_WIDTH - TAU;

    wire [5:0] v0_re; wire [5:0] v0_im;
    wire [5:0] v1_re; wire [5:0] v1_im;
    wire [5:0] v2_re; wire [5:0] v2_im;
    wire [5:0] v3_re; wire [5:0] v3_im;
    wire [5:0] v4_re; wire [5:0] v4_im;
    wire [5:0] v5_re; wire [5:0] v5_im;
    wire [5:0] v6_re; wire [5:0] v6_im;
    wire [5:0] v7_re; wire [5:0] v7_im;

    wire [5:0] s1_0_re; wire [5:0] s1_0_im;
    wire [5:0] s1_1_re; wire [5:0] s1_1_im;
    wire [5:0] s1_2_re; wire [5:0] s1_2_im;
    wire [5:0] s1_3_re; wire [5:0] s1_3_im;
    wire [5:0] s1_4_re; wire [5:0] s1_4_im;
    wire [5:0] s1_5_re; wire [5:0] s1_5_im;
    wire [5:0] s1_6_re; wire [5:0] s1_6_im;
    wire [5:0] s1_7_re; wire [5:0] s1_7_im;

    wire [5:0] s2_0_re; wire [5:0] s2_0_im;
    wire [5:0] s2_1_re; wire [5:0] s2_1_im;
    wire [5:0] s2_2_re; wire [5:0] s2_2_im;
    wire [5:0] s2_3_re; wire [5:0] s2_3_im;
    wire [5:0] s2_4_re; wire [5:0] s2_4_im;
    wire [5:0] s2_5_re; wire [5:0] s2_5_im;
    wire [5:0] s2_6_re; wire [5:0] s2_6_im;
    wire [5:0] s2_7_re; wire [5:0] s2_7_im;

    wire [5:0] w0_re; wire [5:0] w0_im;
    wire [5:0] w1_re; wire [5:0] w1_im;
    wire [5:0] w2_re; wire [5:0] w2_im;
    wire [5:0] w3_re; wire [5:0] w3_im;
    wire [5:0] w4_re; wire [5:0] w4_im;
    wire [5:0] w5_re; wire [5:0] w5_im;
    wire [5:0] w6_re; wire [5:0] w6_im;
    wire [5:0] w7_re; wire [5:0] w7_im;

    assign v0_re = {4'b0000, msg_block[19:18]};
    assign v0_im = {4'b0000, msg_block[17:16]};
    assign v1_re = {4'b0000, msg_block[15:14]};
    assign v1_im = {5'b00000, msg_block[13]};
    assign v2_re = {4'b0000, msg_block[12:11]};
    assign v2_im = {5'b00000, msg_block[10]};
    assign v3_re = {5'b00000, msg_block[9]};
    assign v3_im = {5'b00000, msg_block[8]};
    assign v4_re = {4'b0000, msg_block[7:6]};
    assign v4_im = {5'b00000, msg_block[5]};
    assign v5_re = {5'b00000, msg_block[4]};
    assign v5_im = {5'b00000, msg_block[3]};
    assign v6_re = {5'b00000, msg_block[2]};
    assign v6_im = {5'b00000, msg_block[1]};
    assign v7_re = {5'b00000, msg_block[0]};
    assign v7_im = 6'b000000;

    assign s1_0_re = v0_re; assign s1_0_im = v0_im;
    assign s1_2_re = v2_re; assign s1_2_im = v2_im;
    assign s1_4_re = v4_re; assign s1_4_im = v4_im;
    assign s1_6_re = v6_re; assign s1_6_im = v6_im;

    scloud_bw16_phi_add_pair u_s1_01 (.a_re(v0_re), .a_im(v0_im), .b_re(v1_re), .b_im(v1_im), .y_re(s1_1_re), .y_im(s1_1_im));
    scloud_bw16_phi_add_pair u_s1_23 (.a_re(v2_re), .a_im(v2_im), .b_re(v3_re), .b_im(v3_im), .y_re(s1_3_re), .y_im(s1_3_im));
    scloud_bw16_phi_add_pair u_s1_45 (.a_re(v4_re), .a_im(v4_im), .b_re(v5_re), .b_im(v5_im), .y_re(s1_5_re), .y_im(s1_5_im));
    scloud_bw16_phi_add_pair u_s1_67 (.a_re(v6_re), .a_im(v6_im), .b_re(v7_re), .b_im(v7_im), .y_re(s1_7_re), .y_im(s1_7_im));

    assign s2_0_re = s1_0_re; assign s2_0_im = s1_0_im;
    assign s2_1_re = s1_1_re; assign s2_1_im = s1_1_im;
    assign s2_4_re = s1_4_re; assign s2_4_im = s1_4_im;
    assign s2_5_re = s1_5_re; assign s2_5_im = s1_5_im;

    scloud_bw16_phi_add_pair u_s2_02 (.a_re(s1_0_re), .a_im(s1_0_im), .b_re(s1_2_re), .b_im(s1_2_im), .y_re(s2_2_re), .y_im(s2_2_im));
    scloud_bw16_phi_add_pair u_s2_13 (.a_re(s1_1_re), .a_im(s1_1_im), .b_re(s1_3_re), .b_im(s1_3_im), .y_re(s2_3_re), .y_im(s2_3_im));
    scloud_bw16_phi_add_pair u_s2_46 (.a_re(s1_4_re), .a_im(s1_4_im), .b_re(s1_6_re), .b_im(s1_6_im), .y_re(s2_6_re), .y_im(s2_6_im));
    scloud_bw16_phi_add_pair u_s2_57 (.a_re(s1_5_re), .a_im(s1_5_im), .b_re(s1_7_re), .b_im(s1_7_im), .y_re(s2_7_re), .y_im(s2_7_im));

    assign w0_re = s2_0_re; assign w0_im = s2_0_im;
    assign w1_re = s2_1_re; assign w1_im = s2_1_im;
    assign w2_re = s2_2_re; assign w2_im = s2_2_im;
    assign w3_re = s2_3_re; assign w3_im = s2_3_im;

    scloud_bw16_phi_add_pair u_s3_04 (.a_re(s2_0_re), .a_im(s2_0_im), .b_re(s2_4_re), .b_im(s2_4_im), .y_re(w4_re), .y_im(w4_im));
    scloud_bw16_phi_add_pair u_s3_15 (.a_re(s2_1_re), .a_im(s2_1_im), .b_re(s2_5_re), .b_im(s2_5_im), .y_re(w5_re), .y_im(w5_im));
    scloud_bw16_phi_add_pair u_s3_26 (.a_re(s2_2_re), .a_im(s2_2_im), .b_re(s2_6_re), .b_im(s2_6_im), .y_re(w6_re), .y_im(w6_im));
    scloud_bw16_phi_add_pair u_s3_37 (.a_re(s2_3_re), .a_im(s2_3_im), .b_re(s2_7_re), .b_im(s2_7_im), .y_re(w7_re), .y_im(w7_im));

    assign code_q_flat[(0*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w0_re[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(1*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w0_im[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(2*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w1_re[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(3*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w1_im[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(4*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w2_re[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(5*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w2_im[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(6*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w3_re[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(7*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w3_im[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(8*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w4_re[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(9*Q_WIDTH)+:Q_WIDTH]  = {{(Q_WIDTH-TAU){1'b0}}, w4_im[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(10*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w5_re[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(11*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w5_im[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(12*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w6_re[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(13*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w6_im[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(14*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w7_re[TAU-1:0]} << DELTA_SHIFT;
    assign code_q_flat[(15*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w7_im[TAU-1:0]} << DELTA_SHIFT;

endmodule
