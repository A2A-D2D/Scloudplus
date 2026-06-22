`timescale 1ns/1ps

module tb_scloud_bdd4_seq_rt;

    localparam Q_WIDTH = 12;
    localparam COORDS  = 4;
    localparam CASES   = 100;

    reg clk;
    reg rst_n;
    reg start;
    reg tau_sel;
    reg [(COORDS*Q_WIDTH)-1:0] target_flat;

    wire start_ready;
    wire done;
    wire [(COORDS*Q_WIDTH)-1:0] decoded_flat;
    wire [(COORDS*Q_WIDTH)-1:0] reference_tau3;
    wire [(COORDS*Q_WIDTH)-1:0] reference_tau4;

    integer test_index;
    integer coord_index;
    integer cycle_count;
    integer error_count;

    always #5 clk = ~clk;

    scloud_bdd4_seq_rt #(.Q_WIDTH(Q_WIDTH)) dut (
        .target_flat (target_flat),
        .tau_sel     (tau_sel),
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .start_ready (start_ready),
        .busy        (),
        .done        (done),
        .decoded_flat(decoded_flat)
    );

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (3),
        .COMPLEX_N(2)
    ) u_reference_tau3 (
        .target_flat (target_flat),
        .decoded_flat(reference_tau3)
    );

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (4),
        .COMPLEX_N(2)
    ) u_reference_tau4 (
        .target_flat (target_flat),
        .decoded_flat(reference_tau4)
    );

    task run_case;
        begin
            while (!start_ready) @(posedge clk);
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            cycle_count = 0;
            while (!done && cycle_count < 32) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end

            if (!done) begin
                error_count = error_count + 1;
                $display("FAIL timeout case=%0d tau=%0d", test_index,
                         tau_sel ? 4 : 3);
            end else if (decoded_flat !==
                         (tau_sel ? reference_tau4 : reference_tau3)) begin
                error_count = error_count + 1;
                $display("FAIL mismatch case=%0d tau=%0d got=%h expected=%h",
                         test_index, tau_sel ? 4 : 3, decoded_flat,
                         tau_sel ? reference_tau4 : reference_tau3);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        tau_sel = 1'b0;
        target_flat = {(COORDS*Q_WIDTH){1'b0}};
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (test_index = 0; test_index < CASES; test_index = test_index + 1) begin
            tau_sel = test_index[0];
            for (coord_index = 0; coord_index < COORDS;
                 coord_index = coord_index + 1)
                target_flat[(coord_index*Q_WIDTH)+:Q_WIDTH] = $random;
            run_case;
        end

        if (error_count == 0)
            $display("TB_PASS scloud_bdd4_seq_rt cases=%0d", CASES);
        else
            $display("TB_FAIL scloud_bdd4_seq_rt errors=%0d", error_count);
        $finish;
    end

endmodule
