`timescale 1ns/1ps

module scloud_msgfunc_bw32_demo
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [31:0]                 msg_in,
    input  wire [(32*Q_WIDTH)-1:0]     noise_q_flat,
    output wire [(32*Q_WIDTH)-1:0]     enc_q_flat,
    output wire [(32*Q_WIDTH)-1:0]     noisy_q_flat,
    output wire [(32*Q_WIDTH)-1:0]     rounded_q_flat,
    output wire [31:0]                 msg_out
);

    genvar gi;

    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : gen_add_noise
            assign noisy_q_flat[(gi*Q_WIDTH)+:Q_WIDTH] =
                enc_q_flat[(gi*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    scloud_msgenc_bw32_block #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_msgenc (
        .msg_block  (msg_in),
        .code_q_flat(enc_q_flat)
    );

    scloud_msgdec_bw32_block #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_msgdec (
        .noisy_q_flat  (noisy_q_flat),
        .msg_block     (msg_out),
        .rounded_q_flat(rounded_q_flat)
    );

endmodule
