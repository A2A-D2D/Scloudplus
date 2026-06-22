`timescale 1ns/1ps

module tb_scloud_bdd32_seq_rt;

    localparam Q_WIDTH = 12;
    localparam COORDS  = 32;
    localparam CASES   = 20;

    reg clk;
    reg rst_n;
    reg start;
    reg tau_sel;
    reg target_half_valid;
    reg target_half_sel;
    reg [(16*Q_WIDTH)-1:0] target_half_data;
    reg [(COORDS*Q_WIDTH)-1:0] target_flat;

    wire target_half_ready;
    wire start_ready;
    wire done;
    wire [(COORDS*Q_WIDTH)-1:0] decoded_flat;
    wire [(COORDS*Q_WIDTH)-1:0] reference_tau3;
    wire [(COORDS*Q_WIDTH)-1:0] reference_tau4;

    integer test_index;
    integer coord_index;
    integer error_count;
    integer cycle_count;
    integer min_cycle_count;
    integer max_cycle_count;

    always #5 clk = ~clk;

    scloud_bdd32_seq_rt #(.Q_WIDTH(Q_WIDTH)) dut (
        .target_half_data (target_half_data),
        .target_half_valid(target_half_valid),
        .target_half_sel  (target_half_sel),
        .target_half_ready(target_half_ready),
        .tau_sel          (tau_sel),
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (start),
        .start_ready      (start_ready),
        .busy             (),
        .done             (done),
        .decoded_flat     (decoded_flat)
    );

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (3),
        .COMPLEX_N(16)
    ) u_reference_tau3 (
        .target_flat (target_flat),
        .decoded_flat(reference_tau3)
    );

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (4),
        .COMPLEX_N(16)
    ) u_reference_tau4 (
        .target_flat (target_flat),
        .decoded_flat(reference_tau4)
    );

    task run_case;
        begin
            while (!target_half_ready) @(posedge clk);
            @(negedge clk);
            target_half_sel = test_index[1] ? 1'b1 : 1'b0;
            target_half_data = target_half_sel ?
                               target_flat[(16*Q_WIDTH)+:(16*Q_WIDTH)] :
                               target_flat[0+:(16*Q_WIDTH)];
            target_half_valid = 1'b1;
            @(negedge clk);
            target_half_valid = 1'b0;

            if (start_ready) begin
                error_count = error_count + 1;
                $display("FAIL start_ready after one half case=%0d", test_index);
            end

            while (!target_half_ready) @(posedge clk);
            @(negedge clk);
            target_half_sel = test_index[1] ? 1'b0 : 1'b1;
            target_half_data = target_half_sel ?
                               target_flat[(16*Q_WIDTH)+:(16*Q_WIDTH)] :
                               target_flat[0+:(16*Q_WIDTH)];
            target_half_valid = 1'b1;
            @(negedge clk);
            target_half_valid = 1'b0;

            while (!start_ready) @(posedge clk);
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            cycle_count = 0;
            while (!done && cycle_count < 5000) begin
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
                $display("FAIL mismatch case=%0d tau=%0d", test_index,
                         tau_sel ? 4 : 3);
            end

            if (done) begin
                if (cycle_count < min_cycle_count)
                    min_cycle_count = cycle_count;
                if (cycle_count > max_cycle_count)
                    max_cycle_count = cycle_count;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        tau_sel = 1'b0;
        target_half_valid = 1'b0;
        target_half_sel = 1'b0;
        target_half_data = {(16*Q_WIDTH){1'b0}};
        target_flat = {(COORDS*Q_WIDTH){1'b0}};
        error_count = 0;
        cycle_count = 0;
        min_cycle_count = 5000;
        max_cycle_count = 0;

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
            $display("TB_PASS scloud_bdd32_seq_rt cases=%0d cycles=%0d..%0d",
                     CASES, min_cycle_count, max_cycle_count);
        else
            $display("TB_FAIL scloud_bdd32_seq_rt errors=%0d", error_count);
        $finish;
    end

endmodule
