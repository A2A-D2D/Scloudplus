`timescale 1ns/1ps

module scloud_msgfunc_phi_add_pair
#(
    parameter LABEL_WIDTH = 6
)
(
    input  wire [LABEL_WIDTH-1:0] a_re,
    input  wire [LABEL_WIDTH-1:0] a_im,
    input  wire [LABEL_WIDTH-1:0] b_re,
    input  wire [LABEL_WIDTH-1:0] b_im,
    output wire [LABEL_WIDTH-1:0] y_re,
    output wire [LABEL_WIDTH-1:0] y_im
);

    assign y_re = a_re + b_re - b_im;
    assign y_im = a_im + b_re + b_im;

endmodule

module scloud_msgfunc_inv_phi_pair
#(
    parameter LABEL_WIDTH = 6
)
(
    input  wire [LABEL_WIDTH-1:0] a_re,
    input  wire [LABEL_WIDTH-1:0] a_im,
    input  wire [LABEL_WIDTH-1:0] y_re,
    input  wire [LABEL_WIDTH-1:0] y_im,
    output wire [LABEL_WIDTH-1:0] b_re,
    output wire [LABEL_WIDTH-1:0] b_im
);

    wire [LABEL_WIDTH:0] dr;
    wire [LABEL_WIDTH:0] di;
    wire [LABEL_WIDTH:0] b_re_sum;
    wire [LABEL_WIDTH:0] b_im_sum;

    assign dr = {y_re[LABEL_WIDTH-1], y_re} - {a_re[LABEL_WIDTH-1], a_re};
    assign di = {y_im[LABEL_WIDTH-1], y_im} - {a_im[LABEL_WIDTH-1], a_im};
    assign b_re_sum = dr + di;
    assign b_im_sum = di - dr;
    assign b_re = {b_re_sum[LABEL_WIDTH], b_re_sum[LABEL_WIDTH:1]};
    assign b_im = {b_im_sum[LABEL_WIDTH], b_im_sum[LABEL_WIDTH:1]};

endmodule

module scloud_msgfunc_phi_encode
#(
    parameter COMPLEX_N   = 16,
    parameter LABEL_WIDTH = 6
)
(
    input  wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] label_in_flat,
    output wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] label_out_flat
);

    localparam HALF_COMPLEX = COMPLEX_N / 2;
    localparam HALF_WIDTH   = 2 * HALF_COMPLEX * LABEL_WIDTH;

    genvar gi;

    generate
        if (COMPLEX_N == 1) begin : gen_leaf
            assign label_out_flat = label_in_flat;
        end else begin : gen_node
            wire [HALF_WIDTH-1:0] left_in;
            wire [HALF_WIDTH-1:0] right_in;
            wire [HALF_WIDTH-1:0] left_enc;
            wire [HALF_WIDTH-1:0] right_enc;

            assign left_in  = label_in_flat[0+:HALF_WIDTH];
            assign right_in = label_in_flat[HALF_WIDTH+:HALF_WIDTH];

            scloud_msgfunc_phi_encode #(
                .COMPLEX_N  (HALF_COMPLEX),
                .LABEL_WIDTH(LABEL_WIDTH)
            ) u_left (
                .label_in_flat (left_in),
                .label_out_flat(left_enc)
            );

            scloud_msgfunc_phi_encode #(
                .COMPLEX_N  (HALF_COMPLEX),
                .LABEL_WIDTH(LABEL_WIDTH)
            ) u_right (
                .label_in_flat (right_in),
                .label_out_flat(right_enc)
            );

            assign label_out_flat[0+:HALF_WIDTH] = left_enc;

            for (gi = 0; gi < HALF_COMPLEX; gi = gi + 1) begin : gen_phi_add
                scloud_msgfunc_phi_add_pair #(.LABEL_WIDTH(LABEL_WIDTH)) u_pair (
                    .a_re(left_enc[((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .a_im(left_enc[((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .b_re(right_enc[((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .b_im(right_enc[((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .y_re(label_out_flat[HALF_WIDTH+((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .y_im(label_out_flat[HALF_WIDTH+((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH])
                );
            end
        end
    endgenerate

endmodule

module scloud_msgfunc_phi_decode
#(
    parameter COMPLEX_N   = 16,
    parameter LABEL_WIDTH = 6
)
(
    input  wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] label_in_flat,
    output wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] label_out_flat
);

    localparam HALF_COMPLEX = COMPLEX_N / 2;
    localparam HALF_WIDTH   = 2 * HALF_COMPLEX * LABEL_WIDTH;

    genvar gi;

    generate
        if (COMPLEX_N == 1) begin : gen_leaf
            assign label_out_flat = label_in_flat;
        end else begin : gen_node
            wire [HALF_WIDTH-1:0] left_enc;
            wire [HALF_WIDTH-1:0] right_enc;
            wire [HALF_WIDTH-1:0] right_phi_inv;

            assign left_enc  = label_in_flat[0+:HALF_WIDTH];
            assign right_enc = label_in_flat[HALF_WIDTH+:HALF_WIDTH];

            for (gi = 0; gi < HALF_COMPLEX; gi = gi + 1) begin : gen_inv_phi
                scloud_msgfunc_inv_phi_pair #(.LABEL_WIDTH(LABEL_WIDTH)) u_pair (
                    .a_re(left_enc[((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .a_im(left_enc[((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .y_re(right_enc[((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .y_im(right_enc[((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .b_re(right_phi_inv[((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH]),
                    .b_im(right_phi_inv[((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH])
                );
            end

            scloud_msgfunc_phi_decode #(
                .COMPLEX_N  (HALF_COMPLEX),
                .LABEL_WIDTH(LABEL_WIDTH)
            ) u_left (
                .label_in_flat (left_enc),
                .label_out_flat(label_out_flat[0+:HALF_WIDTH])
            );

            scloud_msgfunc_phi_decode #(
                .COMPLEX_N  (HALF_COMPLEX),
                .LABEL_WIDTH(LABEL_WIDTH)
            ) u_right (
                .label_in_flat (right_phi_inv),
                .label_out_flat(label_out_flat[HALF_WIDTH+:HALF_WIDTH])
            );
        end
    endgenerate

endmodule

module scloud_msgfunc_msg_to_label
#(
    parameter COMPLEX_N     = 16,
    parameter LOG_COMPLEX_N = 4,
    parameter TAU           = 3,
    parameter LABEL_WIDTH   = TAU + LOG_COMPLEX_N,
    parameter MSG_WIDTH     = (COMPLEX_N*(2*TAU)) - ((COMPLEX_N*LOG_COMPLEX_N)/2)
)
(
    input  wire [MSG_WIDTH-1:0] msg_in,
    output wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] label_flat
);

    function integer popcount_idx;
        input integer value;
        integer tmp;
        integer count;
        begin
            tmp = value;
            count = 0;
            while (tmp != 0) begin
                count = count + (tmp % 2);
                tmp = tmp / 2;
            end
            popcount_idx = count;
        end
    endfunction

    function integer coord_re_bits;
        input integer wh;
        integer sub_val;
        begin
            sub_val = wh / 2;
            coord_re_bits = (TAU > sub_val) ? (TAU - sub_val) : 0;
        end
    endfunction

    function integer coord_im_bits;
        input integer wh;
        integer sub_val;
        begin
            sub_val = (wh + 1) / 2;
            coord_im_bits = (TAU > sub_val) ? (TAU - sub_val) : 0;
        end
    endfunction

    function integer coord_offset;
        input integer coord_idx;
        integer oi;
        integer sum;
        integer wh;
        begin
            sum = 0;
            for (oi = 0; oi < coord_idx; oi = oi + 1) begin
                wh = popcount_idx(oi);
                sum = sum + coord_re_bits(wh) + coord_im_bits(wh);
            end
            coord_offset = sum;
        end
    endfunction

    genvar gi;

    generate
        if ((COMPLEX_N == 16) && (LOG_COMPLEX_N == 4) && (TAU == 3)) begin : gen_c_tau3
            wire [7:0] m0; wire [7:0] m1; wire [7:0] m2; wire [7:0] m3;
            wire [7:0] m4; wire [7:0] m5; wire [7:0] m6; wire [7:0] m7;

            assign m0 = msg_in[63 -: 8];
            assign m1 = msg_in[55 -: 8];
            assign m2 = msg_in[47 -: 8];
            assign m3 = msg_in[39 -: 8];
            assign m4 = msg_in[31 -: 8];
            assign m5 = msg_in[23 -: 8];
            assign m6 = msg_in[15 -: 8];
            assign m7 = msg_in[7  -: 8];

            assign label_flat[(0*LABEL_WIDTH)+:LABEL_WIDTH]  = m0[2:0];
            assign label_flat[(1*LABEL_WIDTH)+:LABEL_WIDTH]  = m0[5:3];
            assign label_flat[(2*LABEL_WIDTH)+:LABEL_WIDTH]  = {m1[0], m0[7:6]};
            assign label_flat[(3*LABEL_WIDTH)+:LABEL_WIDTH]  = m2[3:2];
            assign label_flat[(4*LABEL_WIDTH)+:LABEL_WIDTH]  = m1[3:1];
            assign label_flat[(5*LABEL_WIDTH)+:LABEL_WIDTH]  = m2[5:4];
            assign label_flat[(6*LABEL_WIDTH)+:LABEL_WIDTH]  = m2[7:6];
            assign label_flat[(7*LABEL_WIDTH)+:LABEL_WIDTH]  = m3[1:0];
            assign label_flat[(8*LABEL_WIDTH)+:LABEL_WIDTH]  = m1[6:4];
            assign label_flat[(9*LABEL_WIDTH)+:LABEL_WIDTH]  = m3[3:2];
            assign label_flat[(10*LABEL_WIDTH)+:LABEL_WIDTH] = m3[5:4];
            assign label_flat[(11*LABEL_WIDTH)+:LABEL_WIDTH] = m3[7:6];
            assign label_flat[(12*LABEL_WIDTH)+:LABEL_WIDTH] = m4[1:0];
            assign label_flat[(13*LABEL_WIDTH)+:LABEL_WIDTH] = m4[3:2];
            assign label_flat[(14*LABEL_WIDTH)+:LABEL_WIDTH] = m4[5:4];
            assign label_flat[(15*LABEL_WIDTH)+:LABEL_WIDTH] = m7[2];
            assign label_flat[(16*LABEL_WIDTH)+:LABEL_WIDTH] = {m2[1:0], m1[7]};
            assign label_flat[(17*LABEL_WIDTH)+:LABEL_WIDTH] = m4[7:6];
            assign label_flat[(18*LABEL_WIDTH)+:LABEL_WIDTH] = m5[1:0];
            assign label_flat[(19*LABEL_WIDTH)+:LABEL_WIDTH] = m5[3:2];
            assign label_flat[(20*LABEL_WIDTH)+:LABEL_WIDTH] = m5[5:4];
            assign label_flat[(21*LABEL_WIDTH)+:LABEL_WIDTH] = m5[7:6];
            assign label_flat[(22*LABEL_WIDTH)+:LABEL_WIDTH] = m6[1:0];
            assign label_flat[(23*LABEL_WIDTH)+:LABEL_WIDTH] = m7[3];
            assign label_flat[(24*LABEL_WIDTH)+:LABEL_WIDTH] = m6[3:2];
            assign label_flat[(25*LABEL_WIDTH)+:LABEL_WIDTH] = m6[5:4];
            assign label_flat[(26*LABEL_WIDTH)+:LABEL_WIDTH] = m6[7:6];
            assign label_flat[(27*LABEL_WIDTH)+:LABEL_WIDTH] = m7[4];
            assign label_flat[(28*LABEL_WIDTH)+:LABEL_WIDTH] = m7[1:0];
            assign label_flat[(29*LABEL_WIDTH)+:LABEL_WIDTH] = m7[5];
            assign label_flat[(30*LABEL_WIDTH)+:LABEL_WIDTH] = m7[6];
            assign label_flat[(31*LABEL_WIDTH)+:LABEL_WIDTH] = m7[7];
        end else if ((COMPLEX_N == 16) && (LOG_COMPLEX_N == 4) && (TAU == 4)) begin : gen_c_tau4
            wire [7:0] m0;  wire [7:0] m1;  wire [7:0] m2;  wire [7:0] m3;
            wire [7:0] m4;  wire [7:0] m5;  wire [7:0] m6;  wire [7:0] m7;
            wire [7:0] m8;  wire [7:0] m9;  wire [7:0] m10; wire [7:0] m11;

            assign m0  = msg_in[95 -: 8];
            assign m1  = msg_in[87 -: 8];
            assign m2  = msg_in[79 -: 8];
            assign m3  = msg_in[71 -: 8];
            assign m4  = msg_in[63 -: 8];
            assign m5  = msg_in[55 -: 8];
            assign m6  = msg_in[47 -: 8];
            assign m7  = msg_in[39 -: 8];
            assign m8  = msg_in[31 -: 8];
            assign m9  = msg_in[23 -: 8];
            assign m10 = msg_in[15 -: 8];
            assign m11 = msg_in[7  -: 8];

            assign label_flat[(0*LABEL_WIDTH)+:LABEL_WIDTH]  = m0[3:0];
            assign label_flat[(1*LABEL_WIDTH)+:LABEL_WIDTH]  = m0[7:4];
            assign label_flat[(2*LABEL_WIDTH)+:LABEL_WIDTH]  = m1[3:0];
            assign label_flat[(3*LABEL_WIDTH)+:LABEL_WIDTH]  = m3[2:0];
            assign label_flat[(4*LABEL_WIDTH)+:LABEL_WIDTH]  = m1[7:4];
            assign label_flat[(5*LABEL_WIDTH)+:LABEL_WIDTH]  = m3[5:3];
            assign label_flat[(6*LABEL_WIDTH)+:LABEL_WIDTH]  = {m4[0], m3[7:6]};
            assign label_flat[(7*LABEL_WIDTH)+:LABEL_WIDTH]  = m4[3:1];
            assign label_flat[(8*LABEL_WIDTH)+:LABEL_WIDTH]  = m2[3:0];
            assign label_flat[(9*LABEL_WIDTH)+:LABEL_WIDTH]  = m4[6:4];
            assign label_flat[(10*LABEL_WIDTH)+:LABEL_WIDTH] = {m5[1:0], m4[7]};
            assign label_flat[(11*LABEL_WIDTH)+:LABEL_WIDTH] = m5[4:2];
            assign label_flat[(12*LABEL_WIDTH)+:LABEL_WIDTH] = m5[7:5];
            assign label_flat[(13*LABEL_WIDTH)+:LABEL_WIDTH] = m6[2:0];
            assign label_flat[(14*LABEL_WIDTH)+:LABEL_WIDTH] = m6[5:3];
            assign label_flat[(15*LABEL_WIDTH)+:LABEL_WIDTH] = m10[5:4];
            assign label_flat[(16*LABEL_WIDTH)+:LABEL_WIDTH] = m2[7:4];
            assign label_flat[(17*LABEL_WIDTH)+:LABEL_WIDTH] = {m7[0], m6[7:6]};
            assign label_flat[(18*LABEL_WIDTH)+:LABEL_WIDTH] = m7[3:1];
            assign label_flat[(19*LABEL_WIDTH)+:LABEL_WIDTH] = m7[6:4];
            assign label_flat[(20*LABEL_WIDTH)+:LABEL_WIDTH] = {m8[1:0], m7[7]};
            assign label_flat[(21*LABEL_WIDTH)+:LABEL_WIDTH] = m8[4:2];
            assign label_flat[(22*LABEL_WIDTH)+:LABEL_WIDTH] = m8[7:5];
            assign label_flat[(23*LABEL_WIDTH)+:LABEL_WIDTH] = m10[7:6];
            assign label_flat[(24*LABEL_WIDTH)+:LABEL_WIDTH] = m9[2:0];
            assign label_flat[(25*LABEL_WIDTH)+:LABEL_WIDTH] = m9[5:3];
            assign label_flat[(26*LABEL_WIDTH)+:LABEL_WIDTH] = {m10[0], m9[7:6]};
            assign label_flat[(27*LABEL_WIDTH)+:LABEL_WIDTH] = m11[1:0];
            assign label_flat[(28*LABEL_WIDTH)+:LABEL_WIDTH] = m10[3:1];
            assign label_flat[(29*LABEL_WIDTH)+:LABEL_WIDTH] = m11[3:2];
            assign label_flat[(30*LABEL_WIDTH)+:LABEL_WIDTH] = m11[5:4];
            assign label_flat[(31*LABEL_WIDTH)+:LABEL_WIDTH] = m11[7:6];
        end else begin : gen_generic
            for (gi = 0; gi < COMPLEX_N; gi = gi + 1) begin : gen_unpack_msg
                localparam integer WH      = popcount_idx(gi);
                localparam integer RE_BITS = coord_re_bits(WH);
                localparam integer IM_BITS = coord_im_bits(WH);
                localparam integer RE_OFF  = coord_offset(gi);
                localparam integer IM_OFF  = RE_OFF + RE_BITS;

                if (RE_BITS == 0) begin : gen_re_zero
                    assign label_flat[((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH] = {LABEL_WIDTH{1'b0}};
                end else begin : gen_re_bits
                    assign label_flat[((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH] =
                        {{(LABEL_WIDTH-RE_BITS){1'b0}}, msg_in[(MSG_WIDTH-RE_OFF-1)-:RE_BITS]};
                end

                if (IM_BITS == 0) begin : gen_im_zero
                    assign label_flat[((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH] = {LABEL_WIDTH{1'b0}};
                end else begin : gen_im_bits
                    assign label_flat[((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH] =
                        {{(LABEL_WIDTH-IM_BITS){1'b0}}, msg_in[(MSG_WIDTH-IM_OFF-1)-:IM_BITS]};
                end
            end
        end
    endgenerate

endmodule

`define SCLOUD_RL4(i) reduced_label_flat[((i)*LABEL_WIDTH)+:4]
`define SCLOUD_RL3(i) reduced_label_flat[((i)*LABEL_WIDTH)+:3]
`define SCLOUD_RL2(i) reduced_label_flat[((i)*LABEL_WIDTH)+:2]
`define SCLOUD_RB0(i) reduced_label_flat[((i)*LABEL_WIDTH)]
`define SCLOUD_RB2(i) reduced_label_flat[((i)*LABEL_WIDTH)+2]
`define SCLOUD_R21(i) reduced_label_flat[((i)*LABEL_WIDTH)+1+:2]

module scloud_msgfunc_label_to_msg
#(
    parameter COMPLEX_N     = 16,
    parameter LOG_COMPLEX_N = 4,
    parameter TAU           = 3,
    parameter LABEL_WIDTH   = TAU + LOG_COMPLEX_N,
    parameter MSG_WIDTH     = (COMPLEX_N*(2*TAU)) - ((COMPLEX_N*LOG_COMPLEX_N)/2)
)
(
    input  wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] label_flat,
    output wire [MSG_WIDTH-1:0] msg_out
);

    function integer popcount_idx;
        input integer value;
        integer tmp;
        integer count;
        begin
            tmp = value;
            count = 0;
            while (tmp != 0) begin
                count = count + (tmp % 2);
                tmp = tmp / 2;
            end
            popcount_idx = count;
        end
    endfunction

    function integer coord_re_bits;
        input integer wh;
        integer sub_val;
        begin
            sub_val = wh / 2;
            coord_re_bits = (TAU > sub_val) ? (TAU - sub_val) : 0;
        end
    endfunction

    function integer coord_im_bits;
        input integer wh;
        integer sub_val;
        begin
            sub_val = (wh + 1) / 2;
            coord_im_bits = (TAU > sub_val) ? (TAU - sub_val) : 0;
        end
    endfunction

    function integer coord_offset;
        input integer coord_idx;
        integer oi;
        integer sum;
        integer wh;
        begin
            sum = 0;
            for (oi = 0; oi < coord_idx; oi = oi + 1) begin
                wh = popcount_idx(oi);
                sum = sum + coord_re_bits(wh) + coord_im_bits(wh);
            end
            coord_offset = sum;
        end
    endfunction

    wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] reduced_label_flat;
    genvar rgi;

    generate
        for (rgi = 0; rgi < COMPLEX_N; rgi = rgi + 1) begin : gen_reduce_label
            localparam integer WH      = popcount_idx(rgi);
            localparam integer RE_BITS = coord_re_bits(WH);
            localparam integer IM_BITS = coord_im_bits(WH);

            wire [LABEL_WIDTH-1:0] raw_re;
            wire [LABEL_WIDTH-1:0] raw_im;
            wire [LABEL_WIDTH-1:0] b_prime;
            wire [LABEL_WIDTH-1:0] a_adj;

            assign raw_re = label_flat[((2*rgi+0)*LABEL_WIDTH)+:LABEL_WIDTH];
            assign raw_im = label_flat[((2*rgi+1)*LABEL_WIDTH)+:LABEL_WIDTH];

            if (IM_BITS == 0) begin : gen_b_zero
                assign b_prime = {LABEL_WIDTH{1'b0}};
            end else begin : gen_b_bits
                assign b_prime = {{(LABEL_WIDTH-IM_BITS){1'b0}}, raw_im[IM_BITS-1:0]};
            end

            assign a_adj = raw_re - raw_im + b_prime;

            if (RE_BITS == 0) begin : gen_re_zero
                assign reduced_label_flat[((2*rgi+0)*LABEL_WIDTH)+:LABEL_WIDTH] = {LABEL_WIDTH{1'b0}};
            end else begin : gen_re_bits
                assign reduced_label_flat[((2*rgi+0)*LABEL_WIDTH)+:LABEL_WIDTH] =
                    {{(LABEL_WIDTH-RE_BITS){1'b0}}, a_adj[RE_BITS-1:0]};
            end

            assign reduced_label_flat[((2*rgi+1)*LABEL_WIDTH)+:LABEL_WIDTH] = b_prime;
        end
    endgenerate

    function [3:0] label_low4;
        input integer lane_idx;
        begin
            label_low4 = reduced_label_flat[(lane_idx*LABEL_WIDTH)+:4];
        end
    endfunction

    function [2:0] label_low3;
        input integer lane_idx;
        begin
            label_low3 = reduced_label_flat[(lane_idx*LABEL_WIDTH)+:3];
        end
    endfunction

    function [1:0] label_low2;
        input integer lane_idx;
        begin
            label_low2 = reduced_label_flat[(lane_idx*LABEL_WIDTH)+:2];
        end
    endfunction

    function [1:0] label_bits2_1;
        input integer lane_idx;
        begin
            label_bits2_1 = reduced_label_flat[(lane_idx*LABEL_WIDTH)+1+:2];
        end
    endfunction

    function label_bit0;
        input integer lane_idx;
        begin
            label_bit0 = reduced_label_flat[lane_idx*LABEL_WIDTH];
        end
    endfunction

    function label_bit2;
        input integer lane_idx;
        begin
            label_bit2 = reduced_label_flat[(lane_idx*LABEL_WIDTH)+2];
        end
    endfunction

    genvar gi;

    generate
        if ((COMPLEX_N == 16) && (LOG_COMPLEX_N == 4) && (TAU == 3)) begin : gen_c_tau3
            assign msg_out[63 -: 8] = {`SCLOUD_RL2(2), `SCLOUD_RL3(1), `SCLOUD_RL3(0)};
            assign msg_out[55 -: 8] = {`SCLOUD_RB0(16), `SCLOUD_RL3(8),
                                       `SCLOUD_RL3(4), `SCLOUD_RB2(2)};
            assign msg_out[47 -: 8] = {`SCLOUD_RL2(6), `SCLOUD_RL2(5),
                                       `SCLOUD_RL2(3), `SCLOUD_R21(16)};
            assign msg_out[39 -: 8] = {`SCLOUD_RL2(11), `SCLOUD_RL2(10),
                                       `SCLOUD_RL2(9), `SCLOUD_RL2(7)};
            assign msg_out[31 -: 8] = {`SCLOUD_RL2(17), `SCLOUD_RL2(14),
                                       `SCLOUD_RL2(13), `SCLOUD_RL2(12)};
            assign msg_out[23 -: 8] = {`SCLOUD_RL2(21), `SCLOUD_RL2(20),
                                       `SCLOUD_RL2(19), `SCLOUD_RL2(18)};
            assign msg_out[15 -: 8] = {`SCLOUD_RL2(26), `SCLOUD_RL2(25),
                                       `SCLOUD_RL2(24), `SCLOUD_RL2(22)};
            assign msg_out[7 -: 8]  = {`SCLOUD_RB0(31), `SCLOUD_RB0(30),
                                       `SCLOUD_RB0(29), `SCLOUD_RB0(27),
                                       `SCLOUD_RB0(23), `SCLOUD_RB0(15),
                                       `SCLOUD_RL2(28)};
        end else if ((COMPLEX_N == 16) && (LOG_COMPLEX_N == 4) && (TAU == 4)) begin : gen_c_tau4
            assign msg_out[95 -: 8] = {`SCLOUD_RL4(1), `SCLOUD_RL4(0)};
            assign msg_out[87 -: 8] = {`SCLOUD_RL4(4), `SCLOUD_RL4(2)};
            assign msg_out[79 -: 8] = {`SCLOUD_RL4(16), `SCLOUD_RL4(8)};
            assign msg_out[71 -: 8] = {`SCLOUD_RL2(6), `SCLOUD_RL3(5), `SCLOUD_RL3(3)};
            assign msg_out[63 -: 8] = {`SCLOUD_RB0(10), `SCLOUD_RL3(9),
                                       `SCLOUD_RL3(7), `SCLOUD_RB2(6)};
            assign msg_out[55 -: 8] = {`SCLOUD_RL3(12), `SCLOUD_RL3(11), `SCLOUD_R21(10)};
            assign msg_out[47 -: 8] = {`SCLOUD_RL2(17), `SCLOUD_RL3(14), `SCLOUD_RL3(13)};
            assign msg_out[39 -: 8] = {`SCLOUD_RB0(20), `SCLOUD_RL3(19),
                                       `SCLOUD_RL3(18), `SCLOUD_RB2(17)};
            assign msg_out[31 -: 8] = {`SCLOUD_RL3(22), `SCLOUD_RL3(21), `SCLOUD_R21(20)};
            assign msg_out[23 -: 8] = {`SCLOUD_RL2(26), `SCLOUD_RL3(25), `SCLOUD_RL3(24)};
            assign msg_out[15 -: 8] = {`SCLOUD_RL2(23), `SCLOUD_RL2(15),
                                       `SCLOUD_RL3(28), `SCLOUD_RB2(26)};
            assign msg_out[7 -: 8]  = {`SCLOUD_RL2(31), `SCLOUD_RL2(30),
                                       `SCLOUD_RL2(29), `SCLOUD_RL2(27)};
        end else begin : gen_generic
            for (gi = 0; gi < COMPLEX_N; gi = gi + 1) begin : gen_pack_msg
                localparam integer WH      = popcount_idx(gi);
                localparam integer RE_BITS = coord_re_bits(WH);
                localparam integer IM_BITS = coord_im_bits(WH);
                localparam integer RE_OFF  = coord_offset(gi);
                localparam integer IM_OFF  = RE_OFF + RE_BITS;

                wire [LABEL_WIDTH-1:0] raw_re;
                wire [LABEL_WIDTH-1:0] raw_im;
                wire [LABEL_WIDTH-1:0] b_prime;
                wire [LABEL_WIDTH-1:0] a_adj;

                assign raw_re = label_flat[((2*gi+0)*LABEL_WIDTH)+:LABEL_WIDTH];
                assign raw_im = label_flat[((2*gi+1)*LABEL_WIDTH)+:LABEL_WIDTH];

                if (IM_BITS == 0) begin : gen_b_zero
                    assign b_prime = {LABEL_WIDTH{1'b0}};
                end else begin : gen_b_bits
                    assign b_prime = {{(LABEL_WIDTH-IM_BITS){1'b0}}, raw_im[IM_BITS-1:0]};
                end

                assign a_adj = raw_re - raw_im + b_prime;

                if (RE_BITS > 0) begin : gen_re_out
                    assign msg_out[(MSG_WIDTH-RE_OFF-1)-:RE_BITS] = a_adj[RE_BITS-1:0];
                end

                if (IM_BITS > 0) begin : gen_im_out
                    assign msg_out[(MSG_WIDTH-IM_OFF-1)-:IM_BITS] = raw_im[IM_BITS-1:0];
                end
            end
        end
    endgenerate

endmodule

`undef SCLOUD_RL4
`undef SCLOUD_RL3
`undef SCLOUD_RL2
`undef SCLOUD_RB0
`undef SCLOUD_RB2
`undef SCLOUD_R21

module scloud_msgfunc_label_to_q
#(
    parameter COMPLEX_N   = 16,
    parameter Q_WIDTH     = 12,
    parameter TAU         = 3,
    parameter LABEL_WIDTH = TAU + 4
)
(
    input  wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] label_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0]     q_flat
);

    genvar gi;

    generate
        for (gi = 0; gi < 2*COMPLEX_N; gi = gi + 1) begin : gen_to_q
            assign q_flat[(gi*Q_WIDTH)+:Q_WIDTH] =
                {label_flat[(gi*LABEL_WIDTH)+:TAU], {(Q_WIDTH-TAU){1'b0}}};
        end
    endgenerate

endmodule

module scloud_msgfunc_q_to_label
#(
    parameter COMPLEX_N   = 16,
    parameter Q_WIDTH     = 12,
    parameter TAU         = 3,
    parameter LABEL_WIDTH = TAU + 4
)
(
    input  wire [(2*COMPLEX_N*Q_WIDTH)-1:0]     q_flat,
    output wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] label_flat
);

    genvar gi;

    generate
        for (gi = 0; gi < 2*COMPLEX_N; gi = gi + 1) begin : gen_from_q
            assign label_flat[(gi*LABEL_WIDTH)+:LABEL_WIDTH] =
                {{(LABEL_WIDTH-TAU){1'b0}}, q_flat[(gi*Q_WIDTH)+(Q_WIDTH-TAU)+:TAU]};
        end
    endgenerate

endmodule

module scloud_msgenc_param
#(
    parameter COMPLEX_N     = 16,
    parameter LOG_COMPLEX_N = 4,
    parameter Q_WIDTH       = 12,
    parameter TAU           = 3,
    parameter LABEL_WIDTH   = TAU + LOG_COMPLEX_N,
    parameter MSG_WIDTH     = (COMPLEX_N*(2*TAU)) - ((COMPLEX_N*LOG_COMPLEX_N)/2)
)
(
    input  wire [MSG_WIDTH-1:0] msg_block,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0] code_q_flat
);

    wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] raw_label_flat;
    wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] enc_label_flat;

    scloud_msgfunc_msg_to_label #(
        .COMPLEX_N    (COMPLEX_N),
        .LOG_COMPLEX_N(LOG_COMPLEX_N),
        .TAU          (TAU),
        .LABEL_WIDTH  (LABEL_WIDTH),
        .MSG_WIDTH    (MSG_WIDTH)
    ) u_msg_to_label (
        .msg_in    (msg_block),
        .label_flat(raw_label_flat)
    );

    scloud_msgfunc_phi_encode #(
        .COMPLEX_N  (COMPLEX_N),
        .LABEL_WIDTH(LABEL_WIDTH)
    ) u_phi_encode (
        .label_in_flat (raw_label_flat),
        .label_out_flat(enc_label_flat)
    );

    scloud_msgfunc_label_to_q #(
        .COMPLEX_N  (COMPLEX_N),
        .Q_WIDTH    (Q_WIDTH),
        .TAU        (TAU),
        .LABEL_WIDTH(LABEL_WIDTH)
    ) u_label_to_q (
        .label_flat(enc_label_flat),
        .q_flat    (code_q_flat)
    );

