`timescale 1ns/1ps

module scloud_msgfunc_bw8_demo
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [11:0]                 msg_in,
    input  wire [(8*Q_WIDTH)-1:0]      noise_q_flat,
    output wire [(8*Q_WIDTH)-1:0]      enc_q_flat,
    output wire [(8*Q_WIDTH)-1:0]      noisy_q_flat,
    output wire [(8*Q_WIDTH)-1:0]      rounded_q_flat,
    output wire [11:0]                 msg_out
);

    assign noisy_q_flat[(0*Q_WIDTH)+:Q_WIDTH] = enc_q_flat[(0*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(0*Q_WIDTH)+:Q_WIDTH];
    assign noisy_q_flat[(1*Q_WIDTH)+:Q_WIDTH] = enc_q_flat[(1*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(1*Q_WIDTH)+:Q_WIDTH];
    assign noisy_q_flat[(2*Q_WIDTH)+:Q_WIDTH] = enc_q_flat[(2*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(2*Q_WIDTH)+:Q_WIDTH];
    assign noisy_q_flat[(3*Q_WIDTH)+:Q_WIDTH] = enc_q_flat[(3*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(3*Q_WIDTH)+:Q_WIDTH];
    assign noisy_q_flat[(4*Q_WIDTH)+:Q_WIDTH] = enc_q_flat[(4*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(4*Q_WIDTH)+:Q_WIDTH];
    assign noisy_q_flat[(5*Q_WIDTH)+:Q_WIDTH] = enc_q_flat[(5*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(5*Q_WIDTH)+:Q_WIDTH];
    assign noisy_q_flat[(6*Q_WIDTH)+:Q_WIDTH] = enc_q_flat[(6*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(6*Q_WIDTH)+:Q_WIDTH];
    assign noisy_q_flat[(7*Q_WIDTH)+:Q_WIDTH] = enc_q_flat[(7*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(7*Q_WIDTH)+:Q_WIDTH];

    scloud_msgenc_bw8_block #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_msgenc (
        .msg_block  (msg_in),
        .code_q_flat(enc_q_flat)
    );

    scloud_msgdec_bw8_block #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_msgdec (
        .noisy_q_flat  (noisy_q_flat),
        .msg_block     (msg_out),
        .rounded_q_flat(rounded_q_flat)
    );

endmodule
