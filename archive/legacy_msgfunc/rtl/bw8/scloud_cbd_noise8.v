`timescale 1ns/1ps

module scloud_cbd_noise_coord_eta7
#(
    parameter Q_WIDTH = 10
)
(
    input  wire [13:0]          rnd_bits,
    output wire [Q_WIDTH-1:0]   noise_q
);

    wire [3:0] pop_x;
    wire [3:0] pop_y;
    wire [5:0] diff_tc;

    assign pop_x = {3'b000, rnd_bits[0]}
                 + {3'b000, rnd_bits[1]}
                 + {3'b000, rnd_bits[2]}
                 + {3'b000, rnd_bits[3]}
                 + {3'b000, rnd_bits[4]}
                 + {3'b000, rnd_bits[5]}
                 + {3'b000, rnd_bits[6]};

    assign pop_y = {3'b000, rnd_bits[7]}
                 + {3'b000, rnd_bits[8]}
                 + {3'b000, rnd_bits[9]}
                 + {3'b000, rnd_bits[10]}
                 + {3'b000, rnd_bits[11]}
                 + {3'b000, rnd_bits[12]}
                 + {3'b000, rnd_bits[13]};

    assign diff_tc = {2'b00, pop_x} + (~{2'b00, pop_y}) + 6'd1;
    assign noise_q = {{(Q_WIDTH-6){diff_tc[5]}}, diff_tc};

endmodule

module scloud_cbd_noise8
#(
    parameter Q_WIDTH = 10,
    parameter ETA     = 7
)
(
    input  wire [(8*2*ETA)-1:0]     rnd_bits,
    output wire [(8*Q_WIDTH)-1:0]   noise_q_flat
);

    scloud_cbd_noise_coord_eta7 #(.Q_WIDTH(Q_WIDTH)) u_noise0 (
        .rnd_bits(rnd_bits[(0*2*ETA)+:(2*ETA)]),
        .noise_q (noise_q_flat[(0*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_cbd_noise_coord_eta7 #(.Q_WIDTH(Q_WIDTH)) u_noise1 (
        .rnd_bits(rnd_bits[(1*2*ETA)+:(2*ETA)]),
        .noise_q (noise_q_flat[(1*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_cbd_noise_coord_eta7 #(.Q_WIDTH(Q_WIDTH)) u_noise2 (
        .rnd_bits(rnd_bits[(2*2*ETA)+:(2*ETA)]),
        .noise_q (noise_q_flat[(2*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_cbd_noise_coord_eta7 #(.Q_WIDTH(Q_WIDTH)) u_noise3 (
        .rnd_bits(rnd_bits[(3*2*ETA)+:(2*ETA)]),
        .noise_q (noise_q_flat[(3*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_cbd_noise_coord_eta7 #(.Q_WIDTH(Q_WIDTH)) u_noise4 (
        .rnd_bits(rnd_bits[(4*2*ETA)+:(2*ETA)]),
        .noise_q (noise_q_flat[(4*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_cbd_noise_coord_eta7 #(.Q_WIDTH(Q_WIDTH)) u_noise5 (
        .rnd_bits(rnd_bits[(5*2*ETA)+:(2*ETA)]),
        .noise_q (noise_q_flat[(5*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_cbd_noise_coord_eta7 #(.Q_WIDTH(Q_WIDTH)) u_noise6 (
        .rnd_bits(rnd_bits[(6*2*ETA)+:(2*ETA)]),
        .noise_q (noise_q_flat[(6*Q_WIDTH)+:Q_WIDTH])
    );

    scloud_cbd_noise_coord_eta7 #(.Q_WIDTH(Q_WIDTH)) u_noise7 (
        .rnd_bits(rnd_bits[(7*2*ETA)+:(2*ETA)]),
        .noise_q (noise_q_flat[(7*Q_WIDTH)+:Q_WIDTH])
    );

endmodule
