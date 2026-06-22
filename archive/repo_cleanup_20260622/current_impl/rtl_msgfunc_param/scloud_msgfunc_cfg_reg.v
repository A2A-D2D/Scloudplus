`timescale 1ns/1ps

module scloud_msgfunc_cfg_reg
#(
    parameter Q_WIDTH      = 12,
    parameter TAU          = 3,
    parameter MAX_Q_BITS   = 32 * Q_WIDTH,
    parameter MAX_MSG_BITS = (16*(2*TAU)) - ((16*4)/2)
)
(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [1:0]   cfg_bw_mode,
    input  wire [MAX_MSG_BITS-1:0] msg_in,
    input  wire [MAX_Q_BITS-1:0]   noise_q_flat,
    output wire         start_ready,
    output reg          busy,
    output reg          valid_out,
    output reg  [5:0]   active_q_coords,
    output reg  [6:0]   active_msg_bits,
    output reg  [MAX_Q_BITS-1:0]   enc_q_flat,
    output reg  [MAX_Q_BITS-1:0]   noisy_q_flat,
    output reg  [MAX_Q_BITS-1:0]   rounded_q_flat,
    output reg  [MAX_MSG_BITS-1:0] msg_out
);

    localparam [1:0] MODE_BW8  = 2'd0;
    localparam [1:0] MODE_BW16 = 2'd1;
    localparam [1:0] MODE_BW32 = 2'd2;

    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_WAIT_BDD = 3'd1;
    localparam [2:0] ST_LATCH    = 3'd2;
    localparam [2:0] ST_DONE     = 3'd3;

    localparam BW8_MSG_BITS   = (4*(2*TAU)) - ((4*2)/2);
    localparam BW16_MSG_BITS  = (8*(2*TAU)) - ((8*3)/2);
    localparam BW32_MSG_BITS  = MAX_MSG_BITS;
    localparam BW8_Q_BITS     = 8 * Q_WIDTH;
    localparam BW16_Q_BITS    = 16 * Q_WIDTH;
    localparam BW32_Q_BITS    = MAX_Q_BITS;

    reg [2:0]   state;
    reg [1:0]   cfg_bw_mode_r;
    reg [MAX_MSG_BITS-1:0] msg_in_r;
    reg [MAX_Q_BITS-1:0]   noise_q_flat_r;

    // per-core start/done signals
    reg  start_bw8;
    reg  start_bw16;
    reg  start_bw32;
    wire ready_bw8;
    wire ready_bw16;
    wire ready_bw32;
    wire done_bw8;
    wire done_bw16;
    wire done_bw32;

    wire [BW8_Q_BITS-1:0]    enc8_flat;
    wire [BW8_Q_BITS-1:0]    noisy8_flat;
    wire [BW8_Q_BITS-1:0]    rounded8_flat;
    wire [BW8_MSG_BITS-1:0]  msg8_out;
    wire [BW16_Q_BITS-1:0]   enc16_flat;
    wire [BW16_Q_BITS-1:0]   noisy16_flat;
    wire [BW16_Q_BITS-1:0]   rounded16_flat;
    wire [BW16_MSG_BITS-1:0] msg16_out;
    wire [BW32_Q_BITS-1:0]   enc32_flat;
    wire [BW32_Q_BITS-1:0]   noisy32_flat;
    wire [BW32_Q_BITS-1:0]   rounded32_flat;
    wire [BW32_MSG_BITS-1:0] msg32_out;

    assign start_ready = (state == ST_IDLE);

    scloud_msgfunc_param #(
        .COMPLEX_N    (4),
        .LOG_COMPLEX_N(2),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (TAU + 2),
        .MSG_WIDTH    (BW8_MSG_BITS)
    ) u_bw8 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start_bw8),
        .start_ready     (ready_bw8),
        .done            (done_bw8),
        .msg_in          (msg_in_r[BW8_MSG_BITS-1:0]),
        .noise_q_flat    (noise_q_flat_r[BW8_Q_BITS-1:0]),
        .enc_q_flat      (enc8_flat),
        .noisy_q_flat    (noisy8_flat),
        .rounded_q_flat  (rounded8_flat),
        .msg_out         (msg8_out)
    );

    scloud_msgfunc_param #(
        .COMPLEX_N    (8),
        .LOG_COMPLEX_N(3),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (TAU + 3),
        .MSG_WIDTH    (BW16_MSG_BITS)
    ) u_bw16 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start_bw16),
        .start_ready     (ready_bw16),
        .done            (done_bw16),
        .msg_in          (msg_in_r[BW16_MSG_BITS-1:0]),
        .noise_q_flat    (noise_q_flat_r[BW16_Q_BITS-1:0]),
        .enc_q_flat      (enc16_flat),
        .noisy_q_flat    (noisy16_flat),
        .rounded_q_flat  (rounded16_flat),
        .msg_out         (msg16_out)
    );

    scloud_msgfunc_param #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (TAU + 4),
        .MSG_WIDTH    (BW32_MSG_BITS)
    ) u_bw32 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start_bw32),
        .start_ready     (ready_bw32),
        .done            (done_bw32),
        .msg_in          (msg_in_r),
        .noise_q_flat    (noise_q_flat_r),
        .enc_q_flat      (enc32_flat),
        .noisy_q_flat    (noisy32_flat),
        .rounded_q_flat  (rounded32_flat),
        .msg_out         (msg32_out)
    );

    // drive start to the active core only
    always @(*) begin
        start_bw8  = 1'b0;
        start_bw16 = 1'b0;
        start_bw32 = 1'b0;
        case (cfg_bw_mode_r)
            MODE_BW8:  start_bw8  = (state == ST_IDLE) && start;
            MODE_BW16: start_bw16 = (state == ST_IDLE) && start;
            default:   start_bw32 = (state == ST_IDLE) && start;
        endcase
    end

    wire active_ready = (cfg_bw_mode_r == MODE_BW8)  ? ready_bw8 :
                        (cfg_bw_mode_r == MODE_BW16) ? ready_bw16 :
                                                       ready_bw32;
    wire active_done  = (cfg_bw_mode_r == MODE_BW8)  ? done_bw8 :
                        (cfg_bw_mode_r == MODE_BW16) ? done_bw16 :
                                                       done_bw32;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            cfg_bw_mode_r   <= MODE_BW8;
            msg_in_r        <= {MAX_MSG_BITS{1'b0}};
            noise_q_flat_r  <= {MAX_Q_BITS{1'b0}};
            busy            <= 1'b0;
            valid_out       <= 1'b0;
            active_q_coords <= 6'd0;
            active_msg_bits <= 7'd0;
            enc_q_flat      <= {MAX_Q_BITS{1'b0}};
            noisy_q_flat    <= {MAX_Q_BITS{1'b0}};
            rounded_q_flat  <= {MAX_Q_BITS{1'b0}};
            msg_out         <= {MAX_MSG_BITS{1'b0}};
        end else begin
            valid_out <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start && active_ready) begin
                        cfg_bw_mode_r   <= cfg_bw_mode;
                        msg_in_r        <= msg_in;
                        noise_q_flat_r  <= noise_q_flat;
                        busy            <= 1'b1;
                        state           <= ST_WAIT_BDD;
                    end
                end
                ST_WAIT_BDD: begin
                    busy <= 1'b1;
                    // encode outputs are combinational: latch them immediately
                    case (cfg_bw_mode_r)
                        MODE_BW8: begin
                            enc_q_flat   <= {{(MAX_Q_BITS-BW8_Q_BITS){1'b0}}, enc8_flat};
                            noisy_q_flat <= {{(MAX_Q_BITS-BW8_Q_BITS){1'b0}}, noisy8_flat};
                        end
                        MODE_BW16: begin
                            enc_q_flat   <= {{(MAX_Q_BITS-BW16_Q_BITS){1'b0}}, enc16_flat};
                            noisy_q_flat <= {{(MAX_Q_BITS-BW16_Q_BITS){1'b0}}, noisy16_flat};
                        end
                        default: begin
                            enc_q_flat   <= enc32_flat;
                            noisy_q_flat <= noisy32_flat;
                        end
                    endcase
                    if (active_done)
                        state <= ST_LATCH;
                end
                ST_LATCH: begin
                    case (cfg_bw_mode_r)
                        MODE_BW8: begin
                            active_q_coords <= 6'd8;
                            active_msg_bits <= BW8_MSG_BITS[6:0];
                            rounded_q_flat <= {{(MAX_Q_BITS-BW8_Q_BITS){1'b0}}, rounded8_flat};
                            msg_out <= {{(MAX_MSG_BITS-BW8_MSG_BITS){1'b0}}, msg8_out};
                        end
                        MODE_BW16: begin
                            active_q_coords <= 6'd16;
                            active_msg_bits <= BW16_MSG_BITS[6:0];
                            rounded_q_flat <= {{(MAX_Q_BITS-BW16_Q_BITS){1'b0}}, rounded16_flat};
                            msg_out <= {{(MAX_MSG_BITS-BW16_MSG_BITS){1'b0}}, msg16_out};
                        end
                        default: begin
                            active_q_coords <= 6'd32;
                            active_msg_bits <= BW32_MSG_BITS[6:0];
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
