`timescale 1ns/1ps

/*
 * Sequential BW32 message decoder.
 *
 * BDD32 is executed through scloud_bdd32_seq.  The q-to-label, inverse phi,
 * and delabel stages are then registered one stage per cycle to keep the
 * post-BDD critical path short.
 */
module scloud_msgdec_bw32_seq
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [(32*Q_WIDTH)-1:0] noisy_q_flat,
    output wire                    start_ready,
    output reg                     busy,
    output reg                     done,
    output reg  [31:0]             msg_block,
    output reg  [(32*Q_WIDTH)-1:0] rounded_q_flat
);

    localparam [3:0] ST_IDLE    = 4'd0;
    localparam [3:0] ST_BDD     = 4'd1;
    localparam [3:0] ST_UNPACK  = 4'd2;
    localparam [3:0] ST_INV8    = 4'd3;
    localparam [3:0] ST_INV4    = 4'd4;
    localparam [3:0] ST_INV2    = 4'd5;
    localparam [3:0] ST_INV1    = 4'd6;
    localparam [3:0] ST_DELABEL = 4'd7;
    localparam [3:0] ST_DONE    = 4'd8;

    localparam LABEL_WIDTH_TOTAL = 16 * 12;

    reg [3:0] state;
    reg [LABEL_WIDTH_TOTAL-1:0] label_r;

    wire bdd_start_ready;
    wire bdd_busy;
    wire bdd_done;
    wire bdd_start;
    wire [(32*Q_WIDTH)-1:0] rounded_q_w;

    wire [(16*12)-1:0] quant_label_flat;
    wire [(16*12)-1:0] stage8_flat;
    wire [(16*12)-1:0] stage4_flat;
    wire [(16*12)-1:0] stage2_flat;
    wire [(16*12)-1:0] raw_label_flat;
    wire [31:0]        msg_block_w;

    wire [1:0] r0_bits;  wire [1:0] i0_bits;
    wire [1:0] r1_bits;  wire [1:0] i1_bits;
    wire [1:0] r2_bits;  wire [1:0] i2_bits;
    wire [1:0] r3_bits;  wire [1:0] i3_bits;
    wire [1:0] r4_bits;  wire [1:0] i4_bits;
    wire [1:0] r5_bits;  wire [1:0] i5_bits;
    wire [1:0] r6_bits;  wire [1:0] i6_bits;
    wire [1:0] r7_bits;  wire [1:0] i7_bits;
    wire [1:0] r8_bits;  wire [1:0] i8_bits;
    wire [1:0] r9_bits;  wire [1:0] i9_bits;
    wire [1:0] r10_bits; wire [1:0] i10_bits;
    wire [1:0] r11_bits; wire [1:0] i11_bits;
    wire [1:0] r12_bits; wire [1:0] i12_bits;
    wire [1:0] r13_bits; wire [1:0] i13_bits;
    wire [1:0] r14_bits; wire [1:0] i14_bits;
    wire [1:0] r15_bits; wire [1:0] i15_bits;

    assign start_ready = (state == ST_IDLE) && bdd_start_ready;
    assign bdd_start = start && start_ready;

    scloud_bdd32_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_bdd32_seq (
        .target_flat (noisy_q_flat),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (bdd_start),
        .start_ready (bdd_start_ready),
        .busy        (bdd_busy),
        .done        (bdd_done),
        .decoded_flat(rounded_q_w)
    );

    scloud_bw32_q_to_label #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_unpack_q (
        .q_flat    (rounded_q_flat),
        .label_flat(quant_label_flat)
    );

    scloud_bw32_inv_phi_stage6 #(.STAGE_COMPLEX(8)) u_inv_stage8 (
        .label_in_flat (label_r),
        .label_out_flat(stage8_flat)
    );

    scloud_bw32_inv_phi_stage6 #(.STAGE_COMPLEX(4)) u_inv_stage4 (
        .label_in_flat (label_r),
        .label_out_flat(stage4_flat)
    );

    scloud_bw32_inv_phi_stage6 #(.STAGE_COMPLEX(2)) u_inv_stage2 (
        .label_in_flat (label_r),
        .label_out_flat(stage2_flat)
    );

    scloud_bw32_inv_phi_stage6 #(.STAGE_COMPLEX(1)) u_inv_stage1 (
        .label_in_flat (label_r),
        .label_out_flat(raw_label_flat)
    );

    scloud_bw32_delabel_tau2 #(.WH(0)) u_delabel_0  (.raw_re(label_r[(0*6)+:6]),  .raw_im(label_r[(1*6)+:6]),  .re_bits(r0_bits),  .im_bits(i0_bits));
    scloud_bw32_delabel_tau2 #(.WH(1)) u_delabel_1  (.raw_re(label_r[(2*6)+:6]),  .raw_im(label_r[(3*6)+:6]),  .re_bits(r1_bits),  .im_bits(i1_bits));
    scloud_bw32_delabel_tau2 #(.WH(1)) u_delabel_2  (.raw_re(label_r[(4*6)+:6]),  .raw_im(label_r[(5*6)+:6]),  .re_bits(r2_bits),  .im_bits(i2_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_3  (.raw_re(label_r[(6*6)+:6]),  .raw_im(label_r[(7*6)+:6]),  .re_bits(r3_bits),  .im_bits(i3_bits));
    scloud_bw32_delabel_tau2 #(.WH(1)) u_delabel_4  (.raw_re(label_r[(8*6)+:6]),  .raw_im(label_r[(9*6)+:6]),  .re_bits(r4_bits),  .im_bits(i4_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_5  (.raw_re(label_r[(10*6)+:6]), .raw_im(label_r[(11*6)+:6]), .re_bits(r5_bits),  .im_bits(i5_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_6  (.raw_re(label_r[(12*6)+:6]), .raw_im(label_r[(13*6)+:6]), .re_bits(r6_bits),  .im_bits(i6_bits));
    scloud_bw32_delabel_tau2 #(.WH(3)) u_delabel_7  (.raw_re(label_r[(14*6)+:6]), .raw_im(label_r[(15*6)+:6]), .re_bits(r7_bits),  .im_bits(i7_bits));
    scloud_bw32_delabel_tau2 #(.WH(1)) u_delabel_8  (.raw_re(label_r[(16*6)+:6]), .raw_im(label_r[(17*6)+:6]), .re_bits(r8_bits),  .im_bits(i8_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_9  (.raw_re(label_r[(18*6)+:6]), .raw_im(label_r[(19*6)+:6]), .re_bits(r9_bits),  .im_bits(i9_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_10 (.raw_re(label_r[(20*6)+:6]), .raw_im(label_r[(21*6)+:6]), .re_bits(r10_bits), .im_bits(i10_bits));
    scloud_bw32_delabel_tau2 #(.WH(3)) u_delabel_11 (.raw_re(label_r[(22*6)+:6]), .raw_im(label_r[(23*6)+:6]), .re_bits(r11_bits), .im_bits(i11_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_12 (.raw_re(label_r[(24*6)+:6]), .raw_im(label_r[(25*6)+:6]), .re_bits(r12_bits), .im_bits(i12_bits));
    scloud_bw32_delabel_tau2 #(.WH(3)) u_delabel_13 (.raw_re(label_r[(26*6)+:6]), .raw_im(label_r[(27*6)+:6]), .re_bits(r13_bits), .im_bits(i13_bits));
    scloud_bw32_delabel_tau2 #(.WH(3)) u_delabel_14 (.raw_re(label_r[(28*6)+:6]), .raw_im(label_r[(29*6)+:6]), .re_bits(r14_bits), .im_bits(i14_bits));
    scloud_bw32_delabel_tau2 #(.WH(4)) u_delabel_15 (.raw_re(label_r[(30*6)+:6]), .raw_im(label_r[(31*6)+:6]), .re_bits(r15_bits), .im_bits(i15_bits));

    assign msg_block_w = {
        r0_bits[1:0],  i0_bits[1:0],
        r1_bits[1:0],  i1_bits[0],
        r2_bits[1:0],  i2_bits[0],
        r3_bits[0],    i3_bits[0],
        r4_bits[1:0],  i4_bits[0],
        r5_bits[0],    i5_bits[0],
        r6_bits[0],    i6_bits[0],
        r7_bits[0],
        r8_bits[1:0],  i8_bits[0],
        r9_bits[0],    i9_bits[0],
        r10_bits[0],   i10_bits[0],
        r11_bits[0],
        r12_bits[0],   i12_bits[0],
        r13_bits[0],
        r14_bits[0]
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            msg_block      <= 32'd0;
            label_r        <= {LABEL_WIDTH_TOTAL{1'b0}};
            rounded_q_flat <= {(32*Q_WIDTH){1'b0}};
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (bdd_start) begin
                        busy  <= 1'b1;
                        state <= ST_BDD;
                    end
                end
                ST_BDD: begin
                    busy <= 1'b1;
                    if (bdd_done) begin
                        rounded_q_flat <= rounded_q_w;
                        state          <= ST_UNPACK;
                    end
                end
                ST_UNPACK: begin
                    busy    <= 1'b1;
                    label_r <= quant_label_flat;
                    state   <= ST_INV8;
                end
                ST_INV8: begin
                    busy    <= 1'b1;
                    label_r <= stage8_flat;
                    state   <= ST_INV4;
                end
                ST_INV4: begin
                    busy    <= 1'b1;
                    label_r <= stage4_flat;
                    state   <= ST_INV2;
                end
                ST_INV2: begin
                    busy    <= 1'b1;
                    label_r <= stage2_flat;
                    state   <= ST_INV1;
                end
                ST_INV1: begin
                    busy    <= 1'b1;
                    label_r <= raw_label_flat;
                    state   <= ST_DELABEL;
                end
                ST_DELABEL: begin
                    busy      <= 1'b1;
                    msg_block <= msg_block_w;
                    state     <= ST_DONE;
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
