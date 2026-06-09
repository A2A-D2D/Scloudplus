`timescale 1ns/1ps

module scloud_msgenc_bw32_block
#(
    parameter Q_WIDTH = 10,
    parameter TAU     = 2
)
(
    input  wire [31:0]                 msg_block,
    output reg  [(32*Q_WIDTH)-1:0]     code_q_flat
);

    localparam DELTA_SHIFT = Q_WIDTH - TAU;

    integer idx;
    integer base;
    reg [5:0] re [0:15];
    reg [5:0] im [0:15];
    reg [5:0] next_re;
    reg [5:0] next_im;

    always @(msg_block) begin
        re[0]  = {4'b0000, msg_block[31:30]}; im[0]  = {4'b0000, msg_block[29:28]};
        re[1]  = {4'b0000, msg_block[27:26]}; im[1]  = {5'b00000, msg_block[25]};
        re[2]  = {4'b0000, msg_block[24:23]}; im[2]  = {5'b00000, msg_block[22]};
        re[3]  = {5'b00000, msg_block[21]};    im[3]  = {5'b00000, msg_block[20]};
        re[4]  = {4'b0000, msg_block[19:18]}; im[4]  = {5'b00000, msg_block[17]};
        re[5]  = {5'b00000, msg_block[16]};    im[5]  = {5'b00000, msg_block[15]};
        re[6]  = {5'b00000, msg_block[14]};    im[6]  = {5'b00000, msg_block[13]};
        re[7]  = {5'b00000, msg_block[12]};    im[7]  = 6'b000000;
        re[8]  = {4'b0000, msg_block[11:10]}; im[8]  = {5'b00000, msg_block[9]};
        re[9]  = {5'b00000, msg_block[8]};     im[9]  = {5'b00000, msg_block[7]};
        re[10] = {5'b00000, msg_block[6]};     im[10] = {5'b00000, msg_block[5]};
        re[11] = {5'b00000, msg_block[4]};     im[11] = 6'b000000;
        re[12] = {5'b00000, msg_block[3]};     im[12] = {5'b00000, msg_block[2]};
        re[13] = {5'b00000, msg_block[1]};     im[13] = 6'b000000;
        re[14] = {5'b00000, msg_block[0]};     im[14] = 6'b000000;
        re[15] = 6'b000000;                    im[15] = 6'b000000;

        for (base = 0; base < 16; base = base + 2) begin
            next_re = re[base] + re[base+1] - im[base+1];
            next_im = im[base] + re[base+1] + im[base+1];
            re[base+1] = next_re;
            im[base+1] = next_im;
        end

        for (base = 0; base < 16; base = base + 4) begin
            next_re = re[base] + re[base+2] - im[base+2];
            next_im = im[base] + re[base+2] + im[base+2];
            re[base+2] = next_re;
            im[base+2] = next_im;
            next_re = re[base+1] + re[base+3] - im[base+3];
            next_im = im[base+1] + re[base+3] + im[base+3];
            re[base+3] = next_re;
            im[base+3] = next_im;
        end

        for (base = 0; base < 16; base = base + 8) begin
            for (idx = 0; idx < 4; idx = idx + 1) begin
                next_re = re[base+idx] + re[base+4+idx] - im[base+4+idx];
                next_im = im[base+idx] + re[base+4+idx] + im[base+4+idx];
                re[base+4+idx] = next_re;
                im[base+4+idx] = next_im;
            end
        end

        for (idx = 0; idx < 8; idx = idx + 1) begin
            next_re = re[idx] + re[8+idx] - im[8+idx];
            next_im = im[idx] + re[8+idx] + im[8+idx];
            re[8+idx] = next_re;
            im[8+idx] = next_im;
        end

        code_q_flat = {32*Q_WIDTH{1'b0}};
        for (idx = 0; idx < 16; idx = idx + 1) begin
            code_q_flat[((2*idx+0)*Q_WIDTH)+:Q_WIDTH] =
                {{(Q_WIDTH-TAU){1'b0}}, re[idx][TAU-1:0]} << DELTA_SHIFT;
            code_q_flat[((2*idx+1)*Q_WIDTH)+:Q_WIDTH] =
                {{(Q_WIDTH-TAU){1'b0}}, im[idx][TAU-1:0]} << DELTA_SHIFT;
        end
    end

endmodule
