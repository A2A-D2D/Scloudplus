`timescale 1ns/1ps

module scloud_msgfunc_bw32_demo_reg
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,
    input  wire [31:0]  msg_in,
    input  wire [(32*Q_WIDTH)-1:0] noise_q_flat,
    output reg          valid_out,
    output reg  [(32*Q_WIDTH)-1:0] enc_q_flat,
    output reg  [(32*Q_WIDTH)-1:0] noisy_q_flat,
    output reg  [(32*Q_WIDTH)-1:0] rounded_q_flat,
    output reg  [31:0]  msg_out
);

    reg [31:0]              msg_in_r;
    reg [(32*Q_WIDTH)-1:0]  noise_q_flat_r;
    reg                     valid_r;

    wire [(32*Q_WIDTH)-1:0] enc_q_flat_w;
    wire [(32*Q_WIDTH)-1:0] noisy_q_flat_w;
    wire [(32*Q_WIDTH)-1:0] rounded_q_flat_w;
    wire [31:0]             msg_out_w;

    scloud_msgfunc_bw32_demo #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_comb (
        .msg_in        (msg_in_r),
        .noise_q_flat  (noise_q_flat_r),
        .enc_q_flat    (enc_q_flat_w),
        .noisy_q_flat  (noisy_q_flat_w),
        .rounded_q_flat(rounded_q_flat_w),
        .msg_out       (msg_out_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_in_r       <= 32'd0;
            noise_q_flat_r <= {(32*Q_WIDTH){1'b0}};
            valid_r        <= 1'b0;
            valid_out      <= 1'b0;
            enc_q_flat     <= {(32*Q_WIDTH){1'b0}};
            noisy_q_flat   <= {(32*Q_WIDTH){1'b0}};
            rounded_q_flat <= {(32*Q_WIDTH){1'b0}};
            msg_out        <= 32'd0;
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
