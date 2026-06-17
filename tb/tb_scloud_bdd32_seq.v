`timescale 1ns/1ps

module tb_scloud_bdd32_seq;

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
    wire [(COORDS*Q_WIDTH)-1:0] decoded_seq;
    wire [(COORDS*Q_WIDTH)-1:0] decoded_ref;

    integer error_count;
    integer case_count;

    scloud_bdd_recursive #(
        .Q_WIDTH  (Q_WIDTH),
        .TAU      (TAU),
        .COMPLEX_N(16)
    ) u_ref (
        .target_flat (target_flat),
        .decoded_flat(decoded_ref)
    );

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
        .decoded_flat(decoded_seq)
    );

    always #5 clk = ~clk;

    task run_case;
        input [127:0] name;
        input [(COORDS*Q_WIDTH)-1:0] target_value;
        integer wait_cycles;
        begin
            @(posedge clk);
            while (!start_ready) begin
                @(posedge clk);
            end
            @(negedge clk);
            target_flat = target_value;
            start = 1'b1;
            $display("START %0s", name);
            @(negedge clk);
            start = 1'b0;
            wait_cycles = 0;
            while (!done && wait_cycles < 200) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!done) begin
                error_count = error_count + 1;
                $display("FAIL_TIMEOUT %0s busy=%b ready=%b", name, busy, start_ready);
            end else begin
                #1;
                case_count = case_count + 1;
                if (decoded_seq !== decoded_ref) begin
                    error_count = error_count + 1;
                    $display("FAIL %0s seq=%h ref=%h target=%h",
                             name, decoded_seq, decoded_ref, target_flat);
                end else begin
                    $display("PASS %0s cycles=%0d", name, wait_cycles);
                end
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
        run_case("rec00", 320'h3c50ff94197f60337d1ff8c1b3cd0b34d2b7e605bad13f6c23001f745cef8a5fbc1ce1c76f503600);
        run_case("rec01", 320'h4b4ff00dd10c7df48ee9065efc34d5ca4e1085f5027edc552e344fb81ff1c44e58742576400c00d5);
        run_case("rec02", 320'h4cacc3bb147f804770263812239b1c7d00ef582c073e2fe808b612a37b24841ee00200bab1834b30);
        run_case("rec03", 320'h7d70d002f143de5c65fd80edf87ce3c6ff342fd3cadf9c15eb84cdb88d00bdc17bbc297ef07f851d);

        if (error_count == 0) begin
            $display("TB_PASS scloud_bdd32_seq cases=%0d", case_count);
        end else begin
            $display("TB_FAIL scloud_bdd32_seq errors=%0d cases=%0d",
                     error_count, case_count);
        end
        $finish;
    end

endmodule
