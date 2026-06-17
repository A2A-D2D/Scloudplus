`timescale 1ns/1ps

module scloud_msgfunc_cfg_reg
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [1:0]   cfg_bw_mode,
    input  wire [31:0]  msg_in,
    input  wire [319:0] noise_q_flat,
    output wire         start_ready,
    output reg          busy,
    output reg          valid_out,
    output reg  [5:0]   active_q_coords,
    output reg  [5:0]   active_msg_bits,
    output reg  [319:0] enc_q_flat,
    output reg  [319:0] noisy_q_flat,
    output reg  [319:0] rounded_q_flat,
    output reg  [31:0]  msg_out
);

    localparam [1:0] MODE_BW8  = 2'd0;
    localparam [1:0] MODE_BW16 = 2'd1;
    localparam [1:0] MODE_BW32 = 2'd2;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_EVAL = 2'd1;
    localparam [1:0] ST_DONE = 2'd2;

    reg [1:0]   state;
    reg [1:0]   cfg_bw_mode_r;
    reg [31:0]  msg_in_r;
    reg [319:0] noise_q_flat_r;

    wire [79:0]  enc8_flat;
    wire [79:0]  noisy8_flat;
    wire [79:0]  rounded8_flat;
    wire [11:0]  msg8_out;
    wire [159:0] enc16_flat;
    wire [159:0] noisy16_flat;
    wire [159:0] rounded16_flat;
    wire [19:0]  msg16_out;
    wire [319:0] enc32_flat;
    wire [319:0] noisy32_flat;
    wire [319:0] rounded32_flat;
    wire [31:0]  msg32_out;

    assign start_ready = (state == ST_IDLE);

    scloud_msgfunc_param #(
        .COMPLEX_N    (4),
        .LOG_COMPLEX_N(2),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (TAU + 2),
        .MSG_WIDTH    (12)
    ) u_bw8 (
        .msg_in        (msg_in_r[11:0]),
        .noise_q_flat  (noise_q_flat_r[79:0]),
        .enc_q_flat    (enc8_flat),
        .noisy_q_flat  (noisy8_flat),
        .rounded_q_flat(rounded8_flat),
        .msg_out       (msg8_out)
    );

    scloud_msgfunc_param #(
        .COMPLEX_N    (8),
        .LOG_COMPLEX_N(3),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (TAU + 3),
        .MSG_WIDTH    (20)
    ) u_bw16 (
        .msg_in        (msg_in_r[19:0]),
        .noise_q_flat  (noise_q_flat_r[159:0]),
        .enc_q_flat    (enc16_flat),
        .noisy_q_flat  (noisy16_flat),
        .rounded_q_flat(rounded16_flat),
        .msg_out       (msg16_out)
    );

    scloud_msgfunc_param #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (TAU + 4),
        .MSG_WIDTH    (32)
    ) u_bw32 (
        .msg_in        (msg_in_r),
        .noise_q_flat  (noise_q_flat_r),
        .enc_q_flat    (enc32_flat),
        .noisy_q_flat  (noisy32_flat),
        .rounded_q_flat(rounded32_flat),
        .msg_out       (msg32_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            cfg_bw_mode_r  <= MODE_BW8;
            msg_in_r       <= 32'b00000000000000000000000000000000;
            noise_q_flat_r <= 320'b0;
            busy           <= 1'b0;
            valid_out      <= 1'b0;
            active_q_coords <= 6'd0;
            active_msg_bits <= 6'd0;
            enc_q_flat     <= 320'b0;
            noisy_q_flat   <= 320'b0;
            rounded_q_flat <= 320'b0;
            msg_out        <= 32'b00000000000000000000000000000000;
        end else begin
            valid_out <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        cfg_bw_mode_r  <= cfg_bw_mode;
                        msg_in_r       <= msg_in;
                        noise_q_flat_r <= noise_q_flat;
                        busy           <= 1'b1;
                        state          <= ST_EVAL;
                    end
                end
                ST_EVAL: begin
                    case (cfg_bw_mode_r)
                        MODE_BW8: begin
                            active_q_coords <= 6'd8;
                            active_msg_bits <= 6'd12;
                            enc_q_flat <= {240'b0, enc8_flat};
                            noisy_q_flat <= {240'b0, noisy8_flat};
                            rounded_q_flat <= {240'b0, rounded8_flat};
                            msg_out <= {20'b00000000000000000000, msg8_out};
                        end
                        MODE_BW16: begin
                            active_q_coords <= 6'd16;
                            active_msg_bits <= 6'd20;
                            enc_q_flat <= {160'b0, enc16_flat};
                            noisy_q_flat <= {160'b0, noisy16_flat};
                            rounded_q_flat <= {160'b0, rounded16_flat};
                            msg_out <= {12'b000000000000, msg16_out};
                        end
                        default: begin
                            active_q_coords <= 6'd32;
                            active_msg_bits <= 6'd32;
                            enc_q_flat <= enc32_flat;
                            noisy_q_flat <= noisy32_flat;
                            rounded_q_flat <= rounded32_flat;
                            msg_out <= msg32_out;
                        end
                    endcase
                    state <= ST_DONE;
                end
                ST_DONE: begin
                    valid_out <= 1'b1;
                    busy      <= 1'b0;
                    state     <= ST_IDLE;
                end
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