endmodule

module scloud_msgdec_param
#(
    parameter COMPLEX_N     = 16,
    parameter LOG_COMPLEX_N = 4,
    parameter Q_WIDTH       = 12,
    parameter TAU           = 3,
    parameter LABEL_WIDTH   = TAU + LOG_COMPLEX_N,
    parameter MSG_WIDTH     = (COMPLEX_N*(2*TAU)) - ((COMPLEX_N*LOG_COMPLEX_N)/2)
)
(
    input  wire                                clk,
    input  wire                                rst_n,
    input  wire                                bdd_start,
    output wire                                bdd_start_ready,
    output wire                                bdd_done,
    input  wire [(2*COMPLEX_N*Q_WIDTH)-1:0]    noisy_q_flat,
    output wire [MSG_WIDTH-1:0]                msg_block,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0]    rounded_q_flat
);

    wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] quant_label_flat;
    wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] raw_label_flat;

    generate
        if (COMPLEX_N == 16) begin : gen_bdd32
            scloud_bdd32_seq #(
                .Q_WIDTH(Q_WIDTH),
                .TAU    (TAU)
            ) u_bdd (
                .target_flat  (noisy_q_flat),
                .clk          (clk),
                .rst_n        (rst_n),
                .start        (bdd_start),
                .start_ready  (bdd_start_ready),
                .busy         (),
                .done         (bdd_done),
                .decoded_flat (rounded_q_flat)
            );
        end else if (COMPLEX_N == 8) begin : gen_bdd16
            scloud_bdd16_seq #(
                .Q_WIDTH(Q_WIDTH),
                .TAU    (TAU)
            ) u_bdd (
                .target_flat  (noisy_q_flat),
                .clk          (clk),
                .rst_n        (rst_n),
                .start        (bdd_start),
                .start_ready  (bdd_start_ready),
                .busy         (),
                .done         (bdd_done),
                .decoded_flat (rounded_q_flat)
            );
        end else begin : gen_bdd8
            scloud_bdd8_seq #(
                .Q_WIDTH(Q_WIDTH),
                .TAU    (TAU)
            ) u_bdd (
                .target_flat  (noisy_q_flat),
                .clk          (clk),
                .rst_n        (rst_n),
                .start        (bdd_start),
                .start_ready  (bdd_start_ready),
                .busy         (),
                .done         (bdd_done),
                .decoded_flat (rounded_q_flat)
            );
        end
    endgenerate

    scloud_msgfunc_q_to_label #(
        .COMPLEX_N  (COMPLEX_N),
        .Q_WIDTH    (Q_WIDTH),
        .TAU        (TAU),
        .LABEL_WIDTH(LABEL_WIDTH)
    ) u_q_to_label (
        .q_flat    (rounded_q_flat),
        .label_flat(quant_label_flat)
    );

    scloud_msgfunc_phi_decode #(
        .COMPLEX_N  (COMPLEX_N),
        .LABEL_WIDTH(LABEL_WIDTH)
    ) u_phi_decode (
        .label_in_flat (quant_label_flat),
        .label_out_flat(raw_label_flat)
    );

    scloud_msgfunc_label_to_msg #(
        .COMPLEX_N    (COMPLEX_N),
        .LOG_COMPLEX_N(LOG_COMPLEX_N),
        .TAU          (TAU),
        .LABEL_WIDTH  (LABEL_WIDTH),
        .MSG_WIDTH    (MSG_WIDTH)
    ) u_label_to_msg (
        .label_flat(raw_label_flat),
        .msg_out   (msg_block)
    );

