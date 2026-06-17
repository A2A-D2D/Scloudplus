`timescale 1ns/1ps

module tb_scloud_msgfunc_bw16_demo;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;

    reg  [19:0]                 msg_in;
    reg  [(16*Q_WIDTH)-1:0]     noise_q_flat;
    wire [(16*Q_WIDTH)-1:0]     enc_q_flat;
    wire [(16*Q_WIDTH)-1:0]     noisy_q_flat;
    wire [(16*Q_WIDTH)-1:0]     rounded_q_flat;
    wire [19:0]                 msg_out;

    integer error_count;
    integer idx;

    scloud_msgfunc_bw16_demo #(
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

    task check_case;
        input [19:0] msg_value;
        input [(16*Q_WIDTH)-1:0] noise_value;
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

    function [(16*Q_WIDTH)-1:0] pack_noise;
        input [Q_WIDTH-1:0] n00; input [Q_WIDTH-1:0] n01;
        input [Q_WIDTH-1:0] n02; input [Q_WIDTH-1:0] n03;
        input [Q_WIDTH-1:0] n04; input [Q_WIDTH-1:0] n05;
        input [Q_WIDTH-1:0] n06; input [Q_WIDTH-1:0] n07;
        input [Q_WIDTH-1:0] n08; input [Q_WIDTH-1:0] n09;
        input [Q_WIDTH-1:0] n10; input [Q_WIDTH-1:0] n11;
        input [Q_WIDTH-1:0] n12; input [Q_WIDTH-1:0] n13;
        input [Q_WIDTH-1:0] n14; input [Q_WIDTH-1:0] n15;
        begin
            pack_noise = {
                n15, n14, n13, n12, n11, n10, n09, n08,
                n07, n06, n05, n04, n03, n02, n01, n00
            };
        end
    endfunction

    initial begin
        $dumpfile("tb_scloud_msgfunc_bw16_demo.vcd");
        $dumpvars(0, tb_scloud_msgfunc_bw16_demo);

        error_count = 0;
        msg_in = 20'h00000;
        noise_q_flat = {160{1'b0}};
        #5;

        check_case(20'h00000, {160{1'b0}});
        check_case(20'h00001, {160{1'b0}});
        check_case(20'h00020, {160{1'b0}});
        check_case(20'h12345, {160{1'b0}});
        check_case(20'habcde, {160{1'b0}});
        check_case(20'hfffff, {160{1'b0}});

        check_case(20'h12345, pack_noise(
            10'd17,  10'h3f1, 10'd31,  10'h3e8,
            10'd63,  10'h3dd, 10'd11,  10'h3f7,
            10'd45,  10'h3e2, 10'd75,  10'h3f0,
            10'd3,   10'h3fb, 10'd101, 10'h3d0
        ));

        for (idx = 0; idx < 1048576; idx = idx + 257) begin
            msg_in = idx[19:0];
            noise_q_flat = {160{1'b0}};
            #1;
            if (msg_out !== idx[19:0]) begin
                error_count = error_count + 1;
                $display("FAIL_SWEEP msg=%h out=%h enc=%h rounded=%h",
                         idx[19:0], msg_out, enc_q_flat, rounded_q_flat);
            end
        end

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_bw16_demo");
        end else begin
            $display("TB_FAIL scloud_msgfunc_bw16_demo errors=%0d", error_count);
        end
        $finish;
    end

endmodule
