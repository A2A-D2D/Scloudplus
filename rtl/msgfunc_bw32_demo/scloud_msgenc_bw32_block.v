`timescale 1ns/1ps

module scloud_bw32_phi_add_pair6
(
    input  wire [5:0] a_re,
    input  wire [5:0] a_im,
    input  wire [5:0] b_re,
    input  wire [5:0] b_im,
    output wire [5:0] y_re,
    output wire [5:0] y_im
);

    /* Arithmetic is modulo 64 by intentional Verilog bit truncation.
       These 6-bit labels are an internal fixed q=1024, tau=2 demo domain. */
    assign y_re = a_re + b_re - b_im;
    assign y_im = a_im + b_re + b_im;

endmodule

module scloud_bw32_phi_stage6
#(
    parameter STAGE_COMPLEX = 1
)
(
    input  wire [(16*12)-1:0] label_in_flat,
    output wire [(16*12)-1:0] label_out_flat
);

    genvar gi;

    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : gen_stage
            if ((gi % (2*STAGE_COMPLEX)) < STAGE_COMPLEX) begin : gen_left
                assign label_out_flat[((2*gi+0)*6)+:6] = label_in_flat[((2*gi+0)*6)+:6];
                assign label_out_flat[((2*gi+1)*6)+:6] = label_in_flat[((2*gi+1)*6)+:6];
            end else begin : gen_right
                localparam integer LEFT_IDX = gi - STAGE_COMPLEX;

                scloud_bw32_phi_add_pair6 u_phi_add (
                    .a_re(label_in_flat[((2*LEFT_IDX+0)*6)+:6]),
                    .a_im(label_in_flat[((2*LEFT_IDX+1)*6)+:6]),
                    .b_re(label_in_flat[((2*gi+0)*6)+:6]),
                    .b_im(label_in_flat[((2*gi+1)*6)+:6]),
                    .y_re(label_out_flat[((2*gi+0)*6)+:6]),
                    .y_im(label_out_flat[((2*gi+1)*6)+:6])
                );
            end
        end
    endgenerate

endmodule

module scloud_bw32_label_to_q
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [(32*6)-1:0]       label_flat,
    output wire [(32*Q_WIDTH)-1:0] q_flat
);

    localparam LABEL_WIDTH = 6;
    localparam Q_PAD       = Q_WIDTH - TAU;   // zero-padding width for q-domain LSBs

    genvar gi;

    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : gen_pack
            assign q_flat[((2*gi+0)*Q_WIDTH)+:Q_WIDTH] =
                {label_flat[((2*gi+0)*LABEL_WIDTH)+:TAU], {Q_PAD{1'b0}}};
            assign q_flat[((2*gi+1)*Q_WIDTH)+:Q_WIDTH] =
                {label_flat[((2*gi+1)*LABEL_WIDTH)+:TAU], {Q_PAD{1'b0}}};
        end
    endgenerate

endmodule

module scloud_msgenc_bw32_block
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [31:0]                msg_block,
    output wire [(32*Q_WIDTH)-1:0]    code_q_flat
);

    wire [(16*12)-1:0] label0_flat;
    wire [(16*12)-1:0] stage1_flat;
    wire [(16*12)-1:0] stage2_flat;
    wire [(16*12)-1:0] stage4_flat;
    wire [(16*12)-1:0] stage8_flat;

    /* Fixed BW32 demo parameters:
       q=1024, tau=2, Delta=q/2^tau=256.

       Coordinate label map before butterfly expansion:
       j   wH(j)  re bits       im bits
       0   0      msg[31:30]    msg[29:28]
       1   1      msg[27:26]    msg[25]
       2   1      msg[24:23]    msg[22]
       3   2      msg[21]       msg[20]
       4   1      msg[19:18]    msg[17]
       5   2      msg[16]       msg[15]
       6   2      msg[14]       msg[13]
       7   3      msg[12]       0
       8   1      msg[11:10]    msg[9]
       9   2      msg[8]        msg[7]
       10  2      msg[6]        msg[5]
       11  3      msg[4]        0
       12  2      msg[3]        msg[2]
       13  3      msg[1]        0
       14  3      msg[0]        0
       15  4      0             0

       Flat bus order is LSB-first: coord0.re, coord0.im, coord1.re, ... */
    assign label0_flat[(0*6)+:6]  = {4'b0000, msg_block[31:30]};
    assign label0_flat[(1*6)+:6]  = {4'b0000, msg_block[29:28]};
    assign label0_flat[(2*6)+:6]  = {4'b0000, msg_block[27:26]};
    assign label0_flat[(3*6)+:6]  = {5'b00000, msg_block[25]};
    assign label0_flat[(4*6)+:6]  = {4'b0000, msg_block[24:23]};
    assign label0_flat[(5*6)+:6]  = {5'b00000, msg_block[22]};
    assign label0_flat[(6*6)+:6]  = {5'b00000, msg_block[21]};
    assign label0_flat[(7*6)+:6]  = {5'b00000, msg_block[20]};
    assign label0_flat[(8*6)+:6]  = {4'b0000, msg_block[19:18]};
    assign label0_flat[(9*6)+:6]  = {5'b00000, msg_block[17]};
    assign label0_flat[(10*6)+:6] = {5'b00000, msg_block[16]};
    assign label0_flat[(11*6)+:6] = {5'b00000, msg_block[15]};
    assign label0_flat[(12*6)+:6] = {5'b00000, msg_block[14]};
    assign label0_flat[(13*6)+:6] = {5'b00000, msg_block[13]};
    assign label0_flat[(14*6)+:6] = {5'b00000, msg_block[12]};
    assign label0_flat[(15*6)+:6] = 6'b000000;
    assign label0_flat[(16*6)+:6] = {4'b0000, msg_block[11:10]};
    assign label0_flat[(17*6)+:6] = {5'b00000, msg_block[9]};
    assign label0_flat[(18*6)+:6] = {5'b00000, msg_block[8]};
    assign label0_flat[(19*6)+:6] = {5'b00000, msg_block[7]};
    assign label0_flat[(20*6)+:6] = {5'b00000, msg_block[6]};
    assign label0_flat[(21*6)+:6] = {5'b00000, msg_block[5]};
    assign label0_flat[(22*6)+:6] = {5'b00000, msg_block[4]};
    assign label0_flat[(23*6)+:6] = 6'b000000;
    assign label0_flat[(24*6)+:6] = {5'b00000, msg_block[3]};
    assign label0_flat[(25*6)+:6] = {5'b00000, msg_block[2]};
    assign label0_flat[(26*6)+:6] = {5'b00000, msg_block[1]};
    assign label0_flat[(27*6)+:6] = 6'b000000;
    assign label0_flat[(28*6)+:6] = {5'b00000, msg_block[0]};
    assign label0_flat[(29*6)+:6] = 6'b000000;
    assign label0_flat[(30*6)+:6] = 6'b000000;
    assign label0_flat[(31*6)+:6] = 6'b000000;

    scloud_bw32_phi_stage6 #(.STAGE_COMPLEX(1)) u_stage1 (
        .label_in_flat (label0_flat),
        .label_out_flat(stage1_flat)
    );

    scloud_bw32_phi_stage6 #(.STAGE_COMPLEX(2)) u_stage2 (
        .label_in_flat (stage1_flat),
        .label_out_flat(stage2_flat)
    );

    scloud_bw32_phi_stage6 #(.STAGE_COMPLEX(4)) u_stage4 (
        .label_in_flat (stage2_flat),
        .label_out_flat(stage4_flat)
    );

    scloud_bw32_phi_stage6 #(.STAGE_COMPLEX(8)) u_stage8 (
        .label_in_flat (stage4_flat),
        .label_out_flat(stage8_flat)
    );

    scloud_bw32_label_to_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_pack_q (
        .label_flat(stage8_flat),
        .q_flat    (code_q_flat)
    );

endmodule
