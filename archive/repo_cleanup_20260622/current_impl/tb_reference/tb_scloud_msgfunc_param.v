`timescale 1ns/1ps

module tb_scloud_msgfunc_param;

    localparam Q_WIDTH = 12;

    localparam TAU3          = 3;
    localparam TAU3_MSG_BITS = 64;
    localparam TAU3_Q_BITS   = 32 * Q_WIDTH;

    localparam TAU4          = 4;
    localparam TAU4_MSG_BITS = 96;
    localparam TAU4_Q_BITS   = 32 * Q_WIDTH;

    reg  clk;
    reg  rst_n;
    reg  start_tau3;
    reg  start_tau4;
    wire start_ready_tau3;
    wire start_ready_tau4;
    wire done_tau3;
    wire done_tau4;

    reg  [TAU3_MSG_BITS-1:0] msg_tau3_in;
    reg  [TAU4_MSG_BITS-1:0] msg_tau4_in;
    reg  [TAU3_Q_BITS-1:0]   noise_tau3_flat;
    reg  [TAU4_Q_BITS-1:0]   noise_tau4_flat;

    wire [TAU3_Q_BITS-1:0]   enc_tau3_flat;
    wire [TAU4_Q_BITS-1:0]   enc_tau4_flat;
    wire [TAU3_Q_BITS-1:0]   noisy_tau3_flat;
    wire [TAU4_Q_BITS-1:0]   noisy_tau4_flat;
    wire [TAU3_Q_BITS-1:0]   rounded_tau3_flat;
    wire [TAU4_Q_BITS-1:0]   rounded_tau4_flat;
    wire [TAU3_MSG_BITS-1:0] msg_tau3_out;
    wire [TAU4_MSG_BITS-1:0] msg_tau4_out;

    integer error_count;
    integer idx;
    integer cycle;

    // clock: 10ns period
    always #5 clk = ~clk;

    // timeout watchdog: 100k cycles max
    initial begin
        cycle = 0;
        forever begin
            @(posedge clk);
            cycle = cycle + 1;
            if (cycle > 100000) begin
                $display("TB_TIMEOUT at cycle %0d", cycle);
                $finish;
            end
        end
    end

    scloud_msgfunc_param #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU3),
        .LABEL_WIDTH  (TAU3 + 4),
        .MSG_WIDTH    (TAU3_MSG_BITS)
    ) dut_tau3 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start_tau3),
        .start_ready     (start_ready_tau3),
        .done            (done_tau3),
        .msg_in          (msg_tau3_in),
        .noise_q_flat    (noise_tau3_flat),
        .enc_q_flat      (enc_tau3_flat),
        .noisy_q_flat    (noisy_tau3_flat),
        .rounded_q_flat  (rounded_tau3_flat),
        .msg_out         (msg_tau3_out)
    );

    scloud_msgfunc_param #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU4),
        .LABEL_WIDTH  (TAU4 + 4),
        .MSG_WIDTH    (TAU4_MSG_BITS)
    ) dut_tau4 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start_tau4),
        .start_ready     (start_ready_tau4),
        .done            (done_tau4),
        .msg_in          (msg_tau4_in),
        .noise_q_flat    (noise_tau4_flat),
        .enc_q_flat      (enc_tau4_flat),
        .noisy_q_flat    (noisy_tau4_flat),
        .rounded_q_flat  (rounded_tau4_flat),
        .msg_out         (msg_tau4_out)
    );

    // ── handshake helper ──
    task automatic wait_done_tau3;
        begin
            @(posedge clk);
            start_tau3 <= 1'b1;
            @(posedge clk);          // hold start=1 for one full cycle
            start_tau3 <= 1'b0;
            while (!done_tau3) @(posedge clk);
            @(posedge clk);          // output settling
        end
    endtask

    task automatic wait_done_tau4;
        begin
            @(posedge clk);
            start_tau4 <= 1'b1;
            @(posedge clk);
            start_tau4 <= 1'b0;
            while (!done_tau4) @(posedge clk);
            @(posedge clk);
        end
    endtask

    task clear_noise;
        begin
            noise_tau3_flat = {TAU3_Q_BITS{1'b0}};
            noise_tau4_flat = {TAU4_Q_BITS{1'b0}};
        end
    endtask

    task set_noise_tau3;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            noise_tau3_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_tc;
        end
    endtask

    task set_noise_tau4;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            noise_tau4_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_tc;
        end
    endtask

    task check_tau3;
        input [TAU3_MSG_BITS-1:0] msg_value;
        begin
            msg_tau3_in <= msg_value;
            wait_done_tau3;
            if (msg_tau3_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL tau3 msg=%h out=%h", msg_value, msg_tau3_out);
            end else begin
                $display("OK   tau3 msg=%h", msg_value);
            end
        end
    endtask

    task check_tau4;
        input [TAU4_MSG_BITS-1:0] msg_value;
        begin
            msg_tau4_in <= msg_value;
            wait_done_tau4;
            if (msg_tau4_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL tau4 msg=%h out=%h", msg_value, msg_tau4_out);
            end else begin
                $display("OK   tau4 msg=%h", msg_value);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_scloud_msgfunc_param.vcd");
        $dumpvars(0, tb_scloud_msgfunc_param);

        clk        = 1'b0;
        rst_n      = 1'b0;
        start_tau3 = 1'b0;
        start_tau4 = 1'b0;
        error_count = 0;
        msg_tau3_in = {TAU3_MSG_BITS{1'b0}};
        msg_tau4_in = {TAU4_MSG_BITS{1'b0}};
        clear_noise;

        // reset
        $display("TB_START scloud_msgfunc_param (clocked BDD)");
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);
        $display("reset done, starting tests...");

        // ── tau=3 zero-noise roundtrip ──
        $display("=== tau=3 zero-noise ===");
        check_tau3(64'h0000000000000000);
        check_tau3(64'h0000000000000001);
        check_tau3(64'h0123456789abcdef);
        check_tau3(64'hfedcba9876543210);
        check_tau3(64'hffffffffffffffff);
        check_tau3(64'h8000000000000000);
        check_tau3(64'ha5a55a5ac3c33c3c);
        check_tau3(64'hdeadbeefcafebabe);

        // ── tau=4 zero-noise roundtrip ──
        $display("=== tau=4 zero-noise ===");
        check_tau4(96'h000000000000000000000000);
        check_tau4(96'h000000000000000000000001);
        check_tau4(96'h0123456789abcdeffedcba98);
        check_tau4(96'hfedcba987654321001234567);
        check_tau4(96'hffffffffffffffffffffffff);
        check_tau4(96'h800000000000000000000000);

        // ── tau=3 with noise ──
        $display("=== tau=3 noise tests ===");
        clear_noise;
        set_noise_tau3(0,  12'd13);
        set_noise_tau3(1,  12'hff5);
        set_noise_tau3(7,  12'd41);
        set_noise_tau3(15, 12'hfeb);
        set_noise_tau3(18, 12'd43);
        set_noise_tau3(31, 12'hff1);
        check_tau3(64'h13579bdffdb97531);
        check_tau3(64'ha5a55a5ac3c33c3c);

        clear_noise;
        set_noise_tau3(0,  12'd13);
        set_noise_tau3(3,  12'd29);
        set_noise_tau3(7,  12'd41);
        set_noise_tau3(12, 12'd35);
        set_noise_tau3(19, 12'hfd3);
        set_noise_tau3(25, 12'hfdf);
        check_tau3(64'hc001d00d00000001);
        check_tau3(64'h00000000deadbeef);

        // ── tau=4 with noise ──
        $display("=== tau=4 noise tests ===");
        clear_noise;
        set_noise_tau4(0,  12'd13);
        set_noise_tau4(1,  12'hff5);
        set_noise_tau4(7,  12'd41);
        set_noise_tau4(15, 12'hfeb);
        set_noise_tau4(18, 12'd43);
        set_noise_tau4(31, 12'hff1);
        check_tau4(96'h13579bdffdb97531a5a55a5a);
        check_tau4(96'hc001d00d0123456789abcdef);

        // ── random vectors ──
        $display("=== random spot checks ===");
        clear_noise;
        for (idx = 0; idx < 8; idx = idx + 1) begin
            check_tau3((idx * 64'h0011223344556677) ^ {32'h55aa0000, idx[31:0]});
            check_tau4((idx * 96'h000102030405060708090a0b) ^
                       {32'hf00d0000, idx[31:0], 32'h0badcafe});
        end

        // ── result ──
        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_param cases=%0d", 33);
        end else begin
            $display("TB_FAIL scloud_msgfunc_param errors=%0d", error_count);
        end
        $finish;
    end

endmodule