endmodule

module scloud_msgfunc_param
#(
    parameter COMPLEX_N     = 16,
    parameter LOG_COMPLEX_N = 4,
    parameter Q_WIDTH       = 12,
    parameter TAU           = 3,
    parameter LABEL_WIDTH   = TAU + LOG_COMPLEX_N,
    parameter MSG_WIDTH     = (COMPLEX_N*(2*TAU)) - ((COMPLEX_N*LOG_COMPLEX_N)/2)
)
(
    input  wire                                clk,
    input  wire                                rst_n,
    input  wire                                start,
    output wire                                start_ready,
    output wire                                done,
    input  wire [MSG_WIDTH-1:0]                msg_in,
    input  wire [(2*COMPLEX_N*Q_WIDTH)-1:0]    noise_q_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0]    enc_q_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0]    noisy_q_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0]    rounded_q_flat,
    output wire [MSG_WIDTH-1:0]                msg_out
);

    genvar gi;

    generate
        for (gi = 0; gi < 2*COMPLEX_N; gi = gi + 1) begin : gen_noise_add
            assign noisy_q_flat[(gi*Q_WIDTH)+:Q_WIDTH] =
                enc_q_flat[(gi*Q_WIDTH)+:Q_WIDTH] + noise_q_flat[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    scloud_msgenc_param #(
        .COMPLEX_N    (COMPLEX_N),
        .LOG_COMPLEX_N(LOG_COMPLEX_N),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (LABEL_WIDTH),
        .MSG_WIDTH    (MSG_WIDTH)
    ) u_msgenc (
        .msg_block  (msg_in),
        .code_q_flat(enc_q_flat)
    );

    scloud_msgdec_param #(
        .COMPLEX_N    (COMPLEX_N),
        .LOG_COMPLEX_N(LOG_COMPLEX_N),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (LABEL_WIDTH),
        .MSG_WIDTH    (MSG_WIDTH)
    ) u_msgdec (
        .clk             (clk),
        .rst_n           (rst_n),
        .bdd_start       (start),
        .bdd_start_ready (start_ready),
        .bdd_done        (done),
        .noisy_q_flat    (noisy_q_flat),
        .msg_block       (msg_out),
        .rounded_q_flat  (rounded_q_flat)
    );

endmodule
