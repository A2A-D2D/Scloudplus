`timescale 1ns/1ps

module scloud_msgenc_bw8_block
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [11:0]                 msg_block,
    output wire [(8*Q_WIDTH)-1:0]      code_q_flat
);

    localparam DELTA_SHIFT = Q_WIDTH - TAU;
    localparam MOD_MASK    = (1 << TAU) - 1;

    wire signed [5:0] v0_re;
    wire signed [5:0] v0_im;
    wire signed [5:0] v1_re;
    wire signed [5:0] v1_im;
    wire signed [5:0] v2_re;
    wire signed [5:0] v2_im;
    wire signed [5:0] v3_re;
    wire signed [5:0] v3_im;

    wire signed [5:0] s1_0_re;
    wire signed [5:0] s1_0_im;
    wire signed [5:0] s1_1_re;
    wire signed [5:0] s1_1_im;
    wire signed [5:0] s1_2_re;
    wire signed [5:0] s1_2_im;
    wire signed [5:0] s1_3_re;
    wire signed [5:0] s1_3_im;

    wire signed [5:0] w0_re;
    wire signed [5:0] w0_im;
    wire signed [5:0] w1_re;
    wire signed [5:0] w1_im;
    wire signed [5:0] w2_re;
    wire signed [5:0] w2_im;
    wire signed [5:0] w3_re;
    wire signed [5:0] w3_im;

    wire [TAU-1:0] w0_re_mod;
    wire [TAU-1:0] w0_im_mod;
    wire [TAU-1:0] w1_re_mod;
    wire [TAU-1:0] w1_im_mod;
    wire [TAU-1:0] w2_re_mod;
    wire [TAU-1:0] w2_im_mod;
    wire [TAU-1:0] w3_re_mod;
    wire [TAU-1:0] w3_im_mod;

    assign v0_re = {4'b0000, msg_block[11:10]};
    assign v0_im = {4'b0000, msg_block[9:8]};
    assign v1_re = {4'b0000, msg_block[7:6]};
    assign v1_im = {5'b00000, msg_block[5]};
    assign v2_re = {4'b0000, msg_block[4:3]};
    assign v2_im = {5'b00000, msg_block[2]};
    assign v3_re = {5'b00000, msg_block[1]};
    assign v3_im = {5'b00000, msg_block[0]};

    assign s1_0_re = v0_re;
    assign s1_0_im = v0_im;
    assign s1_1_re = v0_re + v1_re - v1_im;
    assign s1_1_im = v0_im + v1_re + v1_im;
    assign s1_2_re = v2_re;
    assign s1_2_im = v2_im;
    assign s1_3_re = v2_re + v3_re - v3_im;
    assign s1_3_im = v2_im + v3_re + v3_im;

    assign w0_re = s1_0_re;
    assign w0_im = s1_0_im;
    assign w1_re = s1_1_re;
    assign w1_im = s1_1_im;
    assign w2_re = s1_0_re + s1_2_re - s1_2_im;
    assign w2_im = s1_0_im + s1_2_re + s1_2_im;
    assign w3_re = s1_1_re + s1_3_re - s1_3_im;
    assign w3_im = s1_1_im + s1_3_re + s1_3_im;

    assign w0_re_mod = w0_re[TAU-1:0] & MOD_MASK[TAU-1:0];
    assign w0_im_mod = w0_im[TAU-1:0] & MOD_MASK[TAU-1:0];
    assign w1_re_mod = w1_re[TAU-1:0] & MOD_MASK[TAU-1:0];
    assign w1_im_mod = w1_im[TAU-1:0] & MOD_MASK[TAU-1:0];
    assign w2_re_mod = w2_re[TAU-1:0] & MOD_MASK[TAU-1:0];
    assign w2_im_mod = w2_im[TAU-1:0] & MOD_MASK[TAU-1:0];
    assign w3_re_mod = w3_re[TAU-1:0] & MOD_MASK[TAU-1:0];
    assign w3_im_mod = w3_im[TAU-1:0] & MOD_MASK[TAU-1:0];

    assign code_q_flat[(0*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w0_re_mod} << DELTA_SHIFT;
    assign code_q_flat[(1*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w0_im_mod} << DELTA_SHIFT;
    assign code_q_flat[(2*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w1_re_mod} << DELTA_SHIFT;
    assign code_q_flat[(3*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w1_im_mod} << DELTA_SHIFT;
    assign code_q_flat[(4*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w2_re_mod} << DELTA_SHIFT;
    assign code_q_flat[(5*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w2_im_mod} << DELTA_SHIFT;
    assign code_q_flat[(6*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w3_re_mod} << DELTA_SHIFT;
    assign code_q_flat[(7*Q_WIDTH)+:Q_WIDTH] = {{(Q_WIDTH-TAU){1'b0}}, w3_im_mod} << DELTA_SHIFT;

endmodule
