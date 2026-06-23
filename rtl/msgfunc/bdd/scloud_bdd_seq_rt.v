`timescale 1ns/1ps

/*
 * Runtime-tau sequential BDD nodes for the RCE wrapper.
 *
 * These modules keep one physical BDD datapath and select tau=3/tau=4
 * rounding at run time. BDD16 and BDD32 serialize their four child calls
 * through one child instance. The resulting unfold-factor-8 hierarchy keeps
 * one BDD8 kernel and follows the area/latency trade-off in Fast Scloud+.
 */

module scloud_bdd_round_coord_q_rt
#(
    parameter Q_WIDTH = 12
)
(
    input  wire               tau_sel,
    input  wire [Q_WIDTH-1:0] x_q,
    output wire [Q_WIDTH-1:0] y_q
);

    localparam [Q_WIDTH-1:0] HALF_DELTA_TAU3 =
        {{(Q_WIDTH-1){1'b0}}, 1'b1} << ((Q_WIDTH - 3) - 1);
    localparam [Q_WIDTH-1:0] HALF_DELTA_TAU4 =
        {{(Q_WIDTH-1){1'b0}}, 1'b1} << ((Q_WIDTH - 4) - 1);
    localparam [Q_WIDTH-1:0] ROUND_MASK_TAU3 =
        {{3{1'b1}}, {(Q_WIDTH-3){1'b0}}};
    localparam [Q_WIDTH-1:0] ROUND_MASK_TAU4 =
        {{4{1'b1}}, {(Q_WIDTH-4){1'b0}}};

    wire [Q_WIDTH:0] sum_tau3;
    wire [Q_WIDTH:0] sum_tau4;
    wire [Q_WIDTH-1:0] round_tau3;
    wire [Q_WIDTH-1:0] round_tau4;

    assign sum_tau3 = {1'b0, x_q} + {1'b0, HALF_DELTA_TAU3};
    assign sum_tau4 = {1'b0, x_q} + {1'b0, HALF_DELTA_TAU4};
    assign round_tau3 = sum_tau3[Q_WIDTH-1:0] & ROUND_MASK_TAU3;
    assign round_tau4 = sum_tau4[Q_WIDTH-1:0] & ROUND_MASK_TAU4;
    assign y_q = tau_sel ? round_tau4 : round_tau3;

endmodule

module scloud_bdd4_seq_rt
#(
    parameter Q_WIDTH = 12
)
(
    input  wire [(4*Q_WIDTH)-1:0] target_flat,
    input  wire                   tau_sel,
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   start,
    output wire                   start_ready,
    output reg                    busy,
    output reg                    done,
    output reg  [(4*Q_WIDTH)-1:0] decoded_flat
);

    localparam COMPLEX_N    = 2;
    localparam HALF_COMPLEX = COMPLEX_N / 2;
    localparam HALF_COORDS  = COMPLEX_N;
    localparam HALF_WIDTH   = HALF_COORDS * Q_WIDTH;
    localparam TOTAL_WIDTH  = 2 * COMPLEX_N * Q_WIDTH;

    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_BDD_Y      = 4'd1;
    localparam [3:0] ST_INV_PHI    = 4'd2;
    localparam [3:0] ST_BDD_Z      = 4'd3;
    localparam [3:0] ST_PREP_DIST  = 4'd4;
    localparam [3:0] ST_START_DIST = 4'd5;
    localparam [3:0] ST_WAIT_DIST  = 4'd6;
    localparam [3:0] ST_DONE       = 4'd7;

    reg [3:0] state;
    reg tau_sel_r;

    reg [TOTAL_WIDTH-1:0] target_r;
    reg [HALF_WIDTH-1:0]  y_l_r;
    reg [HALF_WIDTH-1:0]  y_r_r;
    reg [HALF_WIDTH-1:0]  z_a_in_r;
    reg [HALF_WIDTH-1:0]  z_b_in_r;
    reg [HALF_WIDTH-1:0]  z_a_r;
    reg [HALF_WIDTH-1:0]  z_b_r;
    reg [HALF_WIDTH-1:0]  cand_a_hi_r;
    reg [HALF_WIDTH-1:0]  cand_b_lo_r;

    wire [HALF_WIDTH-1:0] y_l_w;
    wire [HALF_WIDTH-1:0] y_r_w;
    wire [HALF_WIDTH-1:0] diff_a_w;
    wire [HALF_WIDTH-1:0] diff_b_w;
    wire [HALF_WIDTH-1:0] z_a_in_w;
    wire [HALF_WIDTH-1:0] z_b_in_w;
    wire [HALF_WIDTH-1:0] z_a_w;
    wire [HALF_WIDTH-1:0] z_b_w;
    wire [HALF_WIDTH-1:0] phi_z_a_w;
    wire [HALF_WIDTH-1:0] phi_z_b_w;
    wire [TOTAL_WIDTH-1:0] cand_a_w;
    wire [TOTAL_WIDTH-1:0] cand_b_w;
    wire [TOTAL_WIDTH-1:0] cand_a_snap_w;
    wire [TOTAL_WIDTH-1:0] cand_b_snap_w;
    wire dist_ready;
    wire dist_start;
    wire dist_done;
    wire dist_select_a;

    genvar gi;

    assign start_ready = (state == ST_IDLE);

    scloud_bdd_round_coord_q_rt #(.Q_WIDTH(Q_WIDTH)) u_round_l_re (
        .tau_sel(tau_sel_r),
        .x_q(target_r[(0*Q_WIDTH)+:Q_WIDTH]),
        .y_q(y_l_w[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q_rt #(.Q_WIDTH(Q_WIDTH)) u_round_l_im (
        .tau_sel(tau_sel_r),
        .x_q(target_r[(1*Q_WIDTH)+:Q_WIDTH]),
        .y_q(y_l_w[(1*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q_rt #(.Q_WIDTH(Q_WIDTH)) u_round_r_re (
        .tau_sel(tau_sel_r),
        .x_q(target_r[HALF_WIDTH+(0*Q_WIDTH)+:Q_WIDTH]),
        .y_q(y_r_w[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q_rt #(.Q_WIDTH(Q_WIDTH)) u_round_r_im (
        .tau_sel(tau_sel_r),
        .x_q(target_r[HALF_WIDTH+(1*Q_WIDTH)+:Q_WIDTH]),
        .y_q(y_r_w[(1*Q_WIDTH)+:Q_WIDTH])
    );

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_diff
            assign diff_a_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r[HALF_WIDTH+(gi*Q_WIDTH)+:Q_WIDTH] - y_l_r[(gi*Q_WIDTH)+:Q_WIDTH];
            assign diff_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r[(gi*Q_WIDTH)+:Q_WIDTH] - y_r_r[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    assign cand_a_snap_w[0+:HALF_WIDTH] = y_l_r;
    assign cand_a_snap_w[HALF_WIDTH+:HALF_WIDTH] = cand_a_hi_r;
    assign cand_b_snap_w[0+:HALF_WIDTH] = cand_b_lo_r;
    assign cand_b_snap_w[HALF_WIDTH+:HALF_WIDTH] = y_r_r;

    scloud_bdd_inv_phi_flat #(
        .Q_WIDTH  (Q_WIDTH),
        .COMPLEX_N(HALF_COMPLEX)
    ) u_inv_phi_a (
        .d_flat(diff_a_w),
        .b_flat(z_a_in_w)
    );

    scloud_bdd_inv_phi_flat #(
        .Q_WIDTH  (Q_WIDTH),
        .COMPLEX_N(HALF_COMPLEX)
    ) u_inv_phi_b (
        .d_flat(diff_b_w),
        .b_flat(z_b_in_w)
    );

    scloud_bdd_round_coord_q_rt #(.Q_WIDTH(Q_WIDTH)) u_round_za_re (
        .tau_sel(tau_sel_r),
        .x_q(z_a_in_r[(0*Q_WIDTH)+:Q_WIDTH]),
        .y_q(z_a_w[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q_rt #(.Q_WIDTH(Q_WIDTH)) u_round_za_im (
        .tau_sel(tau_sel_r),
        .x_q(z_a_in_r[(1*Q_WIDTH)+:Q_WIDTH]),
        .y_q(z_a_w[(1*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q_rt #(.Q_WIDTH(Q_WIDTH)) u_round_zb_re (
        .tau_sel(tau_sel_r),
        .x_q(z_b_in_r[(0*Q_WIDTH)+:Q_WIDTH]),
        .y_q(z_b_w[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q_rt #(.Q_WIDTH(Q_WIDTH)) u_round_zb_im (
        .tau_sel(tau_sel_r),
        .x_q(z_b_in_r[(1*Q_WIDTH)+:Q_WIDTH]),
        .y_q(z_b_w[(1*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_phi_mul_flat #(
        .Q_WIDTH  (Q_WIDTH),
        .COMPLEX_N(HALF_COMPLEX)
    ) u_phi_za (
        .b_flat(z_a_r),
        .y_flat(phi_z_a_w)
    );

    scloud_bdd_phi_mul_flat #(
        .Q_WIDTH  (Q_WIDTH),
        .COMPLEX_N(HALF_COMPLEX)
    ) u_phi_zb (
        .b_flat(z_b_r),
        .y_flat(phi_z_b_w)
    );

    assign cand_a_w[0+:HALF_WIDTH] = y_l_r;
    assign cand_b_w[HALF_WIDTH+:HALF_WIDTH] = y_r_r;

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_candidates
            assign cand_a_w[HALF_WIDTH+(gi*Q_WIDTH)+:Q_WIDTH] =
                y_l_r[(gi*Q_WIDTH)+:Q_WIDTH] + phi_z_a_w[(gi*Q_WIDTH)+:Q_WIDTH];
            assign cand_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                y_r_r[(gi*Q_WIDTH)+:Q_WIDTH] + phi_z_b_w[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    assign dist_start = (state == ST_START_DIST) && dist_ready;

    scloud_bdd_distance_pair_pipe #(
        .Q_WIDTH(Q_WIDTH),
        .COORDS (2*COMPLEX_N)
    ) u_dist_pipe (
        .cand_a_flat(cand_a_snap_w),
        .cand_b_flat(cand_b_snap_w),
        .target_flat(target_r),
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (dist_start),
        .start_ready(dist_ready),
        .busy       (),
        .done       (dist_done),
        .select_a   (dist_select_a),
        .distance_a (),
        .distance_b ()
    );

    always @(posedge clk) begin
        if (state == ST_PREP_DIST) begin
            cand_a_hi_r <= cand_a_w[HALF_WIDTH+:HALF_WIDTH];
            cand_b_lo_r <= cand_b_w[0+:HALF_WIDTH];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            tau_sel_r    <= 1'b0;
            target_r     <= {TOTAL_WIDTH{1'b0}};
            y_l_r        <= {HALF_WIDTH{1'b0}};
            y_r_r        <= {HALF_WIDTH{1'b0}};
            z_a_in_r     <= {HALF_WIDTH{1'b0}};
            z_b_in_r     <= {HALF_WIDTH{1'b0}};
            z_a_r        <= {HALF_WIDTH{1'b0}};
            z_b_r        <= {HALF_WIDTH{1'b0}};
            decoded_flat <= {TOTAL_WIDTH{1'b0}};
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start_ready && start) begin
                        tau_sel_r  <= tau_sel;
                        target_r   <= target_flat;
                        busy       <= 1'b1;
                        state      <= ST_BDD_Y;
                    end
                end
                ST_BDD_Y: begin
                    y_l_r <= y_l_w;
                    y_r_r <= y_r_w;
                    state <= ST_INV_PHI;
                end
                ST_INV_PHI: begin
                    z_a_in_r <= z_a_in_w;
                    z_b_in_r <= z_b_in_w;
                    state    <= ST_BDD_Z;
                end
                ST_BDD_Z: begin
                    z_a_r <= z_a_w;
                    z_b_r <= z_b_w;
                    state <= ST_PREP_DIST;
                end
                ST_PREP_DIST: begin
                    state <= ST_START_DIST;
                end
                ST_START_DIST: begin
                    if (dist_ready)
                        state <= ST_WAIT_DIST;
                end
                ST_WAIT_DIST: begin
                    if (dist_done) begin
                        decoded_flat <= dist_select_a ? cand_a_snap_w : cand_b_snap_w;
                        state        <= ST_DONE;
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
                end
            endcase
        end
    end

endmodule

module scloud_bdd8_seq_rt
#(
    parameter Q_WIDTH = 12
)
(
    input  wire [(8*Q_WIDTH)-1:0] target_flat,
    input  wire                   tau_sel,
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   start,
    output wire                   start_ready,
    output reg                    busy,
    output reg                    done,
    output reg  [(8*Q_WIDTH)-1:0] decoded_flat
);

    localparam COMPLEX_N    = 4;
    localparam HALF_COMPLEX = COMPLEX_N / 2;
    localparam HALF_COORDS  = COMPLEX_N;
    localparam HALF_WIDTH   = HALF_COORDS * Q_WIDTH;
    localparam TOTAL_WIDTH  = 2 * COMPLEX_N * Q_WIDTH;

    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_WAIT_Y     = 4'd1;
    localparam [3:0] ST_INV_PHI    = 4'd2;
    localparam [3:0] ST_START_Z    = 4'd3;
    localparam [3:0] ST_WAIT_Z     = 4'd4;
    localparam [3:0] ST_PREP_DIST  = 4'd5;
    localparam [3:0] ST_START_DIST = 4'd6;
    localparam [3:0] ST_WAIT_DIST  = 4'd7;
    localparam [3:0] ST_DONE       = 4'd8;
    localparam [3:0] ST_START_Y    = 4'd9;

    reg [3:0] state;
    reg tau_sel_r;

    reg [TOTAL_WIDTH-1:0] target_r;
    reg [HALF_WIDTH-1:0]  y_l_r;
    reg [HALF_WIDTH-1:0]  y_r_r;
    reg [HALF_WIDTH-1:0]  z_a_in_r;
    reg [HALF_WIDTH-1:0]  z_b_in_r;
    reg [HALF_WIDTH-1:0]  z_a_r;
    reg [HALF_WIDTH-1:0]  z_b_r;
    reg [HALF_WIDTH-1:0]  cand_a_hi_r;
    reg [HALF_WIDTH-1:0]  cand_b_lo_r;

    wire child_start;
    wire child_a_ready;
    wire child_b_ready;
    wire child_a_done;
    wire child_b_done;
    wire [HALF_WIDTH-1:0] child_a_target;
    wire [HALF_WIDTH-1:0] child_b_target;
    wire [HALF_WIDTH-1:0] child_a_decoded;
    wire [HALF_WIDTH-1:0] child_b_decoded;
    wire [HALF_WIDTH-1:0] diff_a_w;
    wire [HALF_WIDTH-1:0] diff_b_w;
    wire [HALF_WIDTH-1:0] z_a_in_w;
    wire [HALF_WIDTH-1:0] z_b_in_w;
    wire [HALF_WIDTH-1:0] phi_z_a_w;
    wire [HALF_WIDTH-1:0] phi_z_b_w;
    wire [TOTAL_WIDTH-1:0] cand_a_w;
    wire [TOTAL_WIDTH-1:0] cand_b_w;
    wire [TOTAL_WIDTH-1:0] cand_a_snap_w;
    wire [TOTAL_WIDTH-1:0] cand_b_snap_w;
    wire dist_ready;
    wire dist_start;
    wire dist_done;
    wire dist_select_a;
    wire child_tau_sel;

    genvar gi;

    assign start_ready = (state == ST_IDLE);
    assign child_tau_sel = tau_sel_r;
    assign child_start = (state == ST_START_Y) || (state == ST_START_Z);
    assign child_a_target = (state == ST_START_Y) ? target_r[0+:HALF_WIDTH] :
                                                   z_a_in_r;
    assign child_b_target = (state == ST_START_Y) ? target_r[HALF_WIDTH+:HALF_WIDTH] :
                                                   z_b_in_r;

    scloud_bdd4_seq_rt #(.Q_WIDTH(Q_WIDTH)) u_child_a (
        .target_flat (child_a_target),
        .tau_sel     (child_tau_sel),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (child_start),
        .start_ready (child_a_ready),
        .busy        (),
        .done        (child_a_done),
        .decoded_flat(child_a_decoded)
    );

    scloud_bdd4_seq_rt #(.Q_WIDTH(Q_WIDTH)) u_child_b (
        .target_flat (child_b_target),
        .tau_sel     (child_tau_sel),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (child_start),
        .start_ready (child_b_ready),
        .busy        (),
        .done        (child_b_done),
        .decoded_flat(child_b_decoded)
    );

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_diff
            assign diff_a_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r[HALF_WIDTH+(gi*Q_WIDTH)+:Q_WIDTH] - y_l_r[(gi*Q_WIDTH)+:Q_WIDTH];
            assign diff_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r[(gi*Q_WIDTH)+:Q_WIDTH] - y_r_r[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    assign cand_a_snap_w[0+:HALF_WIDTH] = y_l_r;
    assign cand_a_snap_w[HALF_WIDTH+:HALF_WIDTH] = cand_a_hi_r;
    assign cand_b_snap_w[0+:HALF_WIDTH] = cand_b_lo_r;
    assign cand_b_snap_w[HALF_WIDTH+:HALF_WIDTH] = y_r_r;

    scloud_bdd_inv_phi_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_inv_phi_a (
        .d_flat(diff_a_w),
        .b_flat(z_a_in_w)
    );

    scloud_bdd_inv_phi_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_inv_phi_b (
        .d_flat(diff_b_w),
        .b_flat(z_b_in_w)
    );

    scloud_bdd_phi_mul_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_phi_za (
        .b_flat(z_a_r),
        .y_flat(phi_z_a_w)
    );

    scloud_bdd_phi_mul_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_phi_zb (
        .b_flat(z_b_r),
        .y_flat(phi_z_b_w)
    );

    assign cand_a_w[0+:HALF_WIDTH] = y_l_r;
    assign cand_b_w[HALF_WIDTH+:HALF_WIDTH] = y_r_r;

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_candidates
            assign cand_a_w[HALF_WIDTH+(gi*Q_WIDTH)+:Q_WIDTH] =
                y_l_r[(gi*Q_WIDTH)+:Q_WIDTH] + phi_z_a_w[(gi*Q_WIDTH)+:Q_WIDTH];
            assign cand_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                y_r_r[(gi*Q_WIDTH)+:Q_WIDTH] + phi_z_b_w[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    assign dist_start = (state == ST_START_DIST) && dist_ready;

    scloud_bdd_distance_pair_pipe #(
        .Q_WIDTH(Q_WIDTH),
        .COORDS (2*COMPLEX_N)
    ) u_dist_pipe (
        .cand_a_flat(cand_a_snap_w),
        .cand_b_flat(cand_b_snap_w),
        .target_flat(target_r),
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (dist_start),
        .start_ready(dist_ready),
        .busy       (),
        .done       (dist_done),
        .select_a   (dist_select_a),
        .distance_a (),
        .distance_b ()
    );

    always @(posedge clk) begin
        if (state == ST_PREP_DIST) begin
            cand_a_hi_r <= cand_a_w[HALF_WIDTH+:HALF_WIDTH];
            cand_b_lo_r <= cand_b_w[0+:HALF_WIDTH];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            tau_sel_r    <= 1'b0;
            target_r     <= {TOTAL_WIDTH{1'b0}};
            y_l_r        <= {HALF_WIDTH{1'b0}};
            y_r_r        <= {HALF_WIDTH{1'b0}};
            z_a_in_r     <= {HALF_WIDTH{1'b0}};
            z_b_in_r     <= {HALF_WIDTH{1'b0}};
            z_a_r        <= {HALF_WIDTH{1'b0}};
            z_b_r        <= {HALF_WIDTH{1'b0}};
            decoded_flat <= {TOTAL_WIDTH{1'b0}};
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start_ready && start) begin
                        tau_sel_r  <= tau_sel;
                        target_r   <= target_flat;
                        busy       <= 1'b1;
                        state      <= ST_START_Y;
                    end
                end
                ST_START_Y: begin
                    state <= ST_WAIT_Y;
                end
                ST_WAIT_Y: begin
                    busy <= 1'b1;
                    if (child_a_done && child_b_done) begin
                        y_l_r <= child_a_decoded;
                        y_r_r <= child_b_decoded;
                        state <= ST_INV_PHI;
                    end
                end
                ST_INV_PHI: begin
                    z_a_in_r <= z_a_in_w;
                    z_b_in_r <= z_b_in_w;
                    state    <= ST_START_Z;
                end
                ST_START_Z: begin
                    state <= ST_WAIT_Z;
                end
                ST_WAIT_Z: begin
                    busy <= 1'b1;
                    if (child_a_done && child_b_done) begin
                        z_a_r <= child_a_decoded;
                        z_b_r <= child_b_decoded;
                        state <= ST_PREP_DIST;
                    end
                end
                ST_PREP_DIST: begin
                    state <= ST_START_DIST;
                end
                ST_START_DIST: begin
                    if (dist_ready)
                        state <= ST_WAIT_DIST;
                end
                ST_WAIT_DIST: begin
                    if (dist_done) begin
                        decoded_flat <= dist_select_a ? cand_a_snap_w : cand_b_snap_w;
                        state        <= ST_DONE;
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
                end
            endcase
        end
    end

endmodule

module scloud_bdd16_seq_rt
#(
    parameter Q_WIDTH = 12
)
(
    input  wire [(16*Q_WIDTH)-1:0] target_flat,
    input  wire                    tau_sel,
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    output wire                    dist_start,
    output wire [(16*Q_WIDTH)-1:0] dist_cand_a,
    output wire [(16*Q_WIDTH)-1:0] dist_cand_b,
    output wire [(16*Q_WIDTH)-1:0] dist_target,
    input  wire                    dist_done,
    input  wire                    dist_select_a,
    output wire                    start_ready,
    output reg                     busy,
    output reg                     done,
    output reg  [(16*Q_WIDTH)-1:0] decoded_flat
);

    localparam COMPLEX_N    = 8;
    localparam HALF_COMPLEX = COMPLEX_N / 2;
    localparam HALF_COORDS  = COMPLEX_N;
    localparam HALF_WIDTH   = HALF_COORDS * Q_WIDTH;
    localparam TOTAL_WIDTH  = 2 * COMPLEX_N * Q_WIDTH;

    localparam [3:0] ST_IDLE     = 4'd0;
    localparam [3:0] ST_WAIT_YL  = 4'd1;
    localparam [3:0] ST_START_YR = 4'd2;
    localparam [3:0] ST_WAIT_YR  = 4'd3;
    localparam [3:0] ST_INV_PHI  = 4'd4;
    localparam [3:0] ST_START_ZA = 4'd5;
    localparam [3:0] ST_WAIT_ZA  = 4'd6;
    localparam [3:0] ST_START_ZB = 4'd7;
    localparam [3:0] ST_WAIT_ZB  = 4'd8;
    localparam [3:0] ST_SELECT     = 4'd9;
    localparam [3:0] ST_START_DIST = 4'd10;
    localparam [3:0] ST_WAIT_DIST  = 4'd11;
    localparam [3:0] ST_DONE       = 4'd12;
    localparam [3:0] ST_START_YL   = 4'd13;

    reg [3:0] state;
    reg tau_sel_r;

    reg [TOTAL_WIDTH-1:0] target_r;
    reg [HALF_WIDTH-1:0]  y_l_r;
    reg [HALF_WIDTH-1:0]  y_r_r;
    reg [HALF_WIDTH-1:0]  z_a_in_r;
    reg [HALF_WIDTH-1:0]  z_b_in_r;
    reg [HALF_WIDTH-1:0]  z_a_r;
    reg [HALF_WIDTH-1:0]  z_b_r;
    reg [HALF_WIDTH-1:0]  cand_a_hi_r;
    reg [HALF_WIDTH-1:0]  cand_b_lo_r;

    wire child_start;
    wire child_ready;
    wire child_done;
    wire [HALF_WIDTH-1:0] child_target;
    wire [HALF_WIDTH-1:0] child_decoded;
    wire [HALF_WIDTH-1:0] diff_a_w;
    wire [HALF_WIDTH-1:0] diff_b_w;
    wire [HALF_WIDTH-1:0] z_a_in_w;
    wire [HALF_WIDTH-1:0] z_b_in_w;
    wire [HALF_WIDTH-1:0] phi_z_a_w;
    wire [HALF_WIDTH-1:0] phi_z_b_w;
    wire [TOTAL_WIDTH-1:0] cand_a_w;
    wire [TOTAL_WIDTH-1:0] cand_b_w;
    wire [TOTAL_WIDTH-1:0] cand_a_snap_w;
    wire [TOTAL_WIDTH-1:0] cand_b_snap_w;
    wire child_tau_sel;

    genvar gi;

    assign start_ready = (state == ST_IDLE);
    assign child_tau_sel = tau_sel_r;
    assign child_start = (state == ST_START_YL) ||
                         (state == ST_START_YR) ||
                         (state == ST_START_ZA) ||
                         (state == ST_START_ZB);
    assign child_target = (state == ST_START_YL) ? target_r[0+:HALF_WIDTH] :
                          (state == ST_START_YR) ? target_r[HALF_WIDTH+:HALF_WIDTH] :
                          (state == ST_START_ZA) ? z_a_in_r : z_b_in_r;

    scloud_bdd8_seq_rt #(.Q_WIDTH(Q_WIDTH)) u_child (
        .target_flat (child_target),
        .tau_sel     (child_tau_sel),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (child_start),
        .start_ready (child_ready),
        .busy        (),
        .done        (child_done),
        .decoded_flat(child_decoded)
    );

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_diff
            assign diff_a_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r[HALF_WIDTH+(gi*Q_WIDTH)+:Q_WIDTH] - y_l_r[(gi*Q_WIDTH)+:Q_WIDTH];
            assign diff_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r[(gi*Q_WIDTH)+:Q_WIDTH] - y_r_r[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    assign cand_a_snap_w[0+:HALF_WIDTH] = y_l_r;
    assign cand_a_snap_w[HALF_WIDTH+:HALF_WIDTH] = cand_a_hi_r;
    assign cand_b_snap_w[0+:HALF_WIDTH] = cand_b_lo_r;
    assign cand_b_snap_w[HALF_WIDTH+:HALF_WIDTH] = y_r_r;

    scloud_bdd_inv_phi_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_inv_phi_a (
        .d_flat(diff_a_w),
        .b_flat(z_a_in_w)
    );

    scloud_bdd_inv_phi_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_inv_phi_b (
        .d_flat(diff_b_w),
        .b_flat(z_b_in_w)
    );

    scloud_bdd_phi_mul_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_phi_za (
        .b_flat(z_a_r),
        .y_flat(phi_z_a_w)
    );

    scloud_bdd_phi_mul_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_phi_zb (
        .b_flat(z_b_r),
        .y_flat(phi_z_b_w)
    );

    assign cand_a_w[0+:HALF_WIDTH] = y_l_r;
    assign cand_b_w[HALF_WIDTH+:HALF_WIDTH] = y_r_r;

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_candidates
            assign cand_a_w[HALF_WIDTH+(gi*Q_WIDTH)+:Q_WIDTH] =
                y_l_r[(gi*Q_WIDTH)+:Q_WIDTH] + phi_z_a_w[(gi*Q_WIDTH)+:Q_WIDTH];
            assign cand_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                y_r_r[(gi*Q_WIDTH)+:Q_WIDTH] + phi_z_b_w[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    assign dist_start = (state == ST_START_DIST);
    assign dist_cand_a = cand_a_snap_w;
    assign dist_cand_b = cand_b_snap_w;
    assign dist_target = target_r;

    always @(posedge clk) begin
        if (state == ST_SELECT) begin
            cand_a_hi_r <= cand_a_w[HALF_WIDTH+:HALF_WIDTH];
            cand_b_lo_r <= cand_b_w[0+:HALF_WIDTH];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            tau_sel_r    <= 1'b0;
            target_r     <= {TOTAL_WIDTH{1'b0}};
            y_l_r        <= {HALF_WIDTH{1'b0}};
            y_r_r        <= {HALF_WIDTH{1'b0}};
            z_a_in_r     <= {HALF_WIDTH{1'b0}};
            z_b_in_r     <= {HALF_WIDTH{1'b0}};
            z_a_r        <= {HALF_WIDTH{1'b0}};
            z_b_r        <= {HALF_WIDTH{1'b0}};
            decoded_flat <= {TOTAL_WIDTH{1'b0}};
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start_ready && start) begin
                        tau_sel_r  <= tau_sel;
                        target_r   <= target_flat;
                        busy       <= 1'b1;
                        state      <= ST_START_YL;
                    end
                end
                ST_START_YL: state <= ST_WAIT_YL;
                ST_WAIT_YL: begin
                    busy <= 1'b1;
                    if (child_done) begin
                        y_l_r <= child_decoded;
                        state <= ST_START_YR;
                    end
                end
                ST_START_YR: state <= ST_WAIT_YR;
                ST_WAIT_YR: begin
                    if (child_done) begin
                        y_r_r <= child_decoded;
                        state <= ST_INV_PHI;
                    end
                end
                ST_INV_PHI: begin
                    z_a_in_r <= z_a_in_w;
                    z_b_in_r <= z_b_in_w;
                    state    <= ST_START_ZA;
                end
                ST_START_ZA: state <= ST_WAIT_ZA;
                ST_WAIT_ZA: begin
                    if (child_done) begin
                        z_a_r <= child_decoded;
                        state <= ST_START_ZB;
                    end
                end
                ST_START_ZB: state <= ST_WAIT_ZB;
                ST_WAIT_ZB: begin
                    if (child_done) begin
                        z_b_r <= child_decoded;
                        state <= ST_SELECT;
                    end
                end
                ST_SELECT: begin
                    state <= ST_START_DIST;
                end
                ST_START_DIST: state <= ST_WAIT_DIST;
                ST_WAIT_DIST: begin
                    if (dist_done) begin
                        decoded_flat <= dist_select_a ? cand_a_snap_w : cand_b_snap_w;
                        state        <= ST_DONE;
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
                end
            endcase
        end
    end

endmodule

module scloud_bdd32_seq_rt
#(
    parameter Q_WIDTH = 12
)
(
    input  wire [(16*Q_WIDTH)-1:0] target_half_data,
    input  wire                    target_half_valid,
    input  wire                    target_half_sel,
    output wire                    target_half_ready,
    input  wire                    tau_sel,
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    output wire                    start_ready,
    output reg                     busy,
    output reg                     done,
    output reg  [(32*Q_WIDTH)-1:0] decoded_flat
);

    localparam COMPLEX_N    = 16;
    localparam HALF_COMPLEX = COMPLEX_N / 2;
    localparam HALF_COORDS  = COMPLEX_N;
    localparam HALF_WIDTH   = HALF_COORDS * Q_WIDTH;
    localparam TOTAL_WIDTH  = 2 * COMPLEX_N * Q_WIDTH;

    localparam [3:0] ST_IDLE     = 4'd0;
    localparam [3:0] ST_WAIT_YL  = 4'd1;
    localparam [3:0] ST_START_YR = 4'd2;
    localparam [3:0] ST_WAIT_YR  = 4'd3;
    localparam [3:0] ST_INV_PHI  = 4'd4;
    localparam [3:0] ST_START_ZA = 4'd5;
    localparam [3:0] ST_WAIT_ZA  = 4'd6;
    localparam [3:0] ST_START_ZB = 4'd7;
    localparam [3:0] ST_WAIT_ZB  = 4'd8;
    localparam [3:0] ST_SELECT     = 4'd9;
    localparam [3:0] ST_START_DIST = 4'd10;
    localparam [3:0] ST_WAIT_DIST  = 4'd11;
    localparam [3:0] ST_DONE       = 4'd12;
    localparam [3:0] ST_START_YL   = 4'd13;

    reg [3:0] state;
    reg tau_sel_r;
    reg [1:0] target_loaded;

    reg [TOTAL_WIDTH-1:0] target_r;
    reg [HALF_WIDTH-1:0]  y_l_r;
    reg [HALF_WIDTH-1:0]  y_r_r;
    reg [HALF_WIDTH-1:0]  z_a_in_r;
    reg [HALF_WIDTH-1:0]  z_b_in_r;
    reg [HALF_WIDTH-1:0]  z_a_r;
    reg [HALF_WIDTH-1:0]  z_b_r;
    reg [HALF_WIDTH-1:0]  cand_a_hi_r;
    reg [HALF_WIDTH-1:0]  cand_b_lo_r;

    wire child_start;
    wire child_ready;
    wire child_done;
    wire [HALF_WIDTH-1:0] child_target;
    wire [HALF_WIDTH-1:0] child_decoded;
    wire [HALF_WIDTH-1:0] diff_a_w;
    wire [HALF_WIDTH-1:0] diff_b_w;
    wire [HALF_WIDTH-1:0] z_a_in_w;
    wire [HALF_WIDTH-1:0] z_b_in_w;
    wire [HALF_WIDTH-1:0] phi_z_a_w;
    wire [HALF_WIDTH-1:0] phi_z_b_w;
    wire [TOTAL_WIDTH-1:0] cand_a_w;
    wire [TOTAL_WIDTH-1:0] cand_b_w;
    wire [TOTAL_WIDTH-1:0] cand_a_snap_w;
    wire [TOTAL_WIDTH-1:0] cand_b_snap_w;
    wire dist_start;
    wire dist_done;
    wire dist_select_a;
    wire child_dist_start;
    wire child_dist_done;
    wire child_dist_select_a;
    wire [HALF_WIDTH-1:0] child_dist_cand_a;
    wire [HALF_WIDTH-1:0] child_dist_cand_b;
    wire [HALF_WIDTH-1:0] child_dist_target;
    wire shared_dist_start;
    wire shared_dist_done;
    wire shared_dist_select_a;
    wire [TOTAL_WIDTH-1:0] shared_dist_cand_a;
    wire [TOTAL_WIDTH-1:0] shared_dist_cand_b;
    wire [TOTAL_WIDTH-1:0] shared_dist_target;
    wire child_tau_sel;

    reg dist_owner_child;

    genvar gi;

    assign target_half_ready = (state == ST_IDLE) && !start;
    assign start_ready = (state == ST_IDLE) && (target_loaded == 2'b11);
    assign child_tau_sel = tau_sel_r;
    assign child_start = (state == ST_START_YL) ||
                         (state == ST_START_YR) ||
                         (state == ST_START_ZA) ||
                         (state == ST_START_ZB);
    assign child_target = (state == ST_START_YL) ? target_r[0+:HALF_WIDTH] :
                          (state == ST_START_YR) ? target_r[HALF_WIDTH+:HALF_WIDTH] :
                          (state == ST_START_ZA) ? z_a_in_r : z_b_in_r;

    scloud_bdd16_seq_rt #(.Q_WIDTH(Q_WIDTH)) u_child (
        .target_flat (child_target),
        .tau_sel     (child_tau_sel),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (child_start),
        .dist_start  (child_dist_start),
        .dist_cand_a (child_dist_cand_a),
        .dist_cand_b (child_dist_cand_b),
        .dist_target (child_dist_target),
        .dist_done   (child_dist_done),
        .dist_select_a(child_dist_select_a),
        .start_ready (child_ready),
        .busy        (),
        .done        (child_done),
        .decoded_flat(child_decoded)
    );

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_diff
            assign diff_a_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r[HALF_WIDTH+(gi*Q_WIDTH)+:Q_WIDTH] - y_l_r[(gi*Q_WIDTH)+:Q_WIDTH];
            assign diff_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r[(gi*Q_WIDTH)+:Q_WIDTH] - y_r_r[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    assign cand_a_snap_w[0+:HALF_WIDTH] = y_l_r;
    assign cand_a_snap_w[HALF_WIDTH+:HALF_WIDTH] = cand_a_hi_r;
    assign cand_b_snap_w[0+:HALF_WIDTH] = cand_b_lo_r;
    assign cand_b_snap_w[HALF_WIDTH+:HALF_WIDTH] = y_r_r;

    scloud_bdd_inv_phi_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_inv_phi_a (
        .d_flat(diff_a_w),
        .b_flat(z_a_in_w)
    );

    scloud_bdd_inv_phi_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_inv_phi_b (
        .d_flat(diff_b_w),
        .b_flat(z_b_in_w)
    );

    scloud_bdd_phi_mul_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_phi_za (
        .b_flat(z_a_r),
        .y_flat(phi_z_a_w)
    );

    scloud_bdd_phi_mul_flat #(.Q_WIDTH(Q_WIDTH), .COMPLEX_N(HALF_COMPLEX)) u_phi_zb (
        .b_flat(z_b_r),
        .y_flat(phi_z_b_w)
    );

    assign cand_a_w[0+:HALF_WIDTH] = y_l_r;
    assign cand_b_w[HALF_WIDTH+:HALF_WIDTH] = y_r_r;

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_candidates
            assign cand_a_w[HALF_WIDTH+(gi*Q_WIDTH)+:Q_WIDTH] =
                y_l_r[(gi*Q_WIDTH)+:Q_WIDTH] + phi_z_a_w[(gi*Q_WIDTH)+:Q_WIDTH];
            assign cand_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                y_r_r[(gi*Q_WIDTH)+:Q_WIDTH] + phi_z_b_w[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

    assign dist_start = (state == ST_START_DIST);
    assign shared_dist_start = child_dist_start || dist_start;
    assign shared_dist_cand_a = (dist_owner_child || child_dist_start) ?
                                {{HALF_WIDTH{1'b0}}, child_dist_cand_a} : cand_a_snap_w;
    assign shared_dist_cand_b = (dist_owner_child || child_dist_start) ?
                                {{HALF_WIDTH{1'b0}}, child_dist_cand_b} : cand_b_snap_w;
    assign shared_dist_target = (dist_owner_child || child_dist_start) ?
                                {{HALF_WIDTH{1'b0}}, child_dist_target} : target_r;
    assign child_dist_done = shared_dist_done && dist_owner_child;
    assign child_dist_select_a = shared_dist_select_a;
    assign dist_done = shared_dist_done && !dist_owner_child;
    assign dist_select_a = shared_dist_select_a;

    scloud_bdd_distance_seq #(
        .Q_WIDTH(Q_WIDTH),
        .COORDS (2*COMPLEX_N),
        .LANES  (8)
    ) u_dist_seq (
        .cand_a_flat(shared_dist_cand_a),
        .cand_b_flat(shared_dist_cand_b),
        .target_flat(shared_dist_target),
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (shared_dist_start),
        .start_ready(),
        .busy       (),
        .done       (shared_dist_done),
        .select_a   (shared_dist_select_a),
        .distance_a (),
        .distance_b ()
    );

    always @(posedge clk) begin
        if (state == ST_SELECT) begin
            cand_a_hi_r <= cand_a_w[HALF_WIDTH+:HALF_WIDTH];
            cand_b_lo_r <= cand_b_w[0+:HALF_WIDTH];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            tau_sel_r    <= 1'b0;
            target_loaded <= 2'b00;
            target_r     <= {TOTAL_WIDTH{1'b0}};
            y_l_r        <= {HALF_WIDTH{1'b0}};
            y_r_r        <= {HALF_WIDTH{1'b0}};
            z_a_in_r     <= {HALF_WIDTH{1'b0}};
            z_b_in_r     <= {HALF_WIDTH{1'b0}};
            z_a_r        <= {HALF_WIDTH{1'b0}};
            z_b_r        <= {HALF_WIDTH{1'b0}};
            decoded_flat <= {TOTAL_WIDTH{1'b0}};
            dist_owner_child <= 1'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;
            if (target_half_valid && target_half_ready) begin
                if (target_half_sel) begin
                    target_r[HALF_WIDTH+:HALF_WIDTH] <= target_half_data;
                    target_loaded[1] <= 1'b1;
                end else begin
                    target_r[0+:HALF_WIDTH] <= target_half_data;
                    target_loaded[0] <= 1'b1;
                end
            end
            if (child_dist_start)
                dist_owner_child <= 1'b1;
            else if (shared_dist_done)
                dist_owner_child <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start_ready && start) begin
                        tau_sel_r  <= tau_sel;
                        target_loaded <= 2'b00;
                        busy       <= 1'b1;
                        state      <= ST_START_YL;
                    end
                end
                ST_START_YL: state <= ST_WAIT_YL;
                ST_WAIT_YL: begin
                    busy <= 1'b1;
                    if (child_done) begin
                        y_l_r <= child_decoded;
                        state <= ST_START_YR;
                    end
                end
                ST_START_YR: state <= ST_WAIT_YR;
                ST_WAIT_YR: begin
                    if (child_done) begin
                        y_r_r <= child_decoded;
                        state <= ST_INV_PHI;
                    end
                end
                ST_INV_PHI: begin
                    z_a_in_r <= z_a_in_w;
                    z_b_in_r <= z_b_in_w;
                    state    <= ST_START_ZA;
                end
                ST_START_ZA: state <= ST_WAIT_ZA;
                ST_WAIT_ZA: begin
                    if (child_done) begin
                        z_a_r <= child_decoded;
                        state <= ST_START_ZB;
                    end
                end
                ST_START_ZB: state <= ST_WAIT_ZB;
                ST_WAIT_ZB: begin
                    if (child_done) begin
                        z_b_r <= child_decoded;
                        state <= ST_SELECT;
                    end
                end
                ST_SELECT: begin
                    state <= ST_START_DIST;
                end
                ST_START_DIST: state <= ST_WAIT_DIST;
                ST_WAIT_DIST: begin
                    if (dist_done) begin
                        decoded_flat <= dist_select_a ? cand_a_snap_w : cand_b_snap_w;
                        state        <= ST_DONE;
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
                end
            endcase
        end
    end

endmodule
