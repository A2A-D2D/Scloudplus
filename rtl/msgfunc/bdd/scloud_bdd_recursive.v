`timescale 1ns/1ps

module scloud_bdd_phi_mul_pair_q
#(
    parameter Q_WIDTH = 12
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
    parameter Q_WIDTH = 12
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
    parameter Q_WIDTH = 12,
    parameter TAU     = 3
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

module scloud_bdd_sq_diff_q
#(
    parameter Q_WIDTH = 12
)
(
    input  wire [Q_WIDTH-1:0] cand_q,
    input  wire [Q_WIDTH-1:0] target_q,
    output wire [(2*Q_WIDTH)+1:0] sq_diff
);

    wire [Q_WIDTH-1:0] diff_q;
    wire signed [Q_WIDTH:0] diff_ext;

    assign diff_q   = cand_q - target_q;
    assign diff_ext = {diff_q[Q_WIDTH-1], diff_q};
    assign sq_diff  = diff_ext * diff_ext;

endmodule

module scloud_bdd_sum_tree
#(
    parameter TERMS     = 32,
    parameter IN_WIDTH  = 11,
    parameter OUT_WIDTH = 32
)
(
    input  wire [(TERMS*IN_WIDTH)-1:0] terms_flat,
    output wire [OUT_WIDTH-1:0]        sum_out
);

    localparam LEFT_TERMS  = TERMS / 2;
    localparam RIGHT_TERMS = TERMS - LEFT_TERMS;

    generate
        if (TERMS == 1) begin : gen_leaf
            assign sum_out = {{(OUT_WIDTH-IN_WIDTH){1'b0}}, terms_flat[0+:IN_WIDTH]};
        end else begin : gen_node
            wire [OUT_WIDTH-1:0] left_sum;
            wire [OUT_WIDTH-1:0] right_sum;

            scloud_bdd_sum_tree #(
                .TERMS    (LEFT_TERMS),
                .IN_WIDTH (IN_WIDTH),
                .OUT_WIDTH(OUT_WIDTH)
            ) u_left_sum (
                .terms_flat(terms_flat[0+:(LEFT_TERMS*IN_WIDTH)]),
                .sum_out   (left_sum)
            );

            scloud_bdd_sum_tree #(
                .TERMS    (RIGHT_TERMS),
                .IN_WIDTH (IN_WIDTH),
                .OUT_WIDTH(OUT_WIDTH)
            ) u_right_sum (
                .terms_flat(terms_flat[(LEFT_TERMS*IN_WIDTH)+:(RIGHT_TERMS*IN_WIDTH)]),
                .sum_out   (right_sum)
            );

            assign sum_out = left_sum + right_sum;
        end
    endgenerate

endmodule

module scloud_bdd_distance_tree
#(
    parameter Q_WIDTH = 12,
    parameter COORDS  = 32
)
(
    input  wire [(COORDS*Q_WIDTH)-1:0] cand_flat,
    input  wire [(COORDS*Q_WIDTH)-1:0] target_flat,
    output wire [31:0]                 distance_out
);

    localparam TERM_WIDTH = (2 * Q_WIDTH) + 2;

    wire [(COORDS*TERM_WIDTH)-1:0] sq_flat;
    genvar gi;

    generate
        for (gi = 0; gi < COORDS; gi = gi + 1) begin : gen_sq
            scloud_bdd_sq_diff_q #(.Q_WIDTH(Q_WIDTH)) u_sq_diff (
                .cand_q   (cand_flat[(gi*Q_WIDTH)+:Q_WIDTH]),
                .target_q (target_flat[(gi*Q_WIDTH)+:Q_WIDTH]),
                .sq_diff  (sq_flat[(gi*TERM_WIDTH)+:TERM_WIDTH])
            );
        end
    endgenerate

    scloud_bdd_sum_tree #(
        .TERMS    (COORDS),
        .IN_WIDTH (TERM_WIDTH),
        .OUT_WIDTH(32)
    ) u_l2_sum_tree (
        .terms_flat(sq_flat),
        .sum_out   (distance_out)
    );

endmodule

module scloud_bdd_distance_pair_pipe
#(
    parameter Q_WIDTH = 12,
    parameter COORDS  = 8
)
(
    input  wire [(COORDS*Q_WIDTH)-1:0] cand_a_flat,
    input  wire [(COORDS*Q_WIDTH)-1:0] cand_b_flat,
    input  wire [(COORDS*Q_WIDTH)-1:0] target_flat,
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start,
    output wire                        start_ready,
    output reg                         busy,
    output reg                         done,
    output reg                         select_a,
    output reg  [31:0]                 distance_a,
    output reg  [31:0]                 distance_b
);

    localparam TERM_WIDTH = (2 * Q_WIDTH) + 2;
    localparam DIFF_WIDTH = Q_WIDTH + 1;
    localparam HALF_COORDS = COORDS / 2;

    localparam [2:0] ST_IDLE      = 3'd0;
    localparam [2:0] ST_LOAD_DIFF = 3'd1;
    localparam [2:0] ST_MUL_1     = 3'd2;
    localparam [2:0] ST_MUL_2     = 3'd3;
    localparam [2:0] ST_SUM_PART  = 3'd4;
    localparam [2:0] ST_SUM_FINAL = 3'd5;
    localparam [2:0] ST_COMPARE   = 3'd6;
    localparam [2:0] ST_DONE      = 3'd7;

    reg [2:0] state;
    reg [(COORDS*DIFF_WIDTH)-1:0] diff_a_r;
    reg [(COORDS*DIFF_WIDTH)-1:0] diff_b_r;
    reg [(COORDS*TERM_WIDTH)-1:0] sq_a_1_r;
    reg [(COORDS*TERM_WIDTH)-1:0] sq_b_1_r;
    reg [(COORDS*TERM_WIDTH)-1:0] sq_a_2_r;
    reg [(COORDS*TERM_WIDTH)-1:0] sq_b_2_r;
    reg [31:0] sum_a_lo_r;
    reg [31:0] sum_a_hi_r;
    reg [31:0] sum_b_lo_r;
    reg [31:0] sum_b_hi_r;
    reg [31:0] sum_a_r;
    reg [31:0] sum_b_r;

    wire [(COORDS*DIFF_WIDTH)-1:0] diff_a_w;
    wire [(COORDS*DIFF_WIDTH)-1:0] diff_b_w;
    wire [(COORDS*TERM_WIDTH)-1:0] sq_a_w;
    wire [(COORDS*TERM_WIDTH)-1:0] sq_b_w;
    wire [31:0] sum_a_lo_w;
    wire [31:0] sum_a_hi_w;
    wire [31:0] sum_b_lo_w;
    wire [31:0] sum_b_hi_w;
    wire [31:0] sum_a_w;
    wire [31:0] sum_b_w;

    assign start_ready = (state == ST_IDLE);

    genvar gi;
    generate
        for (gi = 0; gi < COORDS; gi = gi + 1) begin : gen_pair_lane
            wire [Q_WIDTH-1:0] diff_a_q;
            wire [Q_WIDTH-1:0] diff_b_q;
            wire signed [DIFF_WIDTH-1:0] diff_a_lane;
            wire signed [DIFF_WIDTH-1:0] diff_b_lane;

            assign diff_a_q = cand_a_flat[(gi*Q_WIDTH)+:Q_WIDTH] -
                              target_flat[(gi*Q_WIDTH)+:Q_WIDTH];
            assign diff_b_q = cand_b_flat[(gi*Q_WIDTH)+:Q_WIDTH] -
                              target_flat[(gi*Q_WIDTH)+:Q_WIDTH];
            assign diff_a_w[(gi*DIFF_WIDTH)+:DIFF_WIDTH] =
                {diff_a_q[Q_WIDTH-1], diff_a_q};
            assign diff_b_w[(gi*DIFF_WIDTH)+:DIFF_WIDTH] =
                {diff_b_q[Q_WIDTH-1], diff_b_q};
            assign diff_a_lane = diff_a_r[(gi*DIFF_WIDTH)+:DIFF_WIDTH];
            assign diff_b_lane = diff_b_r[(gi*DIFF_WIDTH)+:DIFF_WIDTH];
            assign sq_a_w[(gi*TERM_WIDTH)+:TERM_WIDTH] =
                diff_a_lane * diff_a_lane;
            assign sq_b_w[(gi*TERM_WIDTH)+:TERM_WIDTH] =
                diff_b_lane * diff_b_lane;
        end
    endgenerate

    scloud_bdd_sum_tree #(
        .TERMS    (HALF_COORDS),
        .IN_WIDTH (TERM_WIDTH),
        .OUT_WIDTH(32)
    ) u_sum_a_lo (
        .terms_flat(sq_a_2_r[0+:(HALF_COORDS*TERM_WIDTH)]),
        .sum_out   (sum_a_lo_w)
    );

    scloud_bdd_sum_tree #(
        .TERMS    (HALF_COORDS),
        .IN_WIDTH (TERM_WIDTH),
        .OUT_WIDTH(32)
    ) u_sum_a_hi (
        .terms_flat(sq_a_2_r[(HALF_COORDS*TERM_WIDTH)+:(HALF_COORDS*TERM_WIDTH)]),
        .sum_out   (sum_a_hi_w)
    );

    scloud_bdd_sum_tree #(
        .TERMS    (HALF_COORDS),
        .IN_WIDTH (TERM_WIDTH),
        .OUT_WIDTH(32)
    ) u_sum_b_lo (
        .terms_flat(sq_b_2_r[0+:(HALF_COORDS*TERM_WIDTH)]),
        .sum_out   (sum_b_lo_w)
    );

    scloud_bdd_sum_tree #(
        .TERMS    (HALF_COORDS),
        .IN_WIDTH (TERM_WIDTH),
        .OUT_WIDTH(32)
    ) u_sum_b_hi (
        .terms_flat(sq_b_2_r[(HALF_COORDS*TERM_WIDTH)+:(HALF_COORDS*TERM_WIDTH)]),
        .sum_out   (sum_b_hi_w)
    );

    assign sum_a_w = sum_a_lo_r + sum_a_hi_r;
    assign sum_b_w = sum_b_lo_r + sum_b_hi_r;

    /*
     * Pipeline data intentionally has no asynchronous reset. It is fully
     * overwritten on every request, allowing Vivado to map the multiply
     * stages onto DSP48 AREG/MREG/PREG resources.
     */
    always @(posedge clk) begin
        if (state == ST_LOAD_DIFF) begin
            diff_a_r <= diff_a_w;
            diff_b_r <= diff_b_w;
        end
        if (state == ST_MUL_1) begin
            sq_a_1_r <= sq_a_w;
            sq_b_1_r <= sq_b_w;
        end
        if (state == ST_MUL_2) begin
            sq_a_2_r <= sq_a_1_r;
            sq_b_2_r <= sq_b_1_r;
        end
        if (state == ST_SUM_PART) begin
            sum_a_lo_r <= sum_a_lo_w;
            sum_a_hi_r <= sum_a_hi_w;
            sum_b_lo_r <= sum_b_lo_w;
            sum_b_hi_r <= sum_b_hi_w;
        end
        if (state == ST_SUM_FINAL) begin
            sum_a_r <= sum_a_w;
            sum_b_r <= sum_b_w;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            select_a   <= 1'b0;
            distance_a <= 32'd0;
            distance_b <= 32'd0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        state <= ST_LOAD_DIFF;
                    end
                end
                ST_LOAD_DIFF: state <= ST_MUL_1;
                ST_MUL_1:     state <= ST_MUL_2;
                ST_MUL_2:     state <= ST_SUM_PART;
                ST_SUM_PART:  state <= ST_SUM_FINAL;
                ST_SUM_FINAL: state <= ST_COMPARE;
                ST_COMPARE: begin
                    distance_a <= sum_a_r;
                    distance_b <= sum_b_r;
                    select_a   <= (sum_a_r < sum_b_r);
                    state      <= ST_DONE;
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

module scloud_bdd_distance_seq
#(
    parameter Q_WIDTH = 12,
    parameter COORDS  = 32,
    parameter LANES   = 8
)
(
    input  wire [(COORDS*Q_WIDTH)-1:0] cand_a_flat,
    input  wire [(COORDS*Q_WIDTH)-1:0] cand_b_flat,
    input  wire [(COORDS*Q_WIDTH)-1:0] target_flat,
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start,
    output wire                        start_ready,
    output reg                         busy,
    output reg                         done,
    output reg                         select_a,
    output reg  [31:0]                 distance_a,
    output reg  [31:0]                 distance_b
);

    localparam TERM_WIDTH = (2 * Q_WIDTH) + 2;
    localparam DIFF_WIDTH = Q_WIDTH + 1;
    localparam CHUNKS     = COORDS / LANES;
    localparam HALF_LANES = LANES / 2;

    function integer clog2;
        input integer value;
        integer temp;
        begin
            temp = value - 1;
            clog2 = 0;
            while (temp > 0) begin
                clog2 = clog2 + 1;
                temp = temp >> 1;
            end
        end
    endfunction

    localparam CHUNK_BITS = (CHUNKS <= 1) ? 1 : clog2(CHUNKS);
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_LOAD_CHUNK = 4'd1;
    localparam [3:0] ST_LOAD_DIFF  = 4'd2;
    localparam [3:0] ST_MUL_1      = 4'd3;
    localparam [3:0] ST_MUL_2      = 4'd4;
    localparam [3:0] ST_SUM_PART   = 4'd5;
    localparam [3:0] ST_SUM_FINAL  = 4'd6;
    localparam [3:0] ST_ACCUM      = 4'd7;
    localparam [3:0] ST_COMPARE    = 4'd8;
    localparam [3:0] ST_DONE       = 4'd9;

    reg [3:0] state;
    reg [CHUNK_BITS-1:0] chunk_idx;
    reg phase_b;
    reg [31:0] accum_a;
    reg [31:0] accum_b;
    reg [(LANES*Q_WIDTH)-1:0] chunk_cand_r;
    reg [(LANES*Q_WIDTH)-1:0] chunk_target_r;
    reg [(LANES*DIFF_WIDTH)-1:0] diff_pipe_r;
    reg [(LANES*TERM_WIDTH)-1:0] sq_pipe_1_r;
    reg [(LANES*TERM_WIDTH)-1:0] sq_pipe_2_r;
    reg [31:0] lane_sum_lo_r;
    reg [31:0] lane_sum_hi_r;
    reg [31:0] lane_sum_r;

    wire [(COORDS*Q_WIDTH)-1:0] active_cand;
    wire [(COORDS*Q_WIDTH)-1:0] shifted_cand;
    wire [(COORDS*Q_WIDTH)-1:0] shifted_target;
    wire [(LANES*DIFF_WIDTH)-1:0] diff_flat;
    wire [(LANES*TERM_WIDTH)-1:0] sq_flat;
    wire [31:0] lane_sum_lo_w;
    wire [31:0] lane_sum_hi_w;
    wire [31:0] lane_sum_w;

    assign start_ready = (state == ST_IDLE);
    assign active_cand = phase_b ? cand_b_flat : cand_a_flat;
    assign shifted_cand = active_cand >> (chunk_idx * LANES * Q_WIDTH);
    assign shifted_target = target_flat >> (chunk_idx * LANES * Q_WIDTH);

    genvar gi;
    generate
        for (gi = 0; gi < LANES; gi = gi + 1) begin : gen_lane
            wire [Q_WIDTH-1:0] diff_q;
            wire signed [DIFF_WIDTH-1:0] diff_pipe_lane;

            assign diff_q = chunk_cand_r[(gi*Q_WIDTH)+:Q_WIDTH] -
                            chunk_target_r[(gi*Q_WIDTH)+:Q_WIDTH];
            assign diff_flat[(gi*DIFF_WIDTH)+:DIFF_WIDTH] =
                {diff_q[Q_WIDTH-1], diff_q};
            assign diff_pipe_lane =
                diff_pipe_r[(gi*DIFF_WIDTH)+:DIFF_WIDTH];
            assign sq_flat[(gi*TERM_WIDTH)+:TERM_WIDTH] =
                diff_pipe_lane * diff_pipe_lane;
        end
    endgenerate

    scloud_bdd_sum_tree #(
        .TERMS    (HALF_LANES),
        .IN_WIDTH (TERM_WIDTH),
        .OUT_WIDTH(32)
    ) u_lane_sum_lo (
        .terms_flat(sq_pipe_2_r[0+:(HALF_LANES*TERM_WIDTH)]),
        .sum_out   (lane_sum_lo_w)
    );

    scloud_bdd_sum_tree #(
        .TERMS    (HALF_LANES),
        .IN_WIDTH (TERM_WIDTH),
        .OUT_WIDTH(32)
    ) u_lane_sum_hi (
        .terms_flat(sq_pipe_2_r[(HALF_LANES*TERM_WIDTH)+:(HALF_LANES*TERM_WIDTH)]),
        .sum_out   (lane_sum_hi_w)
    );

    assign lane_sum_w = lane_sum_lo_r + lane_sum_hi_r;

    /*
     * Keep the DSP data pipeline free of asynchronous reset so Vivado can
     * absorb these registers into DSP48 AREG/MREG/PREG stages. Control state
     * is reset separately; pipeline data is always overwritten before use.
     */
    always @(posedge clk) begin
        if (state == ST_LOAD_CHUNK) begin
            chunk_cand_r <= shifted_cand[0+:(LANES*Q_WIDTH)];
            chunk_target_r <= shifted_target[0+:(LANES*Q_WIDTH)];
        end
        if (state == ST_LOAD_DIFF)
            diff_pipe_r <= diff_flat;
        if (state == ST_MUL_1)
            sq_pipe_1_r <= sq_flat;
        if (state == ST_MUL_2)
            sq_pipe_2_r <= sq_pipe_1_r;
        if (state == ST_SUM_PART) begin
            lane_sum_lo_r <= lane_sum_lo_w;
            lane_sum_hi_r <= lane_sum_hi_w;
        end
        if (state == ST_SUM_FINAL)
            lane_sum_r <= lane_sum_w;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            chunk_idx  <= {CHUNK_BITS{1'b0}};
            phase_b    <= 1'b0;
            accum_a    <= 32'd0;
            accum_b    <= 32'd0;
            distance_a <= 32'd0;
            distance_b <= 32'd0;
            select_a   <= 1'b0;
            busy       <= 1'b0;
            done       <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        chunk_idx <= {CHUNK_BITS{1'b0}};
                        phase_b   <= 1'b0;
                        accum_a   <= 32'd0;
                        accum_b   <= 32'd0;
                        busy      <= 1'b1;
                        state     <= ST_LOAD_CHUNK;
                    end
                end
                ST_LOAD_CHUNK: begin
                    state <= ST_LOAD_DIFF;
                end
                ST_LOAD_DIFF: begin
                    state <= ST_MUL_1;
                end
                ST_MUL_1: begin
                    state <= ST_MUL_2;
                end
                ST_MUL_2: begin
                    state <= ST_SUM_PART;
                end
                ST_SUM_PART: begin
                    state <= ST_SUM_FINAL;
                end
                ST_SUM_FINAL: begin
                    state <= ST_ACCUM;
                end
                ST_ACCUM: begin
                    if (!phase_b) begin
                        accum_a <= accum_a + lane_sum_r;
                        if (chunk_idx == CHUNKS-1) begin
                            distance_a <= accum_a + lane_sum_r;
                            chunk_idx  <= {CHUNK_BITS{1'b0}};
                            phase_b    <= 1'b1;
                            state      <= ST_LOAD_CHUNK;
                        end else begin
                            chunk_idx <= chunk_idx + 1'b1;
                            state     <= ST_LOAD_CHUNK;
                        end
                    end else begin
                        accum_b <= accum_b + lane_sum_r;
                        if (chunk_idx == CHUNKS-1) begin
                            distance_b <= accum_b + lane_sum_r;
                            state      <= ST_COMPARE;
                        end else begin
                            chunk_idx <= chunk_idx + 1'b1;
                            state     <= ST_LOAD_CHUNK;
                        end
                    end
                end
                ST_COMPARE: begin
                    select_a <= (distance_a < distance_b);
                    state    <= ST_DONE;
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

/* scloud_bdd_distance — Legacy reference module.
 * Now superseded by scloud_bdd_distance_tree which uses a structural
 * tree-adder for better synthesis QoR.  Kept under `ifdef for regression only.
 */
