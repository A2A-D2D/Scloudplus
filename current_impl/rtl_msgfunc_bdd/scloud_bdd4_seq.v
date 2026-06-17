`timescale 1ns/1ps

/*
 * Sequential BW4 BDD node.
 *
 * This is the smallest registered BDD layer; the BW2 leaves are direct
 * coordinate rounders.
 */
module scloud_bdd4_seq
#(
    parameter Q_WIDTH = 12,
    parameter TAU     = 3
)
(
    input  wire [(4*Q_WIDTH)-1:0] target_flat,
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

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_BDD_Y   = 3'd1;
    localparam [2:0] ST_INV_PHI = 3'd2;
    localparam [2:0] ST_BDD_Z   = 3'd3;
    localparam [2:0] ST_SELECT  = 3'd4;
    localparam [2:0] ST_DONE    = 3'd5;

    reg [2:0] state;

    reg [TOTAL_WIDTH-1:0] target_r;
    reg [HALF_WIDTH-1:0]  target_l_r;
    reg [HALF_WIDTH-1:0]  target_r_r;
    reg [HALF_WIDTH-1:0]  y_l_r;
    reg [HALF_WIDTH-1:0]  y_r_r;
    reg [HALF_WIDTH-1:0]  z_a_in_r;
    reg [HALF_WIDTH-1:0]  z_b_in_r;
    reg [HALF_WIDTH-1:0]  z_a_r;
    reg [HALF_WIDTH-1:0]  z_b_r;

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
    wire [31:0] dist_a_w;
    wire [31:0] dist_b_w;

    genvar gi;

    assign start_ready = (state == ST_IDLE);

    scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_l_re (
        .x_q(target_l_r[(0*Q_WIDTH)+:Q_WIDTH]),
        .y_q(y_l_w[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_l_im (
        .x_q(target_l_r[(1*Q_WIDTH)+:Q_WIDTH]),
        .y_q(y_l_w[(1*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_r_re (
        .x_q(target_r_r[(0*Q_WIDTH)+:Q_WIDTH]),
        .y_q(y_r_w[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_r_im (
        .x_q(target_r_r[(1*Q_WIDTH)+:Q_WIDTH]),
        .y_q(y_r_w[(1*Q_WIDTH)+:Q_WIDTH])
    );

    generate
        for (gi = 0; gi < HALF_COORDS; gi = gi + 1) begin : gen_diff
            assign diff_a_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_r_r[(gi*Q_WIDTH)+:Q_WIDTH] - y_l_r[(gi*Q_WIDTH)+:Q_WIDTH];
            assign diff_b_w[(gi*Q_WIDTH)+:Q_WIDTH] =
                target_l_r[(gi*Q_WIDTH)+:Q_WIDTH] - y_r_r[(gi*Q_WIDTH)+:Q_WIDTH];
        end
    endgenerate

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

    scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_za_re (
        .x_q(z_a_in_r[(0*Q_WIDTH)+:Q_WIDTH]),
        .y_q(z_a_w[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_za_im (
        .x_q(z_a_in_r[(1*Q_WIDTH)+:Q_WIDTH]),
        .y_q(z_a_w[(1*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_zb_re (
        .x_q(z_b_in_r[(0*Q_WIDTH)+:Q_WIDTH]),
        .y_q(z_b_w[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_bdd_round_coord_q #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_round_zb_im (
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

    scloud_bdd_distance_tree #(
        .Q_WIDTH(Q_WIDTH),
        .COORDS (2*COMPLEX_N)
    ) u_dist_a (
        .cand_flat   (cand_a_w),
        .target_flat (target_r),
        .distance_out(dist_a_w)
    );

    scloud_bdd_distance_tree #(
        .Q_WIDTH(Q_WIDTH),
        .COORDS (2*COMPLEX_N)
    ) u_dist_b (
        .cand_flat   (cand_b_w),
        .target_flat (target_r),
        .distance_out(dist_b_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            target_r     <= {TOTAL_WIDTH{1'b0}};
            target_l_r   <= {HALF_WIDTH{1'b0}};
            target_r_r   <= {HALF_WIDTH{1'b0}};
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
                    if (start) begin
                        target_r   <= target_flat;
                        target_l_r <= target_flat[0+:HALF_WIDTH];
                        target_r_r <= target_flat[HALF_WIDTH+:HALF_WIDTH];
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
                    state <= ST_SELECT;
                end
                ST_SELECT: begin
                    decoded_flat <= (dist_a_w < dist_b_w) ? cand_a_w : cand_b_w;
                    state        <= ST_DONE;
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
