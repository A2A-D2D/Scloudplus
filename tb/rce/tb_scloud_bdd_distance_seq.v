`timescale 1ns/1ps

module tb_scloud_bdd_distance_seq;

    localparam Q_WIDTH = 12;
    localparam COORDS  = 32;
    localparam LANES   = 8;

    reg clk;
    reg rst_n;
    reg start;
    reg [(COORDS*Q_WIDTH)-1:0] cand_a_flat;
    reg [(COORDS*Q_WIDTH)-1:0] cand_b_flat;
    reg [(COORDS*Q_WIDTH)-1:0] target_flat;

    wire start_ready;
    wire done;
    wire select_a;
    wire [31:0] distance_a;
    wire [31:0] distance_b;
    wire [31:0] reference_a;
    wire [31:0] reference_b;

    integer test_index;
    integer coord_index;
    integer error_count;

    always #5 clk = ~clk;

    scloud_bdd_distance_tree #(
        .Q_WIDTH(Q_WIDTH),
        .COORDS (COORDS)
    ) u_reference_a (
        .cand_flat   (cand_a_flat),
        .target_flat (target_flat),
        .distance_out(reference_a)
    );

    scloud_bdd_distance_tree #(
        .Q_WIDTH(Q_WIDTH),
        .COORDS (COORDS)
    ) u_reference_b (
        .cand_flat   (cand_b_flat),
        .target_flat (target_flat),
        .distance_out(reference_b)
    );

    scloud_bdd_distance_seq #(
        .Q_WIDTH(Q_WIDTH),
        .COORDS (COORDS),
        .LANES  (LANES)
    ) dut (
        .cand_a_flat(cand_a_flat),
        .cand_b_flat(cand_b_flat),
        .target_flat(target_flat),
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .start_ready(start_ready),
        .busy       (),
        .done       (done),
        .select_a   (select_a),
        .distance_a (distance_a),
        .distance_b (distance_b)
    );

    task run_case;
        begin
            while (!start_ready) @(posedge clk);
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!done) @(posedge clk);

            if (distance_a !== reference_a ||
                distance_b !== reference_b ||
                select_a !== (reference_a < reference_b)) begin
                error_count = error_count + 1;
                $display("FAIL case=%0d got_a=%h ref_a=%h got_b=%h ref_b=%h select=%b",
                         test_index, distance_a, reference_a,
                         distance_b, reference_b, select_a);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        cand_a_flat = {(COORDS*Q_WIDTH){1'b0}};
        cand_b_flat = {(COORDS*Q_WIDTH){1'b0}};
        target_flat = {(COORDS*Q_WIDTH){1'b0}};
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (test_index = 0; test_index < 200; test_index = test_index + 1) begin
            for (coord_index = 0; coord_index < COORDS; coord_index = coord_index + 1) begin
                cand_a_flat[(coord_index*Q_WIDTH)+:Q_WIDTH] = $random;
                cand_b_flat[(coord_index*Q_WIDTH)+:Q_WIDTH] = $random;
                target_flat[(coord_index*Q_WIDTH)+:Q_WIDTH] = $random;
            end
            run_case;
        end

        if (error_count == 0)
            $display("TB_PASS scloud_bdd_distance_seq cases=200");
        else
            $display("TB_FAIL scloud_bdd_distance_seq errors=%0d", error_count);
        $finish;
    end

endmodule
