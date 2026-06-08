`timescale 1ns/1ps

module scloud_msgdec_bw16_block
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [(16*Q_WIDTH)-1:0] noisy_q_flat,
    output wire [19:0]             msg_block,
    output wire [(16*Q_WIDTH)-1:0] rounded_q_flat
);

    wire [TAU-1:0] y0_re; wire [TAU-1:0] y0_im;
    wire [TAU-1:0] y1_re; wire [TAU-1:0] y1_im;
    wire [TAU-1:0] y2_re; wire [TAU-1:0] y2_im;
    wire [TAU-1:0] y3_re; wire [TAU-1:0] y3_im;
    wire [TAU-1:0] y4_re; wire [TAU-1:0] y4_im;
    wire [TAU-1:0] y5_re; wire [TAU-1:0] y5_im;
    wire [TAU-1:0] y6_re; wire [TAU-1:0] y6_im;
    wire [TAU-1:0] y7_re; wire [TAU-1:0] y7_im;

    wire [5:0] s0_re; wire [5:0] s0_im;
    wire [5:0] s1_re; wire [5:0] s1_im;
    wire [5:0] s2_re; wire [5:0] s2_im;
    wire [5:0] s3_re; wire [5:0] s3_im;
    wire [5:0] s4_re; wire [5:0] s4_im;
    wire [5:0] s5_re; wire [5:0] s5_im;
    wire [5:0] s6_re; wire [5:0] s6_im;
    wire [5:0] s7_re; wire [5:0] s7_im;

    wire [5:0] t0_re; wire [5:0] t0_im;
    wire [5:0] t1_re; wire [5:0] t1_im;
    wire [5:0] t2_re; wire [5:0] t2_im;
    wire [5:0] t3_re; wire [5:0] t3_im;
    wire [5:0] t4_re; wire [5:0] t4_im;
    wire [5:0] t5_re; wire [5:0] t5_im;
    wire [5:0] t6_re; wire [5:0] t6_im;
    wire [5:0] t7_re; wire [5:0] t7_im;

    wire [5:0] u0_re; wire [5:0] u0_im;
    wire [5:0] u1_re; wire [5:0] u1_im;
    wire [5:0] u2_re; wire [5:0] u2_im;
    wire [5:0] u3_re; wire [5:0] u3_im;
    wire [5:0] u4_re; wire [5:0] u4_im;
    wire [5:0] u5_re; wire [5:0] u5_im;
    wire [5:0] u6_re; wire [5:0] u6_im;
    wire [5:0] u7_re; wire [5:0] u7_im;

    wire [5:0] raw0_re; wire [5:0] raw0_im;
    wire [5:0] raw1_re; wire [5:0] raw1_im;
    wire [5:0] raw2_re; wire [5:0] raw2_im;
    wire [5:0] raw3_re; wire [5:0] raw3_im;
    wire [5:0] raw4_re; wire [5:0] raw4_im;
    wire [5:0] raw5_re; wire [5:0] raw5_im;
    wire [5:0] raw6_re; wire [5:0] raw6_im;
    wire [5:0] raw7_re; wire [5:0] raw7_im;

    wire [1:0] r0_bits; wire [1:0] i0_bits;
    wire [1:0] r1_bits; wire [1:0] i1_bits;
    wire [1:0] r2_bits; wire [1:0] i2_bits;
    wire [1:0] r3_bits; wire [1:0] i3_bits;
    wire [1:0] r4_bits; wire [1:0] i4_bits;
    wire [1:0] r5_bits; wire [1:0] i5_bits;
    wire [1:0] r6_bits; wire [1:0] i6_bits;
    wire [1:0] r7_bits; wire [1:0] i7_bits;

    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_0_re (.x_q(noisy_q_flat[(0*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(0*Q_WIDTH)+:Q_WIDTH]),  .small_val(y0_re));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_0_im (.x_q(noisy_q_flat[(1*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(1*Q_WIDTH)+:Q_WIDTH]),  .small_val(y0_im));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_1_re (.x_q(noisy_q_flat[(2*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(2*Q_WIDTH)+:Q_WIDTH]),  .small_val(y1_re));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_1_im (.x_q(noisy_q_flat[(3*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(3*Q_WIDTH)+:Q_WIDTH]),  .small_val(y1_im));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_2_re (.x_q(noisy_q_flat[(4*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(4*Q_WIDTH)+:Q_WIDTH]),  .small_val(y2_re));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_2_im (.x_q(noisy_q_flat[(5*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(5*Q_WIDTH)+:Q_WIDTH]),  .small_val(y2_im));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_3_re (.x_q(noisy_q_flat[(6*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(6*Q_WIDTH)+:Q_WIDTH]),  .small_val(y3_re));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_3_im (.x_q(noisy_q_flat[(7*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(7*Q_WIDTH)+:Q_WIDTH]),  .small_val(y3_im));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_4_re (.x_q(noisy_q_flat[(8*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(8*Q_WIDTH)+:Q_WIDTH]),  .small_val(y4_re));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_4_im (.x_q(noisy_q_flat[(9*Q_WIDTH)+:Q_WIDTH]),  .rounded_q(rounded_q_flat[(9*Q_WIDTH)+:Q_WIDTH]),  .small_val(y4_im));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_5_re (.x_q(noisy_q_flat[(10*Q_WIDTH)+:Q_WIDTH]), .rounded_q(rounded_q_flat[(10*Q_WIDTH)+:Q_WIDTH]), .small_val(y5_re));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_5_im (.x_q(noisy_q_flat[(11*Q_WIDTH)+:Q_WIDTH]), .rounded_q(rounded_q_flat[(11*Q_WIDTH)+:Q_WIDTH]), .small_val(y5_im));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_6_re (.x_q(noisy_q_flat[(12*Q_WIDTH)+:Q_WIDTH]), .rounded_q(rounded_q_flat[(12*Q_WIDTH)+:Q_WIDTH]), .small_val(y6_re));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_6_im (.x_q(noisy_q_flat[(13*Q_WIDTH)+:Q_WIDTH]), .rounded_q(rounded_q_flat[(13*Q_WIDTH)+:Q_WIDTH]), .small_val(y6_im));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_7_re (.x_q(noisy_q_flat[(14*Q_WIDTH)+:Q_WIDTH]), .rounded_q(rounded_q_flat[(14*Q_WIDTH)+:Q_WIDTH]), .small_val(y7_re));
    scloud_bw16_round_coord #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_7_im (.x_q(noisy_q_flat[(15*Q_WIDTH)+:Q_WIDTH]), .rounded_q(rounded_q_flat[(15*Q_WIDTH)+:Q_WIDTH]), .small_val(y7_im));

    assign s0_re = {4'b0000, y0_re}; assign s0_im = {4'b0000, y0_im};
    assign s1_re = {4'b0000, y1_re}; assign s1_im = {4'b0000, y1_im};
    assign s2_re = {4'b0000, y2_re}; assign s2_im = {4'b0000, y2_im};
    assign s3_re = {4'b0000, y3_re}; assign s3_im = {4'b0000, y3_im};
    assign s4_re = {4'b0000, y4_re}; assign s4_im = {4'b0000, y4_im};
    assign s5_re = {4'b0000, y5_re}; assign s5_im = {4'b0000, y5_im};
    assign s6_re = {4'b0000, y6_re}; assign s6_im = {4'b0000, y6_im};
    assign s7_re = {4'b0000, y7_re}; assign s7_im = {4'b0000, y7_im};

    assign t0_re = s0_re; assign t0_im = s0_im;
    assign t1_re = s1_re; assign t1_im = s1_im;
    assign t2_re = s2_re; assign t2_im = s2_im;
    assign t3_re = s3_re; assign t3_im = s3_im;
    scloud_bw16_inv_phi_pair u_inv_s3_04 (.a_re(s0_re), .a_im(s0_im), .y_re(s4_re), .y_im(s4_im), .b_re(t4_re), .b_im(t4_im));
    scloud_bw16_inv_phi_pair u_inv_s3_15 (.a_re(s1_re), .a_im(s1_im), .y_re(s5_re), .y_im(s5_im), .b_re(t5_re), .b_im(t5_im));
    scloud_bw16_inv_phi_pair u_inv_s3_26 (.a_re(s2_re), .a_im(s2_im), .y_re(s6_re), .y_im(s6_im), .b_re(t6_re), .b_im(t6_im));
    scloud_bw16_inv_phi_pair u_inv_s3_37 (.a_re(s3_re), .a_im(s3_im), .y_re(s7_re), .y_im(s7_im), .b_re(t7_re), .b_im(t7_im));

    assign u0_re = t0_re; assign u0_im = t0_im;
    assign u1_re = t1_re; assign u1_im = t1_im;
    assign u4_re = t4_re; assign u4_im = t4_im;
    assign u5_re = t5_re; assign u5_im = t5_im;
    scloud_bw16_inv_phi_pair u_inv_s2_02 (.a_re(t0_re), .a_im(t0_im), .y_re(t2_re), .y_im(t2_im), .b_re(u2_re), .b_im(u2_im));
    scloud_bw16_inv_phi_pair u_inv_s2_13 (.a_re(t1_re), .a_im(t1_im), .y_re(t3_re), .y_im(t3_im), .b_re(u3_re), .b_im(u3_im));
    scloud_bw16_inv_phi_pair u_inv_s2_46 (.a_re(t4_re), .a_im(t4_im), .y_re(t6_re), .y_im(t6_im), .b_re(u6_re), .b_im(u6_im));
    scloud_bw16_inv_phi_pair u_inv_s2_57 (.a_re(t5_re), .a_im(t5_im), .y_re(t7_re), .y_im(t7_im), .b_re(u7_re), .b_im(u7_im));

    assign raw0_re = u0_re; assign raw0_im = u0_im;
    assign raw2_re = u2_re; assign raw2_im = u2_im;
    assign raw4_re = u4_re; assign raw4_im = u4_im;
    assign raw6_re = u6_re; assign raw6_im = u6_im;
    scloud_bw16_inv_phi_pair u_inv_s1_01 (.a_re(u0_re), .a_im(u0_im), .y_re(u1_re), .y_im(u1_im), .b_re(raw1_re), .b_im(raw1_im));
    scloud_bw16_inv_phi_pair u_inv_s1_23 (.a_re(u2_re), .a_im(u2_im), .y_re(u3_re), .y_im(u3_im), .b_re(raw3_re), .b_im(raw3_im));
    scloud_bw16_inv_phi_pair u_inv_s1_45 (.a_re(u4_re), .a_im(u4_im), .y_re(u5_re), .y_im(u5_im), .b_re(raw5_re), .b_im(raw5_im));
    scloud_bw16_inv_phi_pair u_inv_s1_67 (.a_re(u6_re), .a_im(u6_im), .y_re(u7_re), .y_im(u7_im), .b_re(raw7_re), .b_im(raw7_im));

    scloud_bw16_reduce_tau2 #(.WH(0)) u_reduce_0 (.raw_re(raw0_re), .raw_im(raw0_im), .re_bits(r0_bits), .im_bits(i0_bits));
    scloud_bw16_reduce_tau2 #(.WH(1)) u_reduce_1 (.raw_re(raw1_re), .raw_im(raw1_im), .re_bits(r1_bits), .im_bits(i1_bits));
    scloud_bw16_reduce_tau2 #(.WH(1)) u_reduce_2 (.raw_re(raw2_re), .raw_im(raw2_im), .re_bits(r2_bits), .im_bits(i2_bits));
    scloud_bw16_reduce_tau2 #(.WH(2)) u_reduce_3 (.raw_re(raw3_re), .raw_im(raw3_im), .re_bits(r3_bits), .im_bits(i3_bits));
    scloud_bw16_reduce_tau2 #(.WH(1)) u_reduce_4 (.raw_re(raw4_re), .raw_im(raw4_im), .re_bits(r4_bits), .im_bits(i4_bits));
    scloud_bw16_reduce_tau2 #(.WH(2)) u_reduce_5 (.raw_re(raw5_re), .raw_im(raw5_im), .re_bits(r5_bits), .im_bits(i5_bits));
    scloud_bw16_reduce_tau2 #(.WH(2)) u_reduce_6 (.raw_re(raw6_re), .raw_im(raw6_im), .re_bits(r6_bits), .im_bits(i6_bits));
    scloud_bw16_reduce_tau2 #(.WH(3)) u_reduce_7 (.raw_re(raw7_re), .raw_im(raw7_im), .re_bits(r7_bits), .im_bits(i7_bits));

    assign msg_block = {
        r0_bits[1:0], i0_bits[1:0],
        r1_bits[1:0], i1_bits[0],
        r2_bits[1:0], i2_bits[0],
        r3_bits[0],   i3_bits[0],
        r4_bits[1:0], i4_bits[0],
        r5_bits[0],   i5_bits[0],
        r6_bits[0],   i6_bits[0],
        r7_bits[0]
    };

endmodule
