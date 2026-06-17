`timescale 1ns/1ps

module tb_scloud_bdd32_seq_smoke;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam COORDS  = 32;

    reg                         clk;
    reg                         rst_n;
    reg                         start;
    reg  [(COORDS*Q_WIDTH)-1:0] target_flat;
    wire                        start_ready;
    wire                        busy;
    wire                        done;
    wire [(COORDS*Q_WIDTH)-1:0] decoded_flat;

    integer wait_cycles;
    integer error_count;

    scloud_bdd32_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_dut (
        .target_flat (target_flat),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .start_ready (start_ready),
        .busy        (busy),
        .done        (done),
        .decoded_flat(decoded_flat)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        target_flat = 320'h3c50ff94197f60337d1ff8c1b3cd0b34d2b7e605bad13f6c23001f745cef8a5fbc1ce1c76f503600;
        wait_cycles = 0;
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        @(posedge clk);
        if (!start_ready) begin
            error_count = error_count + 1;
            $display("FAIL_NOT_READY");
        end

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!done && wait_cycles < 200) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (!done) begin
            error_count = error_count + 1;
            $display("FAIL_TIMEOUT busy=%b ready=%b", busy, start_ready);
        end else if (^decoded_flat === 1'bx) begin
            error_count = error_count + 1;
            $display("FAIL_X decoded=%h", decoded_flat);
        end else begin
            $display("PASS done_cycles=%0d decoded=%h", wait_cycles, decoded_flat);
        end

        if (error_count == 0) begin
            $display("TB_PASS scloud_bdd32_seq_smoke");
        end else begin
            $display("TB_FAIL scloud_bdd32_seq_smoke errors=%0d", error_count);
        end
        $finish;
    end

endmodule
