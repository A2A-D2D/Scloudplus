`timescale 1ns/1ps

module scloud_cbd_noise8
#(
    parameter Q_WIDTH = 10,
    parameter ETA     = 7
)
(
    input  wire [(8*2*ETA)-1:0]     rnd_bits,
    output wire [(8*Q_WIDTH)-1:0]   noise_q_flat
);

    function [3:0] popcount_eta;
        input [ETA-1:0] bits;
        integer i;
        begin
            popcount_eta = 4'd0;
            for (i = 0; i < ETA; i = i + 1) begin
                popcount_eta = popcount_eta + bits[i];
            end
        end
    endfunction

    function [Q_WIDTH-1:0] cbd_one;
        input [(2*ETA)-1:0] bits;
        reg signed [5:0] diff;
        begin
            diff = $signed({2'b00, popcount_eta(bits[ETA-1:0])})
                 - $signed({2'b00, popcount_eta(bits[(2*ETA)-1:ETA])});
            cbd_one = {{(Q_WIDTH-6){diff[5]}}, diff};
        end
    endfunction

    assign noise_q_flat[(0*Q_WIDTH)+:Q_WIDTH] = cbd_one(rnd_bits[(0*2*ETA)+:(2*ETA)]);
    assign noise_q_flat[(1*Q_WIDTH)+:Q_WIDTH] = cbd_one(rnd_bits[(1*2*ETA)+:(2*ETA)]);
    assign noise_q_flat[(2*Q_WIDTH)+:Q_WIDTH] = cbd_one(rnd_bits[(2*2*ETA)+:(2*ETA)]);
    assign noise_q_flat[(3*Q_WIDTH)+:Q_WIDTH] = cbd_one(rnd_bits[(3*2*ETA)+:(2*ETA)]);
    assign noise_q_flat[(4*Q_WIDTH)+:Q_WIDTH] = cbd_one(rnd_bits[(4*2*ETA)+:(2*ETA)]);
    assign noise_q_flat[(5*Q_WIDTH)+:Q_WIDTH] = cbd_one(rnd_bits[(5*2*ETA)+:(2*ETA)]);
    assign noise_q_flat[(6*Q_WIDTH)+:Q_WIDTH] = cbd_one(rnd_bits[(6*2*ETA)+:(2*ETA)]);
    assign noise_q_flat[(7*Q_WIDTH)+:Q_WIDTH] = cbd_one(rnd_bits[(7*2*ETA)+:(2*ETA)]);

endmodule
