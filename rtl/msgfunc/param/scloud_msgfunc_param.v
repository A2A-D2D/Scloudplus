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
    parameter TAU           = 2,
    parameter LABEL_WIDTH   = 6,
    parameter MSG_WIDTH     = 32
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
    endgenerate

endmodule

module scloud_msgfunc_label_to_msg
#(
    parameter COMPLEX_N     = 16,
    parameter LOG_COMPLEX_N = 4,
    parameter TAU           = 2,
    parameter LABEL_WIDTH   = 6,
    parameter MSG_WIDTH     = 32
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

    genvar gi;

    generate
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
    endgenerate

endmodule

module scloud_msgfunc_label_to_q
#(
    parameter COMPLEX_N   = 16,
    parameter Q_WIDTH     = 10,
    parameter TAU         = 2,
    parameter LABEL_WIDTH = 6
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
    parameter Q_WIDTH     = 10,
    parameter TAU         = 2,
    parameter LABEL_WIDTH = 6
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
    parameter Q_WIDTH       = 10,
    parameter TAU           = 2,
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
    parameter Q_WIDTH       = 10,
    parameter TAU           = 2,
    parameter LABEL_WIDTH   = TAU + LOG_COMPLEX_N,
    parameter MSG_WIDTH     = (COMPLEX_N*(2*TAU)) - ((COMPLEX_N*LOG_COMPLEX_N)/2)
)
(
    input  wire [(2*COMPLEX_N*Q_WIDTH)-1:0] noisy_q_flat,
    output wire [MSG_WIDTH-1:0] msg_block,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0] rounded_q_flat
);

    wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] quant_label_flat;
    wire [(2*COMPLEX_N*LABEL_WIDTH)-1:0] raw_label_flat;

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (TAU),
        .COMPLEX_N(COMPLEX_N)
    ) u_bdd (
        .target_flat (noisy_q_flat),
        .decoded_flat(rounded_q_flat)
    );

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
    parameter Q_WIDTH       = 10,
    parameter TAU           = 2,
    parameter LABEL_WIDTH   = TAU + LOG_COMPLEX_N,
    parameter MSG_WIDTH     = (COMPLEX_N*(2*TAU)) - ((COMPLEX_N*LOG_COMPLEX_N)/2)
)
(
    input  wire [MSG_WIDTH-1:0] msg_in,
    input  wire [(2*COMPLEX_N*Q_WIDTH)-1:0] noise_q_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0] enc_q_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0] noisy_q_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0] rounded_q_flat,
    output wire [MSG_WIDTH-1:0] msg_out
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
        .noisy_q_flat  (noisy_q_flat),
        .msg_block     (msg_out),
        .rounded_q_flat(rounded_q_flat)
    );

endmodule
