`timescale 1ns/1ps

module scloud_bw32_inv_phi_pair6
(
    input  wire [5:0] a_re,
    input  wire [5:0] a_im,
    input  wire [5:0] y_re,
    input  wire [5:0] y_im,
    output wire [5:0] b_re,
    output wire [5:0] b_im
);

    wire [6:0] dr;
    wire [6:0] di;
    wire [6:0] b_re_sum;
    wire [6:0] b_im_sum;

    /* Intentional modulo-64 label arithmetic.
       The extra bit preserves the divide-by-2 carry before truncating. */
    assign dr = {y_re[5], y_re} - {a_re[5], a_re};
    assign di = {y_im[5], y_im} - {a_im[5], a_im};
    assign b_re_sum = dr + di;
    assign b_im_sum = di - dr;
    assign b_re = {b_re_sum[6], b_re_sum[6:1]};
    assign b_im = {b_im_sum[6], b_im_sum[6:1]};

endmodule

module scloud_bw32_inv_phi_stage6
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

                scloud_bw32_inv_phi_pair6 u_inv_phi (
                    .a_re(label_in_flat[((2*LEFT_IDX+0)*6)+:6]),
                    .a_im(label_in_flat[((2*LEFT_IDX+1)*6)+:6]),
                    .y_re(label_in_flat[((2*gi+0)*6)+:6]),
                    .y_im(label_in_flat[((2*gi+1)*6)+:6]),
                    .b_re(label_out_flat[((2*gi+0)*6)+:6]),
                    .b_im(label_out_flat[((2*gi+1)*6)+:6])
                );
            end
        end
    endgenerate

endmodule

module scloud_bw32_q_to_label
(
    input  wire [319:0]       q_flat,
    output wire [(16*12)-1:0] label_flat
);

    genvar gi;

    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : gen_unpack
            assign label_flat[((2*gi+0)*6)+:6] = {4'b0000, q_flat[((2*gi+0)*10)+8+:2]};
            assign label_flat[((2*gi+1)*6)+:6] = {4'b0000, q_flat[((2*gi+1)*10)+8+:2]};
        end
    endgenerate

endmodule

module scloud_bw32_delabel_tau2
#(
    parameter WH = 0
)
(
    input  wire [5:0] raw_re,
    input  wire [5:0] raw_im,
    output wire [1:0] re_bits,
    output wire [1:0] im_bits
);

    wire [5:0] b_prime;
    wire [5:0] a_adj;

    /* Fixed tau=2 DelabelingReduce.
       WH is the Hamming weight of the coordinate index j. */
    assign b_prime = (WH == 0) ? {4'b0000, raw_im[1:0]} :
                     (WH == 1) ? {5'b00000, raw_im[0]} :
                     (WH == 2) ? {5'b00000, raw_im[0]} :
                                 6'b000000;

    assign a_adj = raw_re - raw_im + b_prime;

    assign re_bits = (WH == 0) ? a_adj[1:0] :
                     (WH == 1) ? a_adj[1:0] :
                     (WH == 2) ? {1'b0, a_adj[0]} :
                                 {1'b0, a_adj[0]};

    assign im_bits = (WH == 0) ? raw_im[1:0] :
                     (WH == 1) ? {1'b0, raw_im[0]} :
                     (WH == 2) ? {1'b0, raw_im[0]} :
                                 2'b00;

endmodule

module scloud_msgdec_bw32_block
(
    input  wire [319:0] noisy_q_flat,
    output wire [31:0]  msg_block,
    output wire [319:0] rounded_q_flat
);

    wire [(16*12)-1:0] quant_label_flat;
    wire [(16*12)-1:0] stage8_flat;
    wire [(16*12)-1:0] stage4_flat;
    wire [(16*12)-1:0] stage2_flat;
    wire [(16*12)-1:0] raw_label_flat;

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

    /* BDD returns the nearest BW32 q-domain codeword.
       rounded_q_flat uses the same LSB-first coordinate order as enc_q_flat. */
    scloud_bdd_recursive #(
        .Q_WIDTH  (10),
        .TAU      (2),
        .COMPLEX_N(16)
    ) u_bdd (
        .target_flat (noisy_q_flat),
        .decoded_flat(rounded_q_flat)
    );

    scloud_bw32_q_to_label u_unpack_q (
        .q_flat    (rounded_q_flat),
        .label_flat(quant_label_flat)
    );

    scloud_bw32_inv_phi_stage6 #(.STAGE_COMPLEX(8)) u_inv_stage8 (
        .label_in_flat (quant_label_flat),
        .label_out_flat(stage8_flat)
    );

    scloud_bw32_inv_phi_stage6 #(.STAGE_COMPLEX(4)) u_inv_stage4 (
        .label_in_flat (stage8_flat),
        .label_out_flat(stage4_flat)
    );

    scloud_bw32_inv_phi_stage6 #(.STAGE_COMPLEX(2)) u_inv_stage2 (
        .label_in_flat (stage4_flat),
        .label_out_flat(stage2_flat)
    );

    scloud_bw32_inv_phi_stage6 #(.STAGE_COMPLEX(1)) u_inv_stage1 (
        .label_in_flat (stage2_flat),
        .label_out_flat(raw_label_flat)
    );

    scloud_bw32_delabel_tau2 #(.WH(0)) u_delabel_0  (.raw_re(raw_label_flat[(0*6)+:6]),  .raw_im(raw_label_flat[(1*6)+:6]),  .re_bits(r0_bits),  .im_bits(i0_bits));
    scloud_bw32_delabel_tau2 #(.WH(1)) u_delabel_1  (.raw_re(raw_label_flat[(2*6)+:6]),  .raw_im(raw_label_flat[(3*6)+:6]),  .re_bits(r1_bits),  .im_bits(i1_bits));
    scloud_bw32_delabel_tau2 #(.WH(1)) u_delabel_2  (.raw_re(raw_label_flat[(4*6)+:6]),  .raw_im(raw_label_flat[(5*6)+:6]),  .re_bits(r2_bits),  .im_bits(i2_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_3  (.raw_re(raw_label_flat[(6*6)+:6]),  .raw_im(raw_label_flat[(7*6)+:6]),  .re_bits(r3_bits),  .im_bits(i3_bits));
    scloud_bw32_delabel_tau2 #(.WH(1)) u_delabel_4  (.raw_re(raw_label_flat[(8*6)+:6]),  .raw_im(raw_label_flat[(9*6)+:6]),  .re_bits(r4_bits),  .im_bits(i4_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_5  (.raw_re(raw_label_flat[(10*6)+:6]), .raw_im(raw_label_flat[(11*6)+:6]), .re_bits(r5_bits),  .im_bits(i5_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_6  (.raw_re(raw_label_flat[(12*6)+:6]), .raw_im(raw_label_flat[(13*6)+:6]), .re_bits(r6_bits),  .im_bits(i6_bits));
    scloud_bw32_delabel_tau2 #(.WH(3)) u_delabel_7  (.raw_re(raw_label_flat[(14*6)+:6]), .raw_im(raw_label_flat[(15*6)+:6]), .re_bits(r7_bits),  .im_bits(i7_bits));
    scloud_bw32_delabel_tau2 #(.WH(1)) u_delabel_8  (.raw_re(raw_label_flat[(16*6)+:6]), .raw_im(raw_label_flat[(17*6)+:6]), .re_bits(r8_bits),  .im_bits(i8_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_9  (.raw_re(raw_label_flat[(18*6)+:6]), .raw_im(raw_label_flat[(19*6)+:6]), .re_bits(r9_bits),  .im_bits(i9_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_10 (.raw_re(raw_label_flat[(20*6)+:6]), .raw_im(raw_label_flat[(21*6)+:6]), .re_bits(r10_bits), .im_bits(i10_bits));
    scloud_bw32_delabel_tau2 #(.WH(3)) u_delabel_11 (.raw_re(raw_label_flat[(22*6)+:6]), .raw_im(raw_label_flat[(23*6)+:6]), .re_bits(r11_bits), .im_bits(i11_bits));
    scloud_bw32_delabel_tau2 #(.WH(2)) u_delabel_12 (.raw_re(raw_label_flat[(24*6)+:6]), .raw_im(raw_label_flat[(25*6)+:6]), .re_bits(r12_bits), .im_bits(i12_bits));
    scloud_bw32_delabel_tau2 #(.WH(3)) u_delabel_13 (.raw_re(raw_label_flat[(26*6)+:6]), .raw_im(raw_label_flat[(27*6)+:6]), .re_bits(r13_bits), .im_bits(i13_bits));
    scloud_bw32_delabel_tau2 #(.WH(3)) u_delabel_14 (.raw_re(raw_label_flat[(28*6)+:6]), .raw_im(raw_label_flat[(29*6)+:6]), .re_bits(r14_bits), .im_bits(i14_bits));
    scloud_bw32_delabel_tau2 #(.WH(4)) u_delabel_15 (.raw_re(raw_label_flat[(30*6)+:6]), .raw_im(raw_label_flat[(31*6)+:6]), .re_bits(r15_bits), .im_bits(i15_bits));

    assign msg_block = {
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

endmodule
