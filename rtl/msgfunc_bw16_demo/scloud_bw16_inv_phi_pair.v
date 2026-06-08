`timescale 1ns/1ps

module scloud_bw16_inv_phi_pair
(
    input  wire [5:0] a_re,
    input  wire [5:0] a_im,
    input  wire [5:0] y_re,
    input  wire [5:0] y_im,
    output wire [5:0] b_re,
    output wire [5:0] b_im
);

    wire [6:0] dr;
    wire [6:0] di;
    wire [6:0] b_re_sum;
    wire [6:0] b_im_sum;

    assign dr = {y_re[5], y_re} - {a_re[5], a_re};
    assign di = {y_im[5], y_im} - {a_im[5], a_im};
    assign b_re_sum = dr + di;
    assign b_im_sum = di - dr;
    assign b_re = {b_re_sum[6], b_re_sum[6:1]};
    assign b_im = {b_im_sum[6], b_im_sum[6:1]};

endmodule
