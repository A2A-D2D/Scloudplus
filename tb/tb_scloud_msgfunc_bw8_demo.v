`timescale 1ns/1ps

module tb_scloud_msgfunc_bw8_demo;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;

    reg  [11:0]                msg_in;
    reg  [(8*Q_WIDTH)-1:0]     noise_q_flat;
    wire [(8*Q_WIDTH)-1:0]     enc_q_flat;
    wire [(8*Q_WIDTH)-1:0]     noisy_q_flat;
    wire [(8*Q_WIDTH)-1:0]     rounded_q_flat;
    wire [11:0]                msg_out;

    integer error_count;
    integer idx;

    scloud_msgfunc_bw8_demo #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) dut (
        .msg_in        (msg_in),
        .noise_q_flat  (noise_q_flat),
        .enc_q_flat    (enc_q_flat),
        .noisy_q_flat  (noisy_q_flat),
        .rounded_q_flat(rounded_q_flat),
        .msg_out       (msg_out)
    );

    function [(8*Q_WIDTH)-1:0] pack_noise;
        input signed [Q_WIDTH-1:0] n0;
        input signed [Q_WIDTH-1:0] n1;
        input signed [Q_WIDTH-1:0] n2;
        input signed [Q_WIDTH-1:0] n3;
        input signed [Q_WIDTH-1:0] n4;
        input signed [Q_WIDTH-1:0] n5;
        input signed [Q_WIDTH-1:0] n6;
        input signed [Q_WIDTH-1:0] n7;
        begin
            pack_noise = {
                n7[Q_WIDTH-1:0],
                n6[Q_WIDTH-1:0],
                n5[Q_WIDTH-1:0],
                n4[Q_WIDTH-1:0],
                n3[Q_WIDTH-1:0],
                n2[Q_WIDTH-1:0],
                n1[Q_WIDTH-1:0],
                n0[Q_WIDTH-1:0]
            };
        end
    endfunction

    task check_case;
        input [11:0] msg_value;
        input [(8*Q_WIDTH)-1:0] noise_value;
        begin
            msg_in = msg_value;
            noise_q_flat = noise_value;
            #1;
            if (msg_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL msg=%h out=%h enc=%h noisy=%h rounded=%h",
                         msg_value, msg_out, enc_q_flat, noisy_q_flat, rounded_q_flat);
            end else begin
                $display("PASS msg=%h out=%h enc=%h", msg_value, msg_out, enc_q_flat);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_scloud_msgfunc_bw8_demo.vcd");
        $dumpvars(0, tb_scloud_msgfunc_bw8_demo);

        error_count = 0;
        msg_in = 12'h000;
        noise_q_flat = {80{1'b0}};
        #5;

        check_case(12'h000, {80{1'b0}});
        check_case(12'h001, {80{1'b0}});
        check_case(12'h040, {80{1'b0}});
        check_case(12'h120, {80{1'b0}});
        check_case(12'h248, {80{1'b0}});
        check_case(12'h000, pack_noise(10'sd17, -10'sd21, 10'sd31, -10'sd44, 10'sd63, -10'sd70, 10'sd11, -10'sd9));
        check_case(12'h001, pack_noise(-10'sd8, 10'sd9, -10'sd13, 10'sd15, -10'sd17, 10'sd19, -10'sd23, 10'sd25));
        check_case(12'h120, pack_noise(10'sd64, 10'sd32, -10'sd32, -10'sd64, 10'sd7, -10'sd7, 10'sd99, -10'sd99));

        for (idx = 0; idx < 4096; idx = idx + 1) begin
            msg_in = idx[11:0];
            noise_q_flat = {80{1'b0}};
            #1;
            if (msg_out !== idx[11:0]) begin
                error_count = error_count + 1;
                $display("FAIL_EXHAUSTIVE msg=%h out=%h enc=%h rounded=%h",
                         idx[11:0], msg_out, enc_q_flat, rounded_q_flat);
            end
        end

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_bw8_demo");
        end else begin
            $display("TB_FAIL scloud_msgfunc_bw8_demo errors=%0d", error_count);
        end
        $finish;
    end

endmodule
