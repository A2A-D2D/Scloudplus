`timescale 1ns/1ps

module scloud_bw16_phi_add_pair
(
    input  wire [5:0] a_re,
    input  wire [5:0] a_im,
    input  wire [5:0] b_re,
    input  wire [5:0] b_im,
    output wire [5:0] y_re,
    output wire [5:0] y_im
);

    assign y_re = a_re + b_re - b_im;
    assign y_im = a_im + b_re + b_im;

endmodule
