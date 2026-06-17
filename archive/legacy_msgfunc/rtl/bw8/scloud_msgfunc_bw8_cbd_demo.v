`timescale 1ns/1ps

module scloud_msgfunc_bw8_cbd_demo
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2,
    parameter ETA     = 7
)
(
    input  wire [11:0]                 msg_in,
    input  wire [(8*2*ETA)-1:0]        cbd_rnd_bits,
    output wire [(8*Q_WIDTH)-1:0]      noise_q_flat,
    output wire [(8*Q_WIDTH)-1:0]      enc_q_flat,
    output wire [(8*Q_WIDTH)-1:0]      noisy_q_flat,
    output wire [(8*Q_WIDTH)-1:0]      rounded_q_flat,
    output wire [11:0]                 msg_out
);

    scloud_cbd_noise8 #(
        .Q_WIDTH(Q_WIDTH),
        .ETA    (ETA)
    ) u_cbd_noise (
        .rnd_bits    (cbd_rnd_bits),
        .noise_q_flat(noise_q_flat)
    );

    scloud_msgfunc_bw8_demo #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_msgfunc (
        .msg_in        (msg_in),
        .noise_q_flat  (noise_q_flat),
        .enc_q_flat    (enc_q_flat),
        .noisy_q_flat  (noisy_q_flat),
        .rounded_q_flat(rounded_q_flat),
        .msg_out       (msg_out)
    );

endmodule