`ifdef KEEP_BDD_DISTANCE_REF
module scloud_bdd_distance
#(
    parameter Q_WIDTH = 12,
    parameter COORDS  = 32,
    parameter USE_L1  = 0     // 0 = Euclidean (L2), 1 = legacy Manhattan (L1)
)
(
    input  wire [(COORDS*Q_WIDTH)-1:0] cand_flat,
    input  wire [(COORDS*Q_WIDTH)-1:0] target_flat,
    output reg  [31:0]                 distance_out
);

    integer idx;
    reg [Q_WIDTH-1:0]     diff_q;
    reg [Q_WIDTH:0]       diff_ext;
    reg [Q_WIDTH:0]       abs_diff;
    reg [(2*Q_WIDTH)+1:0] sq_diff;        // only used when USE_L1=0

    always @(*) begin
        distance_out = 32'd0;
        for (idx = 0; idx < COORDS; idx = idx + 1) begin
            diff_q   = cand_flat[(idx*Q_WIDTH)+:Q_WIDTH] - target_flat[(idx*Q_WIDTH)+:Q_WIDTH];
            diff_ext = {diff_q[Q_WIDTH-1], diff_q};

            // absolute value: sign-extended diff_q → |diff_q|
            if (diff_ext[Q_WIDTH])
                abs_diff = (~diff_ext) + {{Q_WIDTH{1'b0}}, 1'b1};
            else
                abs_diff = diff_ext;

            if (USE_L1) begin
                // L1 Manhattan distance: dist = Σ |diff|
                // No multipliers needed — pure add/accumulate.
                distance_out = distance_out + {{(31-Q_WIDTH){1'b0}}, abs_diff};
            end else begin
                // L2 Euclidean distance (legacy): dist = Σ (diff²)
                // Retained for verification; requires Q_WIDTH×Q_WIDTH multipliers.
                sq_diff = abs_diff * abs_diff;
                distance_out = distance_out + sq_diff;
            end
        end
    end

endmodule
`endif  // KEEP_BDD_DISTANCE_REF

module scloud_bdd_phi_mul_flat
#(
    parameter Q_WIDTH  = 12,
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
    parameter Q_WIDTH  = 12,
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
    parameter Q_WIDTH   = 12,
    parameter TAU       = 3,
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

            scloud_bdd_distance_tree #(
                .Q_WIDTH(Q_WIDTH),
                .COORDS (COORDS)
            ) u_dist_a (
                .cand_flat    (cand_a),
                .target_flat  (target_flat),
                .distance_out (dist_a)
            );

            scloud_bdd_distance_tree #(
                .Q_WIDTH(Q_WIDTH),
                .COORDS (COORDS)
            ) u_dist_b (
                .cand_flat    (cand_b),
                .target_flat  (target_flat),
                .distance_out (dist_b)
            );

            assign decoded_flat = (dist_a < dist_b) ? cand_a : cand_b;
        end
    endgenerate

endmodule
