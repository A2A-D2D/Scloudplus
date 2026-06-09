`timescale 1ns/1ps

module scloud_msgfunc_bw32_demo_reg
(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,
    input  wire [31:0]  msg_in,
    input  wire [319:0] noise_q_flat,
    output reg          valid_out,
    output reg  [319:0] enc_q_flat,
    output reg  [319:0] noisy_q_flat,
    output reg  [319:0] rounded_q_flat,
    output reg  [31:0]  msg_out
);

    reg [31:0]  msg_in_r;
    reg [319:0] noise_q_flat_r;
    reg         valid_r;

    wire [319:0] enc_q_flat_w;
    wire [319:0] noisy_q_flat_w;
    wire [319:0] rounded_q_flat_w;
    wire [31:0]  msg_out_w;

    scloud_msgfunc_bw32_demo u_comb (
        .msg_in        (msg_in_r),
        .noise_q_flat  (noise_q_flat_r),
        .enc_q_flat    (enc_q_flat_w),
        .noisy_q_flat  (noisy_q_flat_w),
        .rounded_q_flat(rounded_q_flat_w),
        .msg_out       (msg_out_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_in_r       <= 32'b00000000000000000000000000000000;
            noise_q_flat_r <= 320'b0;
            valid_r        <= 1'b0;
            valid_out      <= 1'b0;
            enc_q_flat     <= 320'b0;
            noisy_q_flat   <= 320'b0;
            rounded_q_flat <= 320'b0;
            msg_out        <= 32'b00000000000000000000000000000000;
        end else begin
            msg_in_r       <= msg_in;
            noise_q_flat_r <= noise_q_flat;
            valid_r        <= valid_in;
            valid_out      <= valid_r;
            enc_q_flat     <= enc_q_flat_w;
            noisy_q_flat   <= noisy_q_flat_w;
            rounded_q_flat <= rounded_q_flat_w;
            msg_out        <= msg_out_w;
        end
    end

endmodule
