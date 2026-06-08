`timescale 1ns/1ps

module scloud_bw16_reduce_tau2
#(
    parameter WH = 0
)
(
    input  wire [5:0] raw_re,
    input  wire [5:0] raw_im,
    output wire [1:0] re_bits,
    output wire [1:0] im_bits
);

    wire [5:0] b_prime;
    wire [5:0] a_adj;

    assign b_prime = (WH == 0) ? {4'b0000, raw_im[1:0]} :
                     (WH == 1) ? {5'b00000, raw_im[0]} :
                     (WH == 2) ? {5'b00000, raw_im[0]} :
                                 6'b000000;

    assign a_adj = raw_re - raw_im + b_prime;

    assign re_bits = (WH == 0) ? a_adj[1:0] :
                     (WH == 1) ? a_adj[1:0] :
                     (WH == 2) ? {1'b0, a_adj[0]} :
                                 {1'b0, a_adj[0]};

    assign im_bits = (WH == 0) ? raw_im[1:0] :
                     (WH == 1) ? {1'b0, raw_im[0]} :
                     (WH == 2) ? {1'b0, raw_im[0]} :
                                 2'b00;

endmodule
