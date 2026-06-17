`timescale 1ns/1ps

/*
 * Sequential BW8 BDD using two reusable BW4 engines.
 */
module scloud_bdd8_seq
#(
    parameter Q_WIDTH = 12,
    parameter TAU     = 3
)
(
    input  wire [(8*Q_WIDTH)-1:0] target_flat,
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

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_WAIT_Y  = 3'd1;
    localparam [2:0] ST_INV_PHI = 3'd2;
    localparam [2:0] ST_START_Z = 3'd3;
    localparam [2:0] ST_WAIT_Z  = 3'd4;
    localparam [2:0] ST_SELECT  = 3'd5;
    localparam [2:0] ST_DONE    = 3'd6;

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

    wire child_start;
    wire child_a_ready;
    wire child_b_ready;
    wire child_a_busy;
    wire child_b_busy;
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
    wire [31:0] dist_a_w;
    wire [31:0] dist_b_w;

    genvar gi;

    assign start_ready = (state == ST_IDLE) && child_a_ready && child_b_ready;
    assign child_start = ((state == ST_IDLE) && start_ready && start) ||
                         (state == ST_START_Z);
    assign child_a_target = (state == ST_IDLE) ? target_flat[0+:HALF_WIDTH] :
                                                z_a_in_r;
    assign child_b_target = (state == ST_IDLE) ? target_flat[HALF_WIDTH+:HALF_WIDTH] :
                                                z_b_in_r;

    scloud_bdd4_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_child_a (
        .target_flat (child_a_target),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (child_start),
        .start_ready (child_a_ready),
        .busy        (child_a_busy),
        .done        (child_a_done),
        .decoded_flat(child_a_decoded)
    );

    scloud_bdd4_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_child_b (
        .target_flat (child_b_target),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (child_start),
        .start_ready (child_b_ready),
        .busy        (child_b_busy),
        .done        (child_b_done),
        .decoded_flat(child_b_decoded)
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
                    if (start_ready && start) begin
                        target_r   <= target_flat;
                        target_l_r <= target_flat[0+:HALF_WIDTH];
                        target_r_r <= target_flat[HALF_WIDTH+:HALF_WIDTH];
                        busy       <= 1'b1;
                        state      <= ST_WAIT_Y;
                    end
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
                        state <= ST_SELECT;
                    end
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
