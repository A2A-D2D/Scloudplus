`timescale 1ns/1ps

module scloud_msgfunc_bw32_demo
(
    input  wire [31:0]  msg_in,
    input  wire [319:0] noise_q_flat,
    output wire [319:0] enc_q_flat,
    output wire [319:0] noisy_q_flat,
    output wire [319:0] rounded_q_flat,
    output wire [31:0]  msg_out
);

    genvar gi;

    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : gen_add_noise
            /* q=1024 is a power-of-two ring in this demo, so 10-bit
               truncation is the intended modulo-q reduction. */
            assign noisy_q_flat[(gi*10)+:10] =
                enc_q_flat[(gi*10)+:10] + noise_q_flat[(gi*10)+:10];
        end
    endgenerate

    scloud_msgenc_bw32_block u_msgenc (
        .msg_block  (msg_in),
        .code_q_flat(enc_q_flat)
    );

    scloud_msgdec_bw32_block u_msgdec (
        .noisy_q_flat  (noisy_q_flat),
        .msg_block     (msg_out),
        .rounded_q_flat(rounded_q_flat)
    );

endmodule
