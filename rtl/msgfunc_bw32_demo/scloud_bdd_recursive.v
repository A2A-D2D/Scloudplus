`timescale 1ns/1ps

module scloud_bdd_phi_mul_pair_q
#(
    parameter Q_WIDTH = 10
)
(
    input  wire [Q_WIDTH-1:0] b_re,
    input  wire [Q_WIDTH-1:0] b_im,
    output wire [Q_WIDTH-1:0] y_re,
    output wire [Q_WIDTH-1:0] y_im
);

    assign y_re = b_re - b_im;
    assign y_im = b_re + b_im;

endmodule

module scloud_bdd_inv_phi_pair_q
#(
    parameter Q_WIDTH = 10
)
(
    input  wire [Q_WIDTH-1:0] d_re,
    input  wire [Q_WIDTH-1:0] d_im,
    output wire [Q_WIDTH-1:0] b_re,
    output wire [Q_WIDTH-1:0] b_im
);

    wire [Q_WIDTH:0] d_re_ext;
    wire [Q_WIDTH:0] d_im_ext;
    wire [Q_WIDTH:0] b_re_sum;
    wire [Q_WIDTH:0] b_im_sum;

    assign d_re_ext = {d_re[Q_WIDTH-1], d_re};
    assign d_im_ext = {d_im[Q_WIDTH-1], d_im};
    assign b_re_sum = d_re_ext + d_im_ext;
    assign b_im_sum = d_im_ext - d_re_ext;
    assign b_re = b_re_sum[Q_WIDTH:1];
    assign b_im = b_im_sum[Q_WIDTH:1];

endmodule

module scloud_bdd_round_coord_q
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [Q_WIDTH-1:0] x_q,
    output wire [Q_WIDTH-1:0] y_q
);

    localparam DELTA_SHIFT = Q_WIDTH - TAU;
    localparam [Q_WIDTH-1:0] HALF_DELTA = {{(Q_WIDTH-1){1'b0}}, 1'b1} << (DELTA_SHIFT - 1);
    localparam [Q_WIDTH-1:0] ROUND_MASK = {{TAU{1'b1}}, {DELTA_SHIFT{1'b0}}};

    wire [Q_WIDTH:0] sum_ext;

    assign sum_ext = {1'b0, x_q} + {1'b0, HALF_DELTA};
    assign y_q = sum_ext[Q_WIDTH-1:0] & ROUND_MASK;

endmodule

module scloud_bdd_distance
#(
    parameter Q_WIDTH = 10,
    parameter COORDS  = 32
)
(
    input  wire [(COORDS*Q_WIDTH)-1:0] cand_flat,
    input  wire [(COORDS*Q_WIDTH)-1:0] target_flat,
    output reg  [31:0]                 dist
);

    integer idx;
    reg [Q_WIDTH-1:0] diff_q;
    reg [Q_WIDTH:0] diff_ext;
    reg [Q_WIDTH:0] abs_diff;
    reg [(2*Q_WIDTH)+1:0] sq_diff;

    always @(*) begin
        dist = 32'd0;
        for (idx = 0; idx < COORDS; idx = idx + 1) begin
            diff_q = cand_flat[(idx*Q_WIDTH)+:Q_WIDTH] - target_flat[(idx*Q_WIDTH)+:Q_WIDTH];
            diff_ext = {diff_q[Q_WIDTH-1], diff_q};
            if (diff_ext[Q_WIDTH] == 1'b1) begin
                abs_diff = (~diff_ext) + {{Q_WIDTH{1'b0}}, 1'b1};
            end else begin
                abs_diff = diff_ext;
            end
            sq_diff = abs_diff * abs_diff;
            dist = dist + sq_diff;
        end
    end

endmodule

module scloud_bdd_phi_mul_flat
#(
    parameter Q_WIDTH  = 10,
    parameter COMPLEX_N = 16
)
(
    input  wire [(2*COMPLEX_N*Q_WIDTH)-1:0] b_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0] y_flat
);

    genvar gi;
    generate
        for (gi = 0; gi < COMPLEX_N; gi = gi + 1) begin : gen_phi_mul
            scloud_bdd_phi_mul_pair_q #(.Q_WIDTH(Q_WIDTH)) u_phi_mul_pair (
                .b_re(b_flat[((2*gi+0)*Q_WIDTH)+:Q_WIDTH]),
                .b_im(b_flat[((2*gi+1)*Q_WIDTH)+:Q_WIDTH]),
                .y_re(y_flat[((2*gi+0)*Q_WIDTH)+:Q_WIDTH]),
                .y_im(y_flat[((2*gi+1)*Q_WIDTH)+:Q_WIDTH])
            );
        end
    endgenerate

endmodule

module scloud_bdd_inv_phi_flat
#(
    parameter Q_WIDTH  = 10,
    parameter COMPLEX_N = 16
)
(
    input  wire [(2*COMPLEX_N*Q_WIDTH)-1:0] d_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0] b_flat
);

    genvar gi;
    generate
        for (gi = 0; gi < COMPLEX_N; gi = gi + 1) begin : gen_inv_phi
            scloud_bdd_inv_phi_pair_q #(.Q_WIDTH(Q_WIDTH)) u_inv_phi_pair (
                .d_re(d_flat[((2*gi+0)*Q_WIDTH)+:Q_WIDTH]),
                .d_im(d_flat[((2*gi+1)*Q_WIDTH)+:Q_WIDTH]),
                .b_re(b_flat[((2*gi+0)*Q_WIDTH)+:Q_WIDTH]),
                .b_im(b_flat[((2*gi+1)*Q_WIDTH)+:Q_WIDTH])
            );
        end
    endgenerate

endmodule

module scloud_bdd_recursive
#(
    parameter Q_WIDTH   = 10,
    parameter TAU       = 2,
    parameter COMPLEX_N = 16
)
(
    input  wire [(2*COMPLEX_N*Q_WIDTH)-1:0] target_flat,
    output wire [(2*COMPLEX_N*Q_WIDTH)-1:0] decoded_flat
);

    localparam COORDS       = 2 * COMPLEX_N;
    localparam HALF_COMPLEX = COMPLEX_N / 2;
    localparam HALF_COORDS  = COORDS / 2;
    localparam HALF_WIDTH   = HALF_COORDS * Q_WIDTH;

    generate
        if (COMPLEX_N == 1) begin : gen_bdd2
            scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_re (
                .x_q(target_flat[(0*Q_WIDTH)+:Q_WIDTH]),
                .y_q(decoded_flat[(0*Q_WIDTH)+:Q_WIDTH])
            );

            scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_im (
                .x_q(target_flat[(1*Q_WIDTH)+:Q_WIDTH]),
                .y_q(decoded_flat[(1*Q_WIDTH)+:Q_WIDTH])
            );
        end else begin : gen_recursive
            wire [HALF_WIDTH-1:0] target_l;
            wire [HALF_WIDTH-1:0] target_r;
            wire [HALF_WIDTH-1:0] y_l;
            wire [HALF_WIDTH-1:0] y_r;
            wire [HALF_WIDTH-1:0] diff_a;
            wire [HALF_WIDTH-1:0] diff_b;
            wire [HALF_WIDTH-1:0] z_a_in;
            wire [HALF_WIDTH-1:0] z_b_in;
            wire [HALF_WIDTH-1:0] z_a;
            wire [HALF_WIDTH-1:0] z_b;
            wire [HALF_WIDTH-1:0] phi_z_a;
            wire [HALF_WIDTH-1:0] phi_z_b;
            wire [(COORDS*Q_WIDTH)-1:0] cand_a;
            wire [(COORDS*Q_WIDTH)-1:0] cand_b;
            wire [31:0] dist_a;
            wire [31:0] dist_b;

            genvar gj;

            assign target_l = target_flat[0+:HALF_WIDTH];
            assign target_r = target_flat[HALF_WIDTH+:HALF_WIDTH];

            scloud_bdd_recursive #(
                .Q_WIDTH  (Q_WIDTH),
                .TAU      (TAU),
                .COMPLEX_N(HALF_COMPLEX)
            ) u_bdd_left (
                .target_flat(target_l),
                .decoded_flat(y_l)
            );

            scloud_bdd_recursive #(
                .Q_WIDTH  (Q_WIDTH),
                .TAU      (TAU),
                .COMPLEX_N(HALF_COMPLEX)
            ) u_bdd_right (
                .target_flat(target_r),
                .decoded_flat(y_r)
            );

            for (gj = 0; gj < HALF_COORDS; gj = gj + 1) begin : gen_diff
                assign diff_a[(gj*Q_WIDTH)+:Q_WIDTH] = target_r[(gj*Q_WIDTH)+:Q_WIDTH] - y_l[(gj*Q_WIDTH)+:Q_WIDTH];
                assign diff_b[(gj*Q_WIDTH)+:Q_WIDTH] = target_l[(gj*Q_WIDTH)+:Q_WIDTH] - y_r[(gj*Q_WIDTH)+:Q_WIDTH];
            end

            scloud_bdd_inv_phi_flat #(
                .Q_WIDTH  (Q_WIDTH),
                .COMPLEX_N(HALF_COMPLEX)
            ) u_inv_phi_a (
                .d_flat(diff_a),
                .b_flat(z_a_in)
            );

            scloud_bdd_inv_phi_flat #(
                .Q_WIDTH  (Q_WIDTH),
                .COMPLEX_N(HALF_COMPLEX)
            ) u_inv_phi_b (
                .d_flat(diff_b),
                .b_flat(z_b_in)
            );

            scloud_bdd_recursive #(
                .Q_WIDTH  (Q_WIDTH),
                .TAU      (TAU),
                .COMPLEX_N(HALF_COMPLEX)
            ) u_bdd_za (
                .target_flat(z_a_in),
                .decoded_flat(z_a)
            );

            scloud_bdd_recursive #(
                .Q_WIDTH  (Q_WIDTH),
                .TAU      (TAU),
                .COMPLEX_N(HALF_COMPLEX)
            ) u_bdd_zb (
                .target_flat(z_b_in),
                .decoded_flat(z_b)
            );

            scloud_bdd_phi_mul_flat #(
                .Q_WIDTH  (Q_WIDTH),
                .COMPLEX_N(HALF_COMPLEX)
            ) u_phi_za (
                .b_flat(z_a),
                .y_flat(phi_z_a)
            );

            scloud_bdd_phi_mul_flat #(
                .Q_WIDTH  (Q_WIDTH),
                .COMPLEX_N(HALF_COMPLEX)
            ) u_phi_zb (
                .b_flat(z_b),
                .y_flat(phi_z_b)
            );

            assign cand_a[0+:HALF_WIDTH] = y_l;
            assign cand_b[HALF_WIDTH+:HALF_WIDTH] = y_r;

            for (gj = 0; gj < HALF_COORDS; gj = gj + 1) begin : gen_candidates
                assign cand_a[HALF_WIDTH+(gj*Q_WIDTH)+:Q_WIDTH] = y_l[(gj*Q_WIDTH)+:Q_WIDTH] + phi_z_a[(gj*Q_WIDTH)+:Q_WIDTH];
                assign cand_b[(gj*Q_WIDTH)+:Q_WIDTH] = y_r[(gj*Q_WIDTH)+:Q_WIDTH] + phi_z_b[(gj*Q_WIDTH)+:Q_WIDTH];
            end

            scloud_bdd_distance #(
                .Q_WIDTH(Q_WIDTH),
                .COORDS (COORDS)
            ) u_dist_a (
                .cand_flat  (cand_a),
                .target_flat(target_flat),
                .dist       (dist_a)
            );

            scloud_bdd_distance #(
                .Q_WIDTH(Q_WIDTH),
                .COORDS (COORDS)
            ) u_dist_b (
                .cand_flat  (cand_b),
                .target_flat(target_flat),
                .dist       (dist_b)
            );

            assign decoded_flat = (dist_a <= dist_b) ? cand_a : cand_b;
        end
    endgenerate

endmodule
