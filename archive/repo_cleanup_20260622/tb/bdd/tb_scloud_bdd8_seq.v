`timescale 1ns/1ps

module tb_scloud_bdd8_seq;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam COORDS  = 8;

    reg                         clk;
    reg                         rst_n;
    reg                         start;
    reg  [(COORDS*Q_WIDTH)-1:0] target_flat;
    wire                        start_ready;
    wire                        busy;
    wire                        done;
    wire [(COORDS*Q_WIDTH)-1:0] decoded_seq;
    wire [(COORDS*Q_WIDTH)-1:0] decoded_ref;

    integer error_count;
    integer case_count;

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (TAU),
        .COMPLEX_N(4)
    ) u_ref (
        .target_flat (target_flat),
        .decoded_flat(decoded_ref)
    );

    scloud_bdd8_seq #(
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
        .decoded_flat(decoded_seq)
    );

    always #5 clk = ~clk;

    task run_case;
        input [127:0] name;
        input [(COORDS*Q_WIDTH)-1:0] target_value;
        begin
            @(posedge clk);
            while (!start_ready) begin
                @(posedge clk);
            end
            @(negedge clk);
            target_flat = target_value;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!done) begin
                @(posedge clk);
            end
            #1;
            case_count = case_count + 1;
            if (decoded_seq !== decoded_ref) begin
                error_count = error_count + 1;
                $display("FAIL %0s seq=%h ref=%h target=%h",
                         name, decoded_seq, decoded_ref, target_flat);
            end else begin
                $display("PASS %0s", name);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        target_flat = {COORDS*Q_WIDTH{1'b0}};
        error_count = 0;
        case_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        run_case("zero", {COORDS*Q_WIDTH{1'b0}});
        run_case("pattern", 80'h337d1ff8c1b3cd0b34d2);

        if (error_count == 0) begin
            $display("TB_PASS scloud_bdd8_seq cases=%0d", case_count);
        end else begin
            $display("TB_FAIL scloud_bdd8_seq errors=%0d cases=%0d",
                     error_count, case_count);
        end
        $finish;
    end

endmodule
