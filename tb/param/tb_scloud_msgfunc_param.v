`timescale 1ns/1ps

module tb_scloud_msgfunc_param;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;

    reg  [11:0] msg8_in;
    reg  [19:0] msg16_in;
    reg  [31:0] msg32_in;
    reg  [(8*Q_WIDTH)-1:0]  noise8_flat;
    reg  [(16*Q_WIDTH)-1:0] noise16_flat;
    reg  [(32*Q_WIDTH)-1:0] noise32_flat;

    wire [(8*Q_WIDTH)-1:0]  enc8_flat;
    wire [(16*Q_WIDTH)-1:0] enc16_flat;
    wire [(32*Q_WIDTH)-1:0] enc32_flat;
    wire [(8*Q_WIDTH)-1:0]  noisy8_flat;
    wire [(16*Q_WIDTH)-1:0] noisy16_flat;
    wire [(32*Q_WIDTH)-1:0] noisy32_flat;
    wire [(8*Q_WIDTH)-1:0]  rounded8_flat;
    wire [(16*Q_WIDTH)-1:0] rounded16_flat;
    wire [(32*Q_WIDTH)-1:0] rounded32_flat;
    wire [11:0] msg8_out;
    wire [19:0] msg16_out;
    wire [31:0] msg32_out;

    integer error_count;
    integer idx;

    scloud_msgfunc_param #(
        .COMPLEX_N    (4),
        .LOG_COMPLEX_N(2),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (4),
        .MSG_WIDTH    (12)
    ) dut_bw8 (
        .msg_in        (msg8_in),
        .noise_q_flat  (noise8_flat),
        .enc_q_flat    (enc8_flat),
        .noisy_q_flat  (noisy8_flat),
        .rounded_q_flat(rounded8_flat),
        .msg_out       (msg8_out)
    );

    scloud_msgfunc_param #(
        .COMPLEX_N    (8),
        .LOG_COMPLEX_N(3),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (5),
        .MSG_WIDTH    (20)
    ) dut_bw16 (
        .msg_in        (msg16_in),
        .noise_q_flat  (noise16_flat),
        .enc_q_flat    (enc16_flat),
        .noisy_q_flat  (noisy16_flat),
        .rounded_q_flat(rounded16_flat),
        .msg_out       (msg16_out)
    );

    scloud_msgfunc_param #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (6),
        .MSG_WIDTH    (32)
    ) dut_bw32 (
        .msg_in        (msg32_in),
        .noise_q_flat  (noise32_flat),
        .enc_q_flat    (enc32_flat),
        .noisy_q_flat  (noisy32_flat),
        .rounded_q_flat(rounded32_flat),
        .msg_out       (msg32_out)
    );

    task set_noise8;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            noise8_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_tc;
        end
    endtask

    task set_noise16;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            noise16_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_tc;
        end
    endtask

    task set_noise32;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            noise32_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_tc;
        end
    endtask

    task clear_noise;
        begin
            noise8_flat  = {8*Q_WIDTH{1'b0}};
            noise16_flat = {16*Q_WIDTH{1'b0}};
            noise32_flat = {32*Q_WIDTH{1'b0}};
        end
    endtask

    task check8;
        input [11:0] msg_value;
        begin
            msg8_in = msg_value;
            #1;
            if (msg8_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL BW8 msg=%h out=%h enc=%h rounded=%h",
                         msg_value, msg8_out, enc8_flat, rounded8_flat);
            end
        end
    endtask

    task check16;
        input [19:0] msg_value;
        begin
            msg16_in = msg_value;
            #1;
            if (msg16_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL BW16 msg=%h out=%h enc=%h rounded=%h",
                         msg_value, msg16_out, enc16_flat, rounded16_flat);
            end
        end
    endtask

    task check32;
        input [31:0] msg_value;
        begin
            msg32_in = msg_value;
            #1;
            if (msg32_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL BW32 msg=%h out=%h enc=%h rounded=%h",
                         msg_value, msg32_out, enc32_flat, rounded32_flat);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_scloud_msgfunc_param.vcd");
        $dumpvars(0, tb_scloud_msgfunc_param);

        error_count = 0;
        msg8_in = 12'h000;
        msg16_in = 20'h00000;
        msg32_in = 32'h00000000;
        clear_noise;
        #5;

        check8(12'h000);
        check8(12'h001);
        check8(12'habc);
        check8(12'hfff);

        check16(20'h00000);
        check16(20'h12345);
        check16(20'habcd0);
        check16(20'hfffff);

        check32(32'h00000000);
        check32(32'h00000001);
        check32(32'h12345678);
        check32(32'hdeadbeef);
        check32(32'hffffffff);

        clear_noise;
        set_noise8(0, 10'd13);
        set_noise8(1, 10'h3f5);
        set_noise8(5, 10'd31);
        set_noise8(7, 10'h3e8);
        check8(12'h5a3);
        check8(12'hc71);

        clear_noise;
        set_noise16(0, 10'd13);
        set_noise16(1, 10'h3f5);
        set_noise16(3, 10'd29);
        set_noise16(4, 10'h3e1);
        set_noise16(7, 10'd41);
        set_noise16(9, 10'h3ef);
        set_noise16(12, 10'd35);
        set_noise16(15, 10'h3eb);
        check16(20'h13579);
        check16(20'ha5a5a);

        clear_noise;
        set_noise32(0, 10'd13);
        set_noise32(1, 10'h3f5);
        set_noise32(3, 10'd29);
        set_noise32(4, 10'h3e1);
        set_noise32(7, 10'd41);
        set_noise32(9, 10'h3ef);
        set_noise32(12, 10'd35);
        set_noise32(15, 10'h3eb);
        set_noise32(18, 10'd43);
        set_noise32(19, 10'h3d3);
        set_noise32(24, 10'd31);
        set_noise32(25, 10'h3df);
        set_noise32(30, 10'd15);
        set_noise32(31, 10'h3f1);
        check32(32'h13579bdf);
        check32(32'ha5a55a5a);
        check32(32'hc001d00d);

        clear_noise;
        for (idx = 0; idx < 32; idx = idx + 1) begin
            check32((idx * 32'h00110203) ^ {idx[15:0], idx[15:0]});
        end

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_param");
        end else begin
            $display("TB_FAIL scloud_msgfunc_param errors=%0d", error_count);
        end
        $finish;
    end

endmodule
