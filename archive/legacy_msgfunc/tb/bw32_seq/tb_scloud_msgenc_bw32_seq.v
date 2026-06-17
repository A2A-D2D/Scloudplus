`timescale 1ns/1ps

module tb_scloud_msgenc_bw32_seq;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;

    reg                         clk;
    reg                         rst_n;
    reg                         start;
    reg  [31:0]                 msg_block;
    wire                        start_ready;
    wire                        busy;
    wire                        done;
    wire [(32*Q_WIDTH)-1:0]     code_q_seq;
    wire [(32*Q_WIDTH)-1:0]     code_q_ref;

    integer error_count;
    integer pass_count;
    integer cycle_count;

    scloud_msgenc_bw32_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .msg_block   (msg_block),
        .start_ready (start_ready),
        .busy        (busy),
        .done        (done),
        .code_q_flat (code_q_seq)
    );

    scloud_msgenc_bw32_block #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_ref (
        .msg_block   (msg_block),
        .code_q_flat (code_q_ref)
    );

    always #5 clk = ~clk;

    task run_case;
        input [31:0] msg_value;
        begin
            @(negedge clk);
            msg_block <= msg_value;
            start     <= 1'b1;

            @(negedge clk);
            start <= 1'b0;

            cycle_count = 0;
            while (!done && cycle_count < 50) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end

            if (!done) begin
                $display("TB_ERROR timeout msg=%08x", msg_value);
                error_count = error_count + 1;
            end else if (code_q_seq !== code_q_ref) begin
                $display("TB_ERROR mismatch msg=%08x", msg_value);
                $display("  seq=%h", code_q_seq);
                $display("  ref=%h", code_q_ref);
                error_count = error_count + 1;
            end else begin
                pass_count = pass_count + 1;
                $display("TB_INFO pass msg=%08x cycles=%0d", msg_value, cycle_count);
            end

            @(posedge clk);
        end
    endtask

    initial begin
        clk         = 1'b0;
        rst_n       = 1'b0;
        start       = 1'b0;
        msg_block   = 32'd0;
        error_count = 0;
        pass_count  = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        if (!start_ready || busy || done) begin
            $display("TB_ERROR bad idle handshake start_ready=%b busy=%b done=%b",
                     start_ready, busy, done);
            error_count = error_count + 1;
        end

        run_case(32'h00000000);
        run_case(32'hffffffff);
        run_case(32'h12345678);
        run_case(32'hdeadbeef);
        run_case(32'ha5a55a5a);
        run_case(32'h55555555);

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgenc_bw32_seq cases=%0d", pass_count);
        end else begin
            $display("TB_FAIL scloud_msgenc_bw32_seq errors=%0d cases=%0d",
                     error_count, pass_count);
        end

        $finish;
    end

endmodule
