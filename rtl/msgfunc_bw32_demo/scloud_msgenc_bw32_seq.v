`timescale 1ns/1ps

/*
 * Sequential BW32 message encoder.
 *
 * The combinational label map is followed by one registered cycle per phi
 * stage and one final pack cycle. This mirrors the fast-scloud+ MsgEnc idea of
 * iterating the tensor-product update instead of keeping all stages in one
 * combinational path.
 */
module scloud_msgenc_bw32_seq
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [31:0]             msg_block,
    output wire                    start_ready,
    output reg                     busy,
    output reg                     done,
    output reg  [(32*Q_WIDTH)-1:0] code_q_flat
);

    localparam LABEL_WIDTH_TOTAL = 16 * 12;

    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_STAGE1 = 3'd1;
    localparam [2:0] ST_STAGE2 = 3'd2;
    localparam [2:0] ST_STAGE4 = 3'd3;
    localparam [2:0] ST_STAGE8 = 3'd4;
    localparam [2:0] ST_PACK   = 3'd5;
    localparam [2:0] ST_DONE   = 3'd6;

    reg [2:0] state;
    reg [31:0] msg_r;
    reg [LABEL_WIDTH_TOTAL-1:0] label_r;

    wire [LABEL_WIDTH_TOTAL-1:0] label0_flat;
    wire [LABEL_WIDTH_TOTAL-1:0] stage1_w;
    wire [LABEL_WIDTH_TOTAL-1:0] stage2_w;
    wire [LABEL_WIDTH_TOTAL-1:0] stage4_w;
    wire [LABEL_WIDTH_TOTAL-1:0] stage8_w;
    wire [(32*Q_WIDTH)-1:0]      code_q_w;

    assign start_ready = (state == ST_IDLE);

    assign label0_flat[(0*6)+:6]  = {4'b0000, msg_r[31:30]};
    assign label0_flat[(1*6)+:6]  = {4'b0000, msg_r[29:28]};
    assign label0_flat[(2*6)+:6]  = {4'b0000, msg_r[27:26]};
    assign label0_flat[(3*6)+:6]  = {5'b00000, msg_r[25]};
    assign label0_flat[(4*6)+:6]  = {4'b0000, msg_r[24:23]};
    assign label0_flat[(5*6)+:6]  = {5'b00000, msg_r[22]};
    assign label0_flat[(6*6)+:6]  = {5'b00000, msg_r[21]};
    assign label0_flat[(7*6)+:6]  = {5'b00000, msg_r[20]};
    assign label0_flat[(8*6)+:6]  = {4'b0000, msg_r[19:18]};
    assign label0_flat[(9*6)+:6]  = {5'b00000, msg_r[17]};
    assign label0_flat[(10*6)+:6] = {5'b00000, msg_r[16]};
    assign label0_flat[(11*6)+:6] = {5'b00000, msg_r[15]};
    assign label0_flat[(12*6)+:6] = {5'b00000, msg_r[14]};
    assign label0_flat[(13*6)+:6] = {5'b00000, msg_r[13]};
    assign label0_flat[(14*6)+:6] = {5'b00000, msg_r[12]};
    assign label0_flat[(15*6)+:6] = 6'b000000;
    assign label0_flat[(16*6)+:6] = {4'b0000, msg_r[11:10]};
    assign label0_flat[(17*6)+:6] = {5'b00000, msg_r[9]};
    assign label0_flat[(18*6)+:6] = {5'b00000, msg_r[8]};
    assign label0_flat[(19*6)+:6] = {5'b00000, msg_r[7]};
    assign label0_flat[(20*6)+:6] = {5'b00000, msg_r[6]};
    assign label0_flat[(21*6)+:6] = {5'b00000, msg_r[5]};
    assign label0_flat[(22*6)+:6] = {5'b00000, msg_r[4]};
    assign label0_flat[(23*6)+:6] = 6'b000000;
    assign label0_flat[(24*6)+:6] = {5'b00000, msg_r[3]};
    assign label0_flat[(25*6)+:6] = {5'b00000, msg_r[2]};
    assign label0_flat[(26*6)+:6] = {5'b00000, msg_r[1]};
    assign label0_flat[(27*6)+:6] = 6'b000000;
    assign label0_flat[(28*6)+:6] = {5'b00000, msg_r[0]};
    assign label0_flat[(29*6)+:6] = 6'b000000;
    assign label0_flat[(30*6)+:6] = 6'b000000;
    assign label0_flat[(31*6)+:6] = 6'b000000;

    scloud_bw32_phi_stage6 #(.STAGE_COMPLEX(1)) u_stage1 (
        .label_in_flat (label0_flat),
        .label_out_flat(stage1_w)
    );

    scloud_bw32_phi_stage6 #(.STAGE_COMPLEX(2)) u_stage2 (
        .label_in_flat (label_r),
        .label_out_flat(stage2_w)
    );

    scloud_bw32_phi_stage6 #(.STAGE_COMPLEX(4)) u_stage4 (
        .label_in_flat (label_r),
        .label_out_flat(stage4_w)
    );

    scloud_bw32_phi_stage6 #(.STAGE_COMPLEX(8)) u_stage8 (
        .label_in_flat (label_r),
        .label_out_flat(stage8_w)
    );

    scloud_bw32_label_to_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_pack_q (
        .label_flat(label_r),
        .q_flat    (code_q_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            msg_r       <= 32'd0;
            label_r     <= {LABEL_WIDTH_TOTAL{1'b0}};
            code_q_flat <= {(32*Q_WIDTH){1'b0}};
            busy        <= 1'b0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        msg_r <= msg_block;
                        busy  <= 1'b1;
                        state <= ST_STAGE1;
                    end
                end
                ST_STAGE1: begin
                    label_r <= stage1_w;
                    state   <= ST_STAGE2;
                end
                ST_STAGE2: begin
                    label_r <= stage2_w;
                    state   <= ST_STAGE4;
                end
                ST_STAGE4: begin
                    label_r <= stage4_w;
                    state   <= ST_STAGE8;
                end
                ST_STAGE8: begin
                    label_r <= stage8_w;
                    state   <= ST_PACK;
                end
                ST_PACK: begin
                    code_q_flat <= code_q_w;
                    state       <= ST_DONE;
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
