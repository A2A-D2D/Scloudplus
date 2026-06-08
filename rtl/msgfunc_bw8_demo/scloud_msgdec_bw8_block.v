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

    wire signed [5:0] s0_re;
    wire signed [5:0] s0_im;
    wire signed [5:0] s1_re;
    wire signed [5:0] s1_im;
    wire signed [5:0] s2_re;
    wire signed [5:0] s2_im;
    wire signed [5:0] s3_re;
    wire signed [5:0] s3_im;

    wire signed [5:0] a0_re;
    wire signed [5:0] a0_im;
    wire signed [5:0] a1_re;
    wire signed [5:0] a1_im;
    wire signed [5:0] a2_re;
    wire signed [5:0] a2_im;
    wire signed [5:0] a3_re;
    wire signed [5:0] a3_im;

    wire signed [5:0] raw0_re;
    wire signed [5:0] raw0_im;
    wire signed [5:0] raw1_re;
    wire signed [5:0] raw1_im;
    wire signed [5:0] raw2_re;
    wire signed [5:0] raw2_im;
    wire signed [5:0] raw3_re;
    wire signed [5:0] raw3_im;

    wire [1:0] v0_re_bits;
    wire [1:0] v0_im_bits;
    wire [1:0] v1_re_bits;
    wire       v1_im_bits;
    wire [1:0] v2_re_bits;
    wire       v2_im_bits;
    wire       v3_re_bits;
    wire       v3_im_bits;

    function [Q_WIDTH-1:0] round_delta;
        input [Q_WIDTH-1:0] x;
        reg [Q_WIDTH:0] sum_ext;
        begin
            sum_ext = {1'b0, x} + {1'b0, HALF_DELTA};
            round_delta = sum_ext[Q_WIDTH-1:0] & {{TAU{1'b1}}, {DELTA_SHIFT{1'b0}}};
        end
    endfunction

    function signed [5:0] half_exact_signed;
        input signed [6:0] x;
        begin
            half_exact_signed = x >>> 1;
        end
    endfunction

    function [1:0] mod4_signed;
        input signed [5:0] x;
        begin
            mod4_signed = x[1:0];
        end
    endfunction

    function [1:0] reduce_real_w0;
        input signed [5:0] a;
        input signed [5:0] b;
        reg [1:0] b_prime;
        reg signed [5:0] b_prime_ext;
        reg signed [5:0] a_adj;
        begin
            b_prime = b[1:0];
            b_prime_ext = $signed({4'b0000, b_prime});
            a_adj = a - (b - b_prime_ext);
            reduce_real_w0 = a_adj[1:0];
        end
    endfunction

    function [1:0] reduce_real_w1;
        input signed [5:0] a;
        input signed [5:0] b;
        reg b_prime;
        reg signed [5:0] b_prime_ext;
        reg signed [5:0] a_adj;
        begin
            b_prime = b[0];
            b_prime_ext = $signed({5'b00000, b_prime});
            a_adj = a - (b - b_prime_ext);
            reduce_real_w1 = a_adj[1:0];
        end
    endfunction

    function reduce_real_w2;
        input signed [5:0] a;
        input signed [5:0] b;
        reg b_prime;
        reg signed [5:0] b_prime_ext;
        reg signed [5:0] a_adj;
        begin
            b_prime = b[0];
            b_prime_ext = $signed({5'b00000, b_prime});
            a_adj = a - (b - b_prime_ext);
            reduce_real_w2 = a_adj[0];
        end
    endfunction

    assign r0_q = round_delta(noisy_q_flat[(0*Q_WIDTH)+:Q_WIDTH]);
    assign i0_q = round_delta(noisy_q_flat[(1*Q_WIDTH)+:Q_WIDTH]);
    assign r1_q = round_delta(noisy_q_flat[(2*Q_WIDTH)+:Q_WIDTH]);
    assign i1_q = round_delta(noisy_q_flat[(3*Q_WIDTH)+:Q_WIDTH]);
    assign r2_q = round_delta(noisy_q_flat[(4*Q_WIDTH)+:Q_WIDTH]);
    assign i2_q = round_delta(noisy_q_flat[(5*Q_WIDTH)+:Q_WIDTH]);
    assign r3_q = round_delta(noisy_q_flat[(6*Q_WIDTH)+:Q_WIDTH]);
    assign i3_q = round_delta(noisy_q_flat[(7*Q_WIDTH)+:Q_WIDTH]);

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

    assign s0_re = $signed({4'b0000, y0_re});
    assign s0_im = $signed({4'b0000, y0_im});
    assign s1_re = $signed({4'b0000, y1_re});
    assign s1_im = $signed({4'b0000, y1_im});
    assign s2_re = $signed({4'b0000, y2_re});
    assign s2_im = $signed({4'b0000, y2_im});
    assign s3_re = $signed({4'b0000, y3_re});
    assign s3_im = $signed({4'b0000, y3_im});

    assign a0_re = s0_re;
    assign a0_im = s0_im;
    assign a1_re = s1_re;
    assign a1_im = s1_im;
    assign a2_re = half_exact_signed((s2_re - s0_re) + (s2_im - s0_im));
    assign a2_im = half_exact_signed((s2_im - s0_im) - (s2_re - s0_re));
    assign a3_re = half_exact_signed((s3_re - s1_re) + (s3_im - s1_im));
    assign a3_im = half_exact_signed((s3_im - s1_im) - (s3_re - s1_re));

    assign raw0_re = a0_re;
    assign raw0_im = a0_im;
    assign raw1_re = half_exact_signed((a1_re - a0_re) + (a1_im - a0_im));
    assign raw1_im = half_exact_signed((a1_im - a0_im) - (a1_re - a0_re));
    assign raw2_re = a2_re;
    assign raw2_im = a2_im;
    assign raw3_re = half_exact_signed((a3_re - a2_re) + (a3_im - a2_im));
    assign raw3_im = half_exact_signed((a3_im - a2_im) - (a3_re - a2_re));

    assign v0_im_bits = mod4_signed(raw0_im);
    assign v0_re_bits = reduce_real_w0(raw0_re, raw0_im);
    assign v1_im_bits = raw1_im[0];
    assign v1_re_bits = reduce_real_w1(raw1_re, raw1_im);
    assign v2_im_bits = raw2_im[0];
    assign v2_re_bits = reduce_real_w1(raw2_re, raw2_im);
    assign v3_im_bits = raw3_im[0];
    assign v3_re_bits = reduce_real_w2(raw3_re, raw3_im);

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
