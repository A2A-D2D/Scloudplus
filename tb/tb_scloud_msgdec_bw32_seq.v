`timescale 1ns/1ps

module tb_scloud_msgdec_bw32_seq;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam COORDS  = 32;

    reg                         clk;
    reg                         rst_n;
    reg                         start;
    reg  [31:0]                 msg_in;
    reg  [(COORDS*Q_WIDTH)-1:0] noisy_q_flat;
    wire [(COORDS*Q_WIDTH)-1:0] enc_q_flat;
    wire [31:0]                 msg_ref;
    wire [(COORDS*Q_WIDTH)-1:0] rounded_ref;
    wire                        start_ready;
    wire                        busy;
    wire                        done;
    wire [31:0]                 msg_seq;
    wire [(COORDS*Q_WIDTH)-1:0] rounded_seq;

    integer error_count;
    integer case_count;

    scloud_msgenc_bw32_block #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_enc (
        .msg_block  (msg_in),
        .code_q_flat(enc_q_flat)
    );

    scloud_msgdec_bw32_block #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_ref_dec (
        .noisy_q_flat  (noisy_q_flat),
        .msg_block     (msg_ref),
        .rounded_q_flat(rounded_ref)
    );

    scloud_msgdec_bw32_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_seq_dec (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .noisy_q_flat  (noisy_q_flat),
        .start_ready   (start_ready),
        .busy          (busy),
        .done          (done),
        .msg_block     (msg_seq),
        .rounded_q_flat(rounded_seq)
    );

    always #5 clk = ~clk;

    task run_case;
        input [127:0] name;
        input [31:0]  msg_value;
        input [Q_WIDTH-1:0] noise0;
        input [Q_WIDTH-1:0] noise7;
        begin
            msg_in = msg_value;
            #1;
            noisy_q_flat = enc_q_flat;
            noisy_q_flat[(0*Q_WIDTH)+:Q_WIDTH] =
                noisy_q_flat[(0*Q_WIDTH)+:Q_WIDTH] + noise0;
            noisy_q_flat[(7*Q_WIDTH)+:Q_WIDTH] =
                noisy_q_flat[(7*Q_WIDTH)+:Q_WIDTH] + noise7;

            @(posedge clk);
            while (!start_ready) begin
                @(posedge clk);
            end
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!done) begin
                @(posedge clk);
            end
            #1;

            case_count = case_count + 1;
            if (msg_seq !== msg_ref || rounded_seq !== rounded_ref) begin
                error_count = error_count + 1;
                $display("FAIL %0s msg_seq=%h msg_ref=%h round_seq=%h round_ref=%h",
                         name, msg_seq, msg_ref, rounded_seq, rounded_ref);
            end else begin
                $display("PASS %0s msg=%h", name, msg_seq);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        msg_in = 32'd0;
        noisy_q_flat = {COORDS*Q_WIDTH{1'b0}};
        error_count = 0;
        case_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        run_case("zero", 32'h00000000, 10'd0,    10'd0);
        run_case("pattern_a", 32'h12345678, 10'd17,   10'h3f1);
        run_case("pattern_b", 32'hdeadbeef, 10'h3f8, 10'd31);
        run_case("pattern_c", 32'ha5a55a5a, 10'd63,   10'h3e2);

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgdec_bw32_seq cases=%0d", case_count);
        end else begin
            $display("TB_FAIL scloud_msgdec_bw32_seq errors=%0d cases=%0d",
                     error_count, case_count);
        end
        $finish;
    end

endmodule
