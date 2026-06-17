`timescale 1ns/1ps

module tb_scloud_msgfunc_bw8_cbd_demo;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam ETA     = 7;

    reg  [11:0]                msg_in;
    reg  [(8*2*ETA)-1:0]       cbd_rnd_bits;
    wire [(8*Q_WIDTH)-1:0]     noise_q_flat;
    wire [(8*Q_WIDTH)-1:0]     enc_q_flat;
    wire [(8*Q_WIDTH)-1:0]     noisy_q_flat;
    wire [(8*Q_WIDTH)-1:0]     rounded_q_flat;
    wire [11:0]                msg_out;

    integer error_count;

    scloud_msgfunc_bw8_cbd_demo #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU),
        .ETA    (ETA)
    ) dut (
        .msg_in        (msg_in),
        .cbd_rnd_bits  (cbd_rnd_bits),
        .noise_q_flat  (noise_q_flat),
        .enc_q_flat    (enc_q_flat),
        .noisy_q_flat  (noisy_q_flat),
        .rounded_q_flat(rounded_q_flat),
        .msg_out       (msg_out)
    );

    task check_case;
        input [11:0] msg_value;
        input [(8*2*ETA)-1:0] rnd_value;
        begin
            msg_in = msg_value;
            cbd_rnd_bits = rnd_value;
            #1;
            if (msg_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL msg=%h out=%h rnd=%h noise=%h enc=%h noisy=%h rounded=%h",
                         msg_value, msg_out, rnd_value, noise_q_flat, enc_q_flat, noisy_q_flat, rounded_q_flat);
            end else begin
                $display("PASS msg=%h out=%h noise=%h", msg_value, msg_out, noise_q_flat);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_scloud_msgfunc_bw8_cbd_demo.vcd");
        $dumpvars(0, tb_scloud_msgfunc_bw8_cbd_demo);

        error_count = 0;
        msg_in = 12'h000;
        cbd_rnd_bits = {112{1'b0}};
        #5;

        check_case(12'h000, 112'h0000000000000000000000000000);
        check_case(12'h001, 112'h0123456789abcdef0123456789ab);
        check_case(12'h040, 112'h0f0f0f0f0f0f0f0f0f0f0f0f0f0f);
        check_case(12'h120, 112'h00ff11ee22dd33cc44bb55aa6699);
        check_case(12'h248, 112'h13579bdf2468ace013579bdf2468);
        check_case(12'h248, 112'hffffffffffffffffffffffffffff);

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_bw8_cbd_demo");
        end else begin
            $display("TB_FAIL scloud_msgfunc_bw8_cbd_demo errors=%0d", error_count);
        end
        $finish;
    end

endmodule
