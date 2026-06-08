`timescale 1ns/1ps

module scloud_bw16_round_coord
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [Q_WIDTH-1:0] x_q,
    output wire [Q_WIDTH-1:0] rounded_q,
    output wire [TAU-1:0]     small_val
);

    localparam DELTA_SHIFT = Q_WIDTH - TAU;
    localparam [Q_WIDTH-1:0] HALF_DELTA = {{(Q_WIDTH-1){1'b0}}, 1'b1} << (DELTA_SHIFT - 1);
    localparam [Q_WIDTH-1:0] ROUND_MASK = {{TAU{1'b1}}, {DELTA_SHIFT{1'b0}}};

    wire [Q_WIDTH:0] sum_ext;

    assign sum_ext = {1'b0, x_q} + {1'b0, HALF_DELTA};
    assign rounded_q = sum_ext[Q_WIDTH-1:0] & ROUND_MASK;
    assign small_val = rounded_q[Q_WIDTH-1:DELTA_SHIFT];

endmodule
