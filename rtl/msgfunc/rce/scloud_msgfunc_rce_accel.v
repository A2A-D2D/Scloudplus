`timescale 1ns/1ps

/*
 * Scloud+ MsgEnc/MsgDec accelerator wrapper for SPUV3 RCE-style DPRAM access.
 *
 * Addressing:
 *   All base addresses are 256-bit DPRAM word addresses.
 *
 * Data layout:
 *   msg block: one 256-bit word per BW32 block, lower 64 bits used for tau=3
 *              and lower 96 bits used for tau=4.
 *   q block  : two 256-bit words per BW32 block. Each word stores sixteen
 *              uint16 lanes; the low 12 bits of each lane carry one Q value.
 *
 * Operations:
 *   OP_MSGENC     : read msg_in, write encoded Q block to q_out.
 *   OP_MSGDEC     : read q_in, decode, write msg_out, optionally write rounded
 *                   Q to q_out when dec_write_q is set.
 *   OP_MSGENC_ADD : read msg_in and q_in, write q_in + MsgEnc(msg) to q_out.
 *   OP_SUB_MSGDEC : read q_in and q_aux, decode q_in - q_aux, write msg_out
 *                   and optionally write rounded Q to q_out.
 */
module scloud_msgfunc_rce_accel
#(
    parameter DPRAM_ADDR_WIDTH = 16,
    parameter Q_WIDTH          = 12
)
(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start,
    input  wire [1:0]                   op,
    input  wire                         tau_sel,
    input  wire [2:0]                   block_count,
    input  wire                         dec_write_q,

    input  wire [DPRAM_ADDR_WIDTH-1:0]  msg_in_base,
    input  wire [DPRAM_ADDR_WIDTH-1:0]  msg_out_base,
    input  wire [DPRAM_ADDR_WIDTH-1:0]  q_in_base,
    input  wire [DPRAM_ADDR_WIDTH-1:0]  q_aux_base,
    input  wire [DPRAM_ADDR_WIDTH-1:0]  q_out_base,

    output wire                         start_ready,
    output reg                          busy,
    output reg                          done,
    output reg                          error,

    output reg                          dpram_en,
    output reg                          dpram_wr_en,
    output reg  [31:0]                  dpram_be,
    output reg  [DPRAM_ADDR_WIDTH-1:0]  dpram_addr,
    output reg  [255:0]                 dpram_wdata,
    input  wire [255:0]                 dpram_rdata
);

    localparam [1:0] OP_MSGENC     = 2'd0;
    localparam [1:0] OP_MSGDEC     = 2'd1;
    localparam [1:0] OP_MSGENC_ADD = 2'd2;
    localparam [1:0] OP_SUB_MSGDEC = 2'd3;

    localparam TAU3_MSG_BITS = 64;
    localparam TAU4_MSG_BITS = 96;
    localparam Q_BITS        = 32 * Q_WIDTH;
    localparam Q_HALF_BITS   = 16 * Q_WIDTH;

    localparam [4:0] ST_IDLE       = 5'd0;
    localparam [4:0] ST_READ_MSG   = 5'd1;
    localparam [4:0] ST_CAP_MSG    = 5'd2;
    localparam [4:0] ST_READ_Q0    = 5'd3;
    localparam [4:0] ST_CAP_Q0     = 5'd4;
    localparam [4:0] ST_READ_Q1    = 5'd5;
    localparam [4:0] ST_CAP_Q1     = 5'd6;
    localparam [4:0] ST_READ_AUX0  = 5'd7;
    localparam [4:0] ST_CAP_AUX0   = 5'd8;
    localparam [4:0] ST_READ_AUX1  = 5'd9;
    localparam [4:0] ST_CAP_AUX1   = 5'd10;
    localparam [4:0] ST_START_DEC  = 5'd11;
    localparam [4:0] ST_WAIT_DEC   = 5'd12;
    localparam [4:0] ST_WRITE_Q0   = 5'd13;
    localparam [4:0] ST_WRITE_Q1   = 5'd14;
    localparam [4:0] ST_WRITE_MSG  = 5'd15;
    localparam [4:0] ST_NEXT_BLOCK = 5'd16;
    localparam [4:0] ST_DONE       = 5'd17;
    localparam [4:0] ST_PREP_ENC   = 5'd18;

    reg [4:0]                  state;
    reg [1:0]                  op_r;
    reg                        tau_sel_r;
    reg                        dec_write_q_r;
    reg [2:0]                  block_count_r;
    reg [2:0]                  block_idx;
    reg [DPRAM_ADDR_WIDTH-1:0] msg_in_base_r;
    reg [DPRAM_ADDR_WIDTH-1:0] msg_out_base_r;
    reg [DPRAM_ADDR_WIDTH-1:0] q_in_base_r;
    reg [DPRAM_ADDR_WIDTH-1:0] q_aux_base_r;
    reg [DPRAM_ADDR_WIDTH-1:0] q_out_base_r;
    reg [255:0]                msg_word_r;
    reg [Q_BITS-1:0]           q_in_flat_r;
    reg [Q_BITS-1:0]           q_aux_flat_r;
    reg [TAU4_MSG_BITS-1:0]    msg_result_r;
    reg                        dec_start;

    wire [Q_BITS-1:0]        enc_tau3_flat;
    wire [Q_BITS-1:0]        enc_tau4_flat;
    wire [TAU3_MSG_BITS-1:0] dec_tau3_msg;
    wire [TAU4_MSG_BITS-1:0] dec_tau4_msg;
    wire [Q_BITS-1:0]        rounded_rt_flat;
    wire                     dec_rt_ready;
    wire                     dec_rt_done;
    wire [(32*7)-1:0]       quant_label_tau3_flat;
    wire [(32*7)-1:0]       raw_label_tau3_flat;
    wire [(32*8)-1:0]       quant_label_tau4_flat;
    wire [(32*8)-1:0]       raw_label_tau4_flat;
    wire [Q_BITS-1:0]        enc_selected_flat;
    wire [Q_BITS-1:0]        dec_input_flat;
    wire [Q_BITS-1:0]        dec_rounded_flat;
    wire [TAU4_MSG_BITS-1:0] dec_msg_padded;
    wire                     dec_selected_ready;
    wire                     dec_selected_done;
    wire                     op_is_dec;
    wire                     op_needs_msg;
    wire                     op_needs_q;
    wire                     op_needs_aux;
    wire                     op_writes_msg;
    wire                     op_writes_q;
    wire [Q_BITS-1:0]        q_write_flat;
    wire [DPRAM_ADDR_WIDTH-1:0] block_q_offset;

    assign start_ready = (state == ST_IDLE);

    assign op_is_dec    = (op_r == OP_MSGDEC) || (op_r == OP_SUB_MSGDEC);
    assign op_needs_msg = (op_r == OP_MSGENC) || (op_r == OP_MSGENC_ADD);
    assign op_needs_q   = (op_r == OP_MSGDEC) || (op_r == OP_MSGENC_ADD) ||
                          (op_r == OP_SUB_MSGDEC);
    assign op_needs_aux = (op_r == OP_SUB_MSGDEC);
    assign op_writes_msg = op_is_dec;
    assign op_writes_q = (op_r == OP_MSGENC) || (op_r == OP_MSGENC_ADD) ||
                         (op_is_dec && dec_write_q_r);
    assign block_q_offset = {{(DPRAM_ADDR_WIDTH-3){1'b0}}, block_idx} << 1;

    assign enc_selected_flat = tau_sel_r ? enc_tau4_flat : enc_tau3_flat;
    assign dec_input_flat = (op_r == OP_SUB_MSGDEC) ?
                            q_sub_mod(q_in_flat_r, q_aux_flat_r) :
                            q_in_flat_r;
    assign dec_rounded_flat = rounded_rt_flat;
    assign dec_msg_padded = tau_sel_r ? dec_tau4_msg :
                            {{(TAU4_MSG_BITS-TAU3_MSG_BITS){1'b0}}, dec_tau3_msg};
    assign dec_selected_ready = dec_rt_ready;
    assign dec_selected_done  = dec_rt_done;
    assign q_write_flat = (op_r == OP_MSGENC)     ? enc_selected_flat :
                          (op_r == OP_MSGENC_ADD) ? q_add_mod(q_in_flat_r, enc_selected_flat) :
                                                     dec_rounded_flat;

    function [Q_HALF_BITS-1:0] word_to_q_half;
        input [255:0] word_in;
        integer lane;
        begin
            word_to_q_half = {Q_HALF_BITS{1'b0}};
            for (lane = 0; lane < 16; lane = lane + 1) begin
                word_to_q_half[(lane*Q_WIDTH)+:Q_WIDTH] =
                    word_in[(lane*16)+:Q_WIDTH];
            end
        end
    endfunction

    function [255:0] q_half_to_word;
        input [Q_HALF_BITS-1:0] q_half_in;
        integer lane;
        begin
            q_half_to_word = 256'b0;
            for (lane = 0; lane < 16; lane = lane + 1) begin
                q_half_to_word[(lane*16)+:Q_WIDTH] =
                    q_half_in[(lane*Q_WIDTH)+:Q_WIDTH];
            end
        end
    endfunction

    function [Q_BITS-1:0] q_add_mod;
        input [Q_BITS-1:0] a;
        input [Q_BITS-1:0] b;
        integer lane;
        reg [Q_WIDTH:0] sum;
        begin
            q_add_mod = {Q_BITS{1'b0}};
            for (lane = 0; lane < 32; lane = lane + 1) begin
                sum = {1'b0, a[(lane*Q_WIDTH)+:Q_WIDTH]} +
                      {1'b0, b[(lane*Q_WIDTH)+:Q_WIDTH]};
                q_add_mod[(lane*Q_WIDTH)+:Q_WIDTH] = sum[Q_WIDTH-1:0];
            end
        end
    endfunction

    function [Q_BITS-1:0] q_sub_mod;
        input [Q_BITS-1:0] a;
        input [Q_BITS-1:0] b;
        integer lane;
        reg [Q_WIDTH:0] diff;
        begin
            q_sub_mod = {Q_BITS{1'b0}};
            for (lane = 0; lane < 32; lane = lane + 1) begin
                diff = {1'b0, a[(lane*Q_WIDTH)+:Q_WIDTH]} -
                       {1'b0, b[(lane*Q_WIDTH)+:Q_WIDTH]};
                q_sub_mod[(lane*Q_WIDTH)+:Q_WIDTH] = diff[Q_WIDTH-1:0];
            end
        end
    endfunction

    scloud_msgenc_param #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (3),
        .LABEL_WIDTH  (7),
        .MSG_WIDTH    (TAU3_MSG_BITS)
    ) u_msgenc_tau3 (
        .msg_block  (msg_word_r[TAU3_MSG_BITS-1:0]),
        .code_q_flat(enc_tau3_flat)
    );

    scloud_msgenc_param #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (4),
        .LABEL_WIDTH  (8),
        .MSG_WIDTH    (TAU4_MSG_BITS)
    ) u_msgenc_tau4 (
        .msg_block  (msg_word_r[TAU4_MSG_BITS-1:0]),
        .code_q_flat(enc_tau4_flat)
    );

    scloud_bdd32_seq_rt #(
        .Q_WIDTH(Q_WIDTH)
    ) u_bdd_rt (
        .target_flat  (dec_input_flat),
        .tau_sel      (tau_sel_r),
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (dec_start),
        .start_ready  (dec_rt_ready),
        .busy         (),
        .done         (dec_rt_done),
        .decoded_flat (rounded_rt_flat)
    );

    scloud_msgfunc_q_to_label #(
        .COMPLEX_N  (16),
        .Q_WIDTH    (Q_WIDTH),
        .TAU        (3),
        .LABEL_WIDTH(7)
    ) u_q_to_label_tau3 (
        .q_flat    (rounded_rt_flat),
        .label_flat(quant_label_tau3_flat)
    );

    scloud_msgfunc_phi_decode #(
        .COMPLEX_N  (16),
        .LABEL_WIDTH(7)
    ) u_phi_decode_tau3 (
        .label_in_flat (quant_label_tau3_flat),
        .label_out_flat(raw_label_tau3_flat)
    );

    scloud_msgfunc_label_to_msg #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .TAU          (3),
        .LABEL_WIDTH  (7),
        .MSG_WIDTH    (TAU3_MSG_BITS)
    ) u_label_to_msg_tau3 (
        .label_flat(raw_label_tau3_flat),
        .msg_out   (dec_tau3_msg)
    );

    scloud_msgfunc_q_to_label #(
        .COMPLEX_N  (16),
        .Q_WIDTH    (Q_WIDTH),
        .TAU        (4),
        .LABEL_WIDTH(8)
    ) u_q_to_label_tau4 (
        .q_flat    (rounded_rt_flat),
        .label_flat(quant_label_tau4_flat)
    );

    scloud_msgfunc_phi_decode #(
        .COMPLEX_N  (16),
        .LABEL_WIDTH(8)
    ) u_phi_decode_tau4 (
        .label_in_flat (quant_label_tau4_flat),
        .label_out_flat(raw_label_tau4_flat)
    );

    scloud_msgfunc_label_to_msg #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .TAU          (4),
        .LABEL_WIDTH  (8),
        .MSG_WIDTH    (TAU4_MSG_BITS)
    ) u_label_to_msg_tau4 (
        .label_flat(raw_label_tau4_flat),
        .msg_out   (dec_tau4_msg)
    );

    always @(*) begin
        dpram_en      = 1'b0;
        dpram_wr_en   = 1'b0;
        dpram_be      = 32'h00000000;
        dpram_addr    = {DPRAM_ADDR_WIDTH{1'b0}};
        dpram_wdata   = 256'b0;
        dec_start = 1'b0;

        case (state)
            ST_READ_MSG: begin
                dpram_en   = 1'b1;
                dpram_addr = msg_in_base_r + {{(DPRAM_ADDR_WIDTH-3){1'b0}}, block_idx};
            end
            ST_READ_Q0: begin
                dpram_en   = 1'b1;
                dpram_addr = q_in_base_r + block_q_offset;
            end
            ST_READ_Q1: begin
                dpram_en   = 1'b1;
                dpram_addr = q_in_base_r + block_q_offset +
                             {{(DPRAM_ADDR_WIDTH-1){1'b0}}, 1'b1};
            end
            ST_READ_AUX0: begin
                dpram_en   = 1'b1;
                dpram_addr = q_aux_base_r + block_q_offset;
            end
            ST_READ_AUX1: begin
                dpram_en   = 1'b1;
                dpram_addr = q_aux_base_r + block_q_offset +
                             {{(DPRAM_ADDR_WIDTH-1){1'b0}}, 1'b1};
            end
            ST_START_DEC: begin
                dec_start = dec_selected_ready;
            end
            ST_WRITE_Q0: begin
                dpram_en     = 1'b1;
                dpram_wr_en  = 1'b1;
                dpram_be     = 32'hffffffff;
                dpram_addr   = q_out_base_r + block_q_offset;
                dpram_wdata  = q_half_to_word(q_write_flat[0+:Q_HALF_BITS]);
            end
            ST_WRITE_Q1: begin
                dpram_en     = 1'b1;
                dpram_wr_en  = 1'b1;
                dpram_be     = 32'hffffffff;
                dpram_addr   = q_out_base_r + block_q_offset +
                               {{(DPRAM_ADDR_WIDTH-1){1'b0}}, 1'b1};
                dpram_wdata  = q_half_to_word(q_write_flat[Q_HALF_BITS+:Q_HALF_BITS]);
            end
            ST_WRITE_MSG: begin
                dpram_en    = 1'b1;
                dpram_wr_en = 1'b1;
                dpram_be    = tau_sel_r ? 32'h00000fff : 32'h000000ff;
                dpram_addr  = msg_out_base_r + {{(DPRAM_ADDR_WIDTH-3){1'b0}}, block_idx};
                dpram_wdata = {160'b0, msg_result_r};
            end
            default: begin
                dpram_en      = 1'b0;
                dpram_wr_en   = 1'b0;
                dpram_be      = 32'h00000000;
                dpram_addr    = {DPRAM_ADDR_WIDTH{1'b0}};
                dpram_wdata   = 256'b0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            op_r           <= OP_MSGENC;
            tau_sel_r      <= 1'b0;
            dec_write_q_r  <= 1'b0;
            block_count_r  <= 3'd0;
            block_idx      <= 3'd0;
            msg_in_base_r  <= {DPRAM_ADDR_WIDTH{1'b0}};
            msg_out_base_r <= {DPRAM_ADDR_WIDTH{1'b0}};
            q_in_base_r    <= {DPRAM_ADDR_WIDTH{1'b0}};
            q_aux_base_r   <= {DPRAM_ADDR_WIDTH{1'b0}};
            q_out_base_r   <= {DPRAM_ADDR_WIDTH{1'b0}};
            msg_word_r     <= 256'b0;
            q_in_flat_r    <= {Q_BITS{1'b0}};
            q_aux_flat_r   <= {Q_BITS{1'b0}};
            msg_result_r   <= {TAU4_MSG_BITS{1'b0}};
            busy           <= 1'b0;
            done           <= 1'b0;
            error          <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        op_r           <= op;
                        tau_sel_r      <= tau_sel;
                        dec_write_q_r  <= dec_write_q;
                        block_count_r  <= block_count;
                        block_idx      <= 3'd0;
                        msg_in_base_r  <= msg_in_base;
                        msg_out_base_r <= msg_out_base;
                        q_in_base_r    <= q_in_base;
                        q_aux_base_r   <= q_aux_base;
                        q_out_base_r   <= q_out_base;
                        error          <= (block_count == 3'd0) || (block_count > 3'd4);
                        busy           <= 1'b1;
                        if ((block_count == 3'd0) || (block_count > 3'd4))
                            state <= ST_DONE;
                        else if ((op == OP_MSGENC) || (op == OP_MSGENC_ADD))
                            state <= ST_READ_MSG;
                        else
                            state <= ST_READ_Q0;
                    end
                end
                ST_READ_MSG: begin
                    busy  <= 1'b1;
                    state <= ST_CAP_MSG;
                end
                ST_CAP_MSG: begin
                    msg_word_r <= dpram_rdata;
                    if (op_needs_q)
                        state <= ST_READ_Q0;
                    else begin
                        state <= ST_PREP_ENC;
                    end
                end
                ST_PREP_ENC: begin
                    state <= ST_WRITE_Q0;
                end
                ST_READ_Q0: begin
                    state <= ST_CAP_Q0;
                end
                ST_CAP_Q0: begin
                    q_in_flat_r[0+:Q_HALF_BITS] <= word_to_q_half(dpram_rdata);
                    state <= ST_READ_Q1;
                end
                ST_READ_Q1: begin
                    state <= ST_CAP_Q1;
                end
                ST_CAP_Q1: begin
                    q_in_flat_r[Q_HALF_BITS+:Q_HALF_BITS] <= word_to_q_half(dpram_rdata);
                    if (op_needs_aux)
                        state <= ST_READ_AUX0;
                    else if (op_is_dec)
                        state <= ST_START_DEC;
                    else begin
                        state <= ST_WRITE_Q0;
                    end
                end
                ST_READ_AUX0: begin
                    state <= ST_CAP_AUX0;
                end
                ST_CAP_AUX0: begin
                    q_aux_flat_r[0+:Q_HALF_BITS] <= word_to_q_half(dpram_rdata);
                    state <= ST_READ_AUX1;
                end
                ST_READ_AUX1: begin
                    state <= ST_CAP_AUX1;
                end
                ST_CAP_AUX1: begin
                    q_aux_flat_r[Q_HALF_BITS+:Q_HALF_BITS] <= word_to_q_half(dpram_rdata);
                    state <= ST_START_DEC;
                end
                ST_START_DEC: begin
                    if (dec_selected_ready)
                        state <= ST_WAIT_DEC;
                end
                ST_WAIT_DEC: begin
                    if (dec_selected_done) begin
                        msg_result_r    <= dec_msg_padded;
                        if (op_writes_q)
                            state <= ST_WRITE_Q0;
                        else
                            state <= ST_WRITE_MSG;
                    end
                end
                ST_WRITE_Q0: begin
                    state <= ST_WRITE_Q1;
                end
                ST_WRITE_Q1: begin
                    if (op_writes_msg)
                        state <= ST_WRITE_MSG;
                    else
                        state <= ST_NEXT_BLOCK;
                end
                ST_WRITE_MSG: begin
                    state <= ST_NEXT_BLOCK;
                end
                ST_NEXT_BLOCK: begin
                    if (block_idx + 3'd1 >= block_count_r) begin
                        state <= ST_DONE;
                    end else begin
                        block_idx <= block_idx + 3'd1;
                        if (op_needs_msg)
                            state <= ST_READ_MSG;
                        else
                            state <= ST_READ_Q0;
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
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule
