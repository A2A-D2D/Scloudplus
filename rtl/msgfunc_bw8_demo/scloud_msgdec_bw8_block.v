`timescale 1ns/1ps

module scloud_msgdec_bw8_block
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [(8*Q_WIDTH)-1:0] noisy_q_flat,
    output wire [11:0]            msg_block,
    output wire [(8*Q_WIDTH)-1:0] rounded_q_flat
);

    localparam DELTA_SHIFT = Q_WIDTH - TAU;
    localparam [Q_WIDTH-1:0] HALF_DELTA = {{(Q_WIDTH-1){1'b0}}, 1'b1} << (DELTA_SHIFT - 1);
    localparam [Q_WIDTH-1:0] ROUND_MASK = {{TAU{1'b1}}, {DELTA_SHIFT{1'b0}}};

    wire [Q_WIDTH:0] r0_sum;
    wire [Q_WIDTH:0] i0_sum;
    wire [Q_WIDTH:0] r1_sum;
    wire [Q_WIDTH:0] i1_sum;
    wire [Q_WIDTH:0] r2_sum;
    wire [Q_WIDTH:0] i2_sum;
    wire [Q_WIDTH:0] r3_sum;
    wire [Q_WIDTH:0] i3_sum;

    wire [Q_WIDTH-1:0] r0_q;
    wire [Q_WIDTH-1:0] i0_q;
    wire [Q_WIDTH-1:0] r1_q;
    wire [Q_WIDTH-1:0] i1_q;
    wire [Q_WIDTH-1:0] r2_q;
    wire [Q_WIDTH-1:0] i2_q;
    wire [Q_WIDTH-1:0] r3_q;
    wire [Q_WIDTH-1:0] i3_q;

    wire [TAU-1:0] y0_re;
    wire [TAU-1:0] y0_im;
    wire [TAU-1:0] y1_re;
    wire [TAU-1:0] y1_im;
    wire [TAU-1:0] y2_re;
    wire [TAU-1:0] y2_im;
    wire [TAU-1:0] y3_re;
    wire [TAU-1:0] y3_im;

    wire [5:0] s0_re;
    wire [5:0] s0_im;
    wire [5:0] s1_re;
    wire [5:0] s1_im;
    wire [5:0] s2_re;
    wire [5:0] s2_im;
    wire [5:0] s3_re;
    wire [5:0] s3_im;

    wire [6:0] a2_re_sum;
    wire [6:0] a2_im_sum;
    wire [6:0] a3_re_sum;
    wire [6:0] a3_im_sum;
    wire [6:0] raw1_re_sum;
    wire [6:0] raw1_im_sum;
    wire [6:0] raw3_re_sum;
    wire [6:0] raw3_im_sum;

    wire [5:0] a0_re;
    wire [5:0] a0_im;
    wire [5:0] a1_re;
    wire [5:0] a1_im;
    wire [5:0] a2_re;
    wire [5:0] a2_im;
    wire [5:0] a3_re;
    wire [5:0] a3_im;

    wire [5:0] raw0_re;
    wire [5:0] raw0_im;
    wire [5:0] raw1_re;
    wire [5:0] raw1_im;
    wire [5:0] raw2_re;
    wire [5:0] raw2_im;
    wire [5:0] raw3_re;
    wire [5:0] raw3_im;

    wire [5:0] red0_b_prime;
    wire [5:0] red1_b_prime;
    wire [5:0] red2_b_prime;
    wire [5:0] red3_b_prime;
    wire [5:0] red0_a_adj;
    wire [5:0] red1_a_adj;
    wire [5:0] red2_a_adj;
    wire [5:0] red3_a_adj;

    wire [1:0] v0_re_bits;
    wire [1:0] v0_im_bits;
    wire [1:0] v1_re_bits;
    wire       v1_im_bits;
    wire [1:0] v2_re_bits;
    wire       v2_im_bits;
    wire       v3_re_bits;
    wire       v3_im_bits;

    assign r0_sum = {1'b0, noisy_q_flat[(0*Q_WIDTH)+:Q_WIDTH]} + {1'b0, HALF_DELTA};
    assign i0_sum = {1'b0, noisy_q_flat[(1*Q_WIDTH)+:Q_WIDTH]} + {1'b0, HALF_DELTA};
    assign r1_sum = {1'b0, noisy_q_flat[(2*Q_WIDTH)+:Q_WIDTH]} + {1'b0, HALF_DELTA};
    assign i1_sum = {1'b0, noisy_q_flat[(3*Q_WIDTH)+:Q_WIDTH]} + {1'b0, HALF_DELTA};
    assign r2_sum = {1'b0, noisy_q_flat[(4*Q_WIDTH)+:Q_WIDTH]} + {1'b0, HALF_DELTA};
    assign i2_sum = {1'b0, noisy_q_flat[(5*Q_WIDTH)+:Q_WIDTH]} + {1'b0, HALF_DELTA};
    assign r3_sum = {1'b0, noisy_q_flat[(6*Q_WIDTH)+:Q_WIDTH]} + {1'b0, HALF_DELTA};
    assign i3_sum = {1'b0, noisy_q_flat[(7*Q_WIDTH)+:Q_WIDTH]} + {1'b0, HALF_DELTA};

    assign r0_q = r0_sum[Q_WIDTH-1:0] & ROUND_MASK;
    assign i0_q = i0_sum[Q_WIDTH-1:0] & ROUND_MASK;
    assign r1_q = r1_sum[Q_WIDTH-1:0] & ROUND_MASK;
    assign i1_q = i1_sum[Q_WIDTH-1:0] & ROUND_MASK;
    assign r2_q = r2_sum[Q_WIDTH-1:0] & ROUND_MASK;
    assign i2_q = i2_sum[Q_WIDTH-1:0] & ROUND_MASK;
    assign r3_q = r3_sum[Q_WIDTH-1:0] & ROUND_MASK;
    assign i3_q = i3_sum[Q_WIDTH-1:0] & ROUND_MASK;

    assign rounded_q_flat[(0*Q_WIDTH)+:Q_WIDTH] = r0_q;
    assign rounded_q_flat[(1*Q_WIDTH)+:Q_WIDTH] = i0_q;
    assign rounded_q_flat[(2*Q_WIDTH)+:Q_WIDTH] = r1_q;
    assign rounded_q_flat[(3*Q_WIDTH)+:Q_WIDTH] = i1_q;
    assign rounded_q_flat[(4*Q_WIDTH)+:Q_WIDTH] = r2_q;
    assign rounded_q_flat[(5*Q_WIDTH)+:Q_WIDTH] = i2_q;
    assign rounded_q_flat[(6*Q_WIDTH)+:Q_WIDTH] = r3_q;
    assign rounded_q_flat[(7*Q_WIDTH)+:Q_WIDTH] = i3_q;

    assign y0_re = r0_q[Q_WIDTH-1:DELTA_SHIFT];
    assign y0_im = i0_q[Q_WIDTH-1:DELTA_SHIFT];
    assign y1_re = r1_q[Q_WIDTH-1:DELTA_SHIFT];
    assign y1_im = i1_q[Q_WIDTH-1:DELTA_SHIFT];
    assign y2_re = r2_q[Q_WIDTH-1:DELTA_SHIFT];
    assign y2_im = i2_q[Q_WIDTH-1:DELTA_SHIFT];
    assign y3_re = r3_q[Q_WIDTH-1:DELTA_SHIFT];
    assign y3_im = i3_q[Q_WIDTH-1:DELTA_SHIFT];

    assign s0_re = {4'b0000, y0_re};
    assign s0_im = {4'b0000, y0_im};
    assign s1_re = {4'b0000, y1_re};
    assign s1_im = {4'b0000, y1_im};
    assign s2_re = {4'b0000, y2_re};
    assign s2_im = {4'b0000, y2_im};
    assign s3_re = {4'b0000, y3_re};
    assign s3_im = {4'b0000, y3_im};

    assign a0_re = s0_re;
    assign a0_im = s0_im;
    assign a1_re = s1_re;
    assign a1_im = s1_im;

    assign a2_re_sum = {s2_re[5], s2_re} + {s2_im[5], s2_im} - {s0_re[5], s0_re} - {s0_im[5], s0_im};
    assign a2_im_sum = {s2_im[5], s2_im} - {s2_re[5], s2_re} - {s0_im[5], s0_im} + {s0_re[5], s0_re};
    assign a3_re_sum = {s3_re[5], s3_re} + {s3_im[5], s3_im} - {s1_re[5], s1_re} - {s1_im[5], s1_im};
    assign a3_im_sum = {s3_im[5], s3_im} - {s3_re[5], s3_re} - {s1_im[5], s1_im} + {s1_re[5], s1_re};

    assign a2_re = {a2_re_sum[6], a2_re_sum[6:1]};
    assign a2_im = {a2_im_sum[6], a2_im_sum[6:1]};
    assign a3_re = {a3_re_sum[6], a3_re_sum[6:1]};
    assign a3_im = {a3_im_sum[6], a3_im_sum[6:1]};

    assign raw0_re = a0_re;
    assign raw0_im = a0_im;
    assign raw2_re = a2_re;
    assign raw2_im = a2_im;

    assign raw1_re_sum = {a1_re[5], a1_re} + {a1_im[5], a1_im} - {a0_re[5], a0_re} - {a0_im[5], a0_im};
    assign raw1_im_sum = {a1_im[5], a1_im} - {a1_re[5], a1_re} - {a0_im[5], a0_im} + {a0_re[5], a0_re};
    assign raw3_re_sum = {a3_re[5], a3_re} + {a3_im[5], a3_im} - {a2_re[5], a2_re} - {a2_im[5], a2_im};
    assign raw3_im_sum = {a3_im[5], a3_im} - {a3_re[5], a3_re} - {a2_im[5], a2_im} + {a2_re[5], a2_re};

    assign raw1_re = {raw1_re_sum[6], raw1_re_sum[6:1]};
    assign raw1_im = {raw1_im_sum[6], raw1_im_sum[6:1]};
    assign raw3_re = {raw3_re_sum[6], raw3_re_sum[6:1]};
    assign raw3_im = {raw3_im_sum[6], raw3_im_sum[6:1]};

    assign red0_b_prime = {4'b0000, raw0_im[1:0]};
    assign red1_b_prime = {5'b00000, raw1_im[0]};
    assign red2_b_prime = {5'b00000, raw2_im[0]};
    assign red3_b_prime = {5'b00000, raw3_im[0]};

    assign red0_a_adj = raw0_re - raw0_im + red0_b_prime;
    assign red1_a_adj = raw1_re - raw1_im + red1_b_prime;
    assign red2_a_adj = raw2_re - raw2_im + red2_b_prime;
    assign red3_a_adj = raw3_re - raw3_im + red3_b_prime;

    assign v0_im_bits = raw0_im[1:0];
    assign v0_re_bits = red0_a_adj[1:0];
    assign v1_im_bits = raw1_im[0];
    assign v1_re_bits = red1_a_adj[1:0];
    assign v2_im_bits = raw2_im[0];
    assign v2_re_bits = red2_a_adj[1:0];
    assign v3_im_bits = raw3_im[0];
    assign v3_re_bits = red3_a_adj[0];

    assign msg_block = {
        v0_re_bits,
        v0_im_bits,
        v1_re_bits,
        v1_im_bits,
        v2_re_bits,
        v2_im_bits,
        v3_re_bits,
        v3_im_bits
    };

endmodule
