`timescale 1ns/1ps

module tb_scloud_phi_decode_seq;

    localparam COMPLEX_N = 16;
    localparam TAU3_WIDTH = 7;
    localparam TAU4_WIDTH = 8;
    localparam CASES = 200;

    reg clk;
    reg rst_n;
    reg start;
    reg [(2*COMPLEX_N*TAU3_WIDTH)-1:0] label_tau3_in;
    reg [(2*COMPLEX_N*TAU4_WIDTH)-1:0] label_tau4_in;

    wire tau3_ready;
    wire tau4_ready;
    wire tau3_done;
    wire tau4_done;
    wire [(2*COMPLEX_N*TAU3_WIDTH)-1:0] tau3_out;
    wire [(2*COMPLEX_N*TAU4_WIDTH)-1:0] tau4_out;
    wire [(2*COMPLEX_N*TAU3_WIDTH)-1:0] tau3_reference;
    wire [(2*COMPLEX_N*TAU4_WIDTH)-1:0] tau4_reference;

    integer test_index;
    integer word_index;
    integer error_count;
    integer cycle_count;

    always #5 clk = ~clk;

    scloud_msgfunc_phi_decode #(
        .COMPLEX_N  (COMPLEX_N),
        .LABEL_WIDTH(TAU3_WIDTH)
    ) u_tau3_reference (
        .label_in_flat (label_tau3_in),
        .label_out_flat(tau3_reference)
    );

    scloud_msgfunc_phi_decode #(
        .COMPLEX_N  (COMPLEX_N),
        .LABEL_WIDTH(TAU4_WIDTH)
    ) u_tau4_reference (
        .label_in_flat (label_tau4_in),
        .label_out_flat(tau4_reference)
    );

    scloud_msgfunc_phi_decode_seq #(
        .COMPLEX_N  (COMPLEX_N),
        .LABEL_WIDTH(TAU3_WIDTH)
    ) u_tau3_dut (
        .label_in_flat (label_tau3_in),
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .start_ready   (tau3_ready),
        .busy          (),
        .done          (tau3_done),
        .label_out_flat(tau3_out)
    );

    scloud_msgfunc_phi_decode_seq #(
        .COMPLEX_N  (COMPLEX_N),
        .LABEL_WIDTH(TAU4_WIDTH)
    ) u_tau4_dut (
        .label_in_flat (label_tau4_in),
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .start_ready   (tau4_ready),
        .busy          (),
        .done          (tau4_done),
        .label_out_flat(tau4_out)
    );

    task run_case;
        begin
            while (!(tau3_ready && tau4_ready)) @(posedge clk);
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            cycle_count = 0;
            while (!(tau3_done && tau4_done) && cycle_count < 16) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end

            if (!(tau3_done && tau4_done)) begin
                error_count = error_count + 1;
                $display("FAIL timeout case=%0d", test_index);
            end else begin
                if (tau3_out !== tau3_reference) begin
                    error_count = error_count + 1;
                    $display("FAIL tau3 case=%0d got=%h expected=%h",
                             test_index, tau3_out, tau3_reference);
                end
                if (tau4_out !== tau4_reference) begin
                    error_count = error_count + 1;
                    $display("FAIL tau4 case=%0d got=%h expected=%h",
                             test_index, tau4_out, tau4_reference);
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        label_tau3_in = {(2*COMPLEX_N*TAU3_WIDTH){1'b0}};
        label_tau4_in = {(2*COMPLEX_N*TAU4_WIDTH){1'b0}};
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (test_index = 0; test_index < CASES; test_index = test_index + 1) begin
            for (word_index = 0; word_index < 8; word_index = word_index + 1) begin
                label_tau3_in[(word_index*28)+:28] = $random;
                label_tau4_in[(word_index*32)+:32] = $random;
            end
            run_case;
        end

        if (error_count == 0)
            $display("TB_PASS scloud_phi_decode_seq cases=%0d", CASES);
        else
            $display("TB_FAIL scloud_phi_decode_seq errors=%0d", error_count);
        $finish;
    end

endmodule
