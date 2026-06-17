`timescale 1ns/1ps

/*
 * Sequential BW32 message-function demo top.
 *
 * This module preserves the combinational demo datapath:
 *   MsgEnc -> q-domain noise add -> MsgDec
 * but executes MsgEnc and MsgDec through the registered BW32 engines.
 */
module scloud_msgfunc_bw32_seq
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [31:0]             msg_in,
    input  wire [(32*Q_WIDTH)-1:0] noise_q_flat,
    output wire                    start_ready,
    output reg                     busy,
    output reg                     done,
    output reg  [(32*Q_WIDTH)-1:0] enc_q_flat,
    output reg  [(32*Q_WIDTH)-1:0] noisy_q_flat,
    output reg  [(32*Q_WIDTH)-1:0] rounded_q_flat,
    output reg  [31:0]             msg_out
);

    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_ENC      = 3'd1;
    localparam [2:0] ST_ADD      = 3'd2;
    localparam [2:0] ST_DEC_START = 3'd3;
    localparam [2:0] ST_DEC_WAIT  = 3'd4;
    localparam [2:0] ST_DONE      = 3'd5;

    reg [2:0] state;
    reg [(32*Q_WIDTH)-1:0] noise_r;

    wire enc_start_ready;
    wire enc_busy;
    wire enc_done;
    wire enc_start;
    wire [(32*Q_WIDTH)-1:0] enc_q_w;

    wire dec_start_ready;
    wire dec_busy;
    wire dec_done;
    wire dec_start;
    wire [31:0] dec_msg_w;
    wire [(32*Q_WIDTH)-1:0] dec_rounded_w;

    integer ai;

    assign start_ready = (state == ST_IDLE) && enc_start_ready && dec_start_ready;
    assign enc_start   = start && start_ready;
    assign dec_start   = (state == ST_DEC_START) && dec_start_ready;

    scloud_msgenc_bw32_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_msgenc_seq (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (enc_start),
        .msg_block   (msg_in),
        .start_ready (enc_start_ready),
        .busy        (enc_busy),
        .done        (enc_done),
        .code_q_flat (enc_q_w)
    );

    scloud_msgdec_bw32_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_msgdec_seq (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (dec_start),
        .noisy_q_flat   (noisy_q_flat),
        .start_ready    (dec_start_ready),
        .busy           (dec_busy),
        .done           (dec_done),
        .msg_block      (dec_msg_w),
        .rounded_q_flat (dec_rounded_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            noise_r        <= {(32*Q_WIDTH){1'b0}};
            enc_q_flat     <= {(32*Q_WIDTH){1'b0}};
            noisy_q_flat   <= {(32*Q_WIDTH){1'b0}};
            rounded_q_flat <= {(32*Q_WIDTH){1'b0}};
            msg_out        <= 32'd0;
            busy           <= 1'b0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start_ready && start) begin
                        noise_r <= noise_q_flat;
                        busy    <= 1'b1;
                        state   <= ST_ENC;
                    end
                end
                ST_ENC: begin
                    busy <= 1'b1;
                    if (enc_done) begin
                        enc_q_flat <= enc_q_w;
                        state      <= ST_ADD;
                    end
                end
                ST_ADD: begin
                    busy <= 1'b1;
                    for (ai = 0; ai < 32; ai = ai + 1) begin
                        noisy_q_flat[(ai*Q_WIDTH)+:Q_WIDTH] <=
                            enc_q_flat[(ai*Q_WIDTH)+:Q_WIDTH] +
                            noise_r[(ai*Q_WIDTH)+:Q_WIDTH];
                    end
                    state <= ST_DEC_START;
                end
                ST_DEC_START: begin
                    busy <= 1'b1;
                    if (dec_start_ready) begin
                        state <= ST_DEC_WAIT;
                    end
                end
                ST_DEC_WAIT: begin
                    busy <= 1'b1;
                    if (dec_done) begin
                        rounded_q_flat <= dec_rounded_w;
                        msg_out        <= dec_msg_w;
                        state          <= ST_DONE;
                    end
                end
                ST_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end
                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
