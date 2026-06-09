`timescale 1ns/1ps

module scloud_msgdec_bw32_block
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [(32*Q_WIDTH)-1:0] noisy_q_flat,
    output reg  [31:0]             msg_block,
    output wire [(32*Q_WIDTH)-1:0] rounded_q_flat
);

    localparam DELTA_SHIFT = Q_WIDTH - TAU;

    integer idx;
    integer base;
    reg [5:0] re [0:15];
    reg [5:0] im [0:15];
    reg [5:0] raw_re [0:15];
    reg [5:0] raw_im [0:15];
    reg [5:0] b_prime;
    reg [5:0] a_adj;
    reg [6:0] dr;
    reg [6:0] di;
    reg [6:0] b_re_sum;
    reg [6:0] b_im_sum;

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (TAU),
        .COMPLEX_N(16)
    ) u_bdd (
        .target_flat (noisy_q_flat),
        .decoded_flat(rounded_q_flat)
    );

    always @(rounded_q_flat) begin
        for (idx = 0; idx < 16; idx = idx + 1) begin
            re[idx] = {4'b0000, rounded_q_flat[((2*idx+0)*Q_WIDTH)+DELTA_SHIFT+:TAU]};
            im[idx] = {4'b0000, rounded_q_flat[((2*idx+1)*Q_WIDTH)+DELTA_SHIFT+:TAU]};
        end

        for (idx = 0; idx < 8; idx = idx + 1) begin
            dr = {re[8+idx][5], re[8+idx]} - {re[idx][5], re[idx]};
            di = {im[8+idx][5], im[8+idx]} - {im[idx][5], im[idx]};
            b_re_sum = dr + di;
            b_im_sum = di - dr;
            re[8+idx] = {b_re_sum[6], b_re_sum[6:1]};
            im[8+idx] = {b_im_sum[6], b_im_sum[6:1]};
        end

        for (base = 0; base < 16; base = base + 8) begin
            for (idx = 0; idx < 4; idx = idx + 1) begin
                dr = {re[base+4+idx][5], re[base+4+idx]} - {re[base+idx][5], re[base+idx]};
                di = {im[base+4+idx][5], im[base+4+idx]} - {im[base+idx][5], im[base+idx]};
                b_re_sum = dr + di;
                b_im_sum = di - dr;
                re[base+4+idx] = {b_re_sum[6], b_re_sum[6:1]};
                im[base+4+idx] = {b_im_sum[6], b_im_sum[6:1]};
            end
        end

        for (base = 0; base < 16; base = base + 4) begin
            dr = {re[base+2][5], re[base+2]} - {re[base][5], re[base]};
            di = {im[base+2][5], im[base+2]} - {im[base][5], im[base]};
            b_re_sum = dr + di;
            b_im_sum = di - dr;
            re[base+2] = {b_re_sum[6], b_re_sum[6:1]};
            im[base+2] = {b_im_sum[6], b_im_sum[6:1]};
            dr = {re[base+3][5], re[base+3]} - {re[base+1][5], re[base+1]};
            di = {im[base+3][5], im[base+3]} - {im[base+1][5], im[base+1]};
            b_re_sum = dr + di;
            b_im_sum = di - dr;
            re[base+3] = {b_re_sum[6], b_re_sum[6:1]};
            im[base+3] = {b_im_sum[6], b_im_sum[6:1]};
        end

        for (base = 0; base < 16; base = base + 2) begin
            dr = {re[base+1][5], re[base+1]} - {re[base][5], re[base]};
            di = {im[base+1][5], im[base+1]} - {im[base][5], im[base]};
            b_re_sum = dr + di;
            b_im_sum = di - dr;
            re[base+1] = {b_re_sum[6], b_re_sum[6:1]};
            im[base+1] = {b_im_sum[6], b_im_sum[6:1]};
        end

        for (idx = 0; idx < 16; idx = idx + 1) begin
            raw_re[idx] = re[idx];
            raw_im[idx] = im[idx];
        end

        msg_block = 32'b00000000000000000000000000000000;

        b_prime = {4'b0000, raw_im[0][1:0]}; a_adj = raw_re[0] - raw_im[0] + b_prime;
        msg_block[31:30] = a_adj[1:0]; msg_block[29:28] = raw_im[0][1:0];

        b_prime = {5'b00000, raw_im[1][0]}; a_adj = raw_re[1] - raw_im[1] + b_prime;
        msg_block[27:26] = a_adj[1:0]; msg_block[25] = raw_im[1][0];

        b_prime = {5'b00000, raw_im[2][0]}; a_adj = raw_re[2] - raw_im[2] + b_prime;
        msg_block[24:23] = a_adj[1:0]; msg_block[22] = raw_im[2][0];

        b_prime = {5'b00000, raw_im[3][0]}; a_adj = raw_re[3] - raw_im[3] + b_prime;
        msg_block[21] = a_adj[0]; msg_block[20] = raw_im[3][0];

        b_prime = {5'b00000, raw_im[4][0]}; a_adj = raw_re[4] - raw_im[4] + b_prime;
        msg_block[19:18] = a_adj[1:0]; msg_block[17] = raw_im[4][0];

        b_prime = {5'b00000, raw_im[5][0]}; a_adj = raw_re[5] - raw_im[5] + b_prime;
        msg_block[16] = a_adj[0]; msg_block[15] = raw_im[5][0];

        b_prime = {5'b00000, raw_im[6][0]}; a_adj = raw_re[6] - raw_im[6] + b_prime;
        msg_block[14] = a_adj[0]; msg_block[13] = raw_im[6][0];

        b_prime = 6'b000000; a_adj = raw_re[7] - raw_im[7] + b_prime;
        msg_block[12] = a_adj[0];

        b_prime = {5'b00000, raw_im[8][0]}; a_adj = raw_re[8] - raw_im[8] + b_prime;
        msg_block[11:10] = a_adj[1:0]; msg_block[9] = raw_im[8][0];

        b_prime = {5'b00000, raw_im[9][0]}; a_adj = raw_re[9] - raw_im[9] + b_prime;
        msg_block[8] = a_adj[0]; msg_block[7] = raw_im[9][0];

        b_prime = {5'b00000, raw_im[10][0]}; a_adj = raw_re[10] - raw_im[10] + b_prime;
        msg_block[6] = a_adj[0]; msg_block[5] = raw_im[10][0];

        b_prime = 6'b000000; a_adj = raw_re[11] - raw_im[11] + b_prime;
        msg_block[4] = a_adj[0];

        b_prime = {5'b00000, raw_im[12][0]}; a_adj = raw_re[12] - raw_im[12] + b_prime;
        msg_block[3] = a_adj[0]; msg_block[2] = raw_im[12][0];

        b_prime = 6'b000000; a_adj = raw_re[13] - raw_im[13] + b_prime;
        msg_block[1] = a_adj[0];

        b_prime = 6'b000000; a_adj = raw_re[14] - raw_im[14] + b_prime;
        msg_block[0] = a_adj[0];
    end

endmodule
