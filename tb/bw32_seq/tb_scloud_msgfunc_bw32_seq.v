`timescale 1ns/1ps

module tb_scloud_msgfunc_bw32_seq;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam COORDS  = 32;

    reg                         clk;
    reg                         rst_n;
    reg                         start;
    reg  [31:0]                 msg_in;
    reg  [(COORDS*Q_WIDTH)-1:0] noise_q_flat;
    wire                        start_ready;
    wire                        busy;
    wire                        done;
    wire [(COORDS*Q_WIDTH)-1:0] enc_q_seq;
    wire [(COORDS*Q_WIDTH)-1:0] noisy_q_seq;
    wire [(COORDS*Q_WIDTH)-1:0] rounded_q_seq;
    wire [31:0]                 msg_out_seq;

    wire [(COORDS*Q_WIDTH)-1:0] enc_q_ref;
    wire [(COORDS*Q_WIDTH)-1:0] noisy_q_ref;
    wire [(COORDS*Q_WIDTH)-1:0] rounded_q_ref;
    wire [31:0]                 msg_out_ref;

    integer error_count;
    integer pass_count;
    integer cycle_count;
    integer ni;

    scloud_msgfunc_bw32_seq #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .msg_in         (msg_in),
        .noise_q_flat   (noise_q_flat),
        .start_ready    (start_ready),
        .busy           (busy),
        .done           (done),
        .enc_q_flat     (enc_q_seq),
        .noisy_q_flat   (noisy_q_seq),
        .rounded_q_flat (rounded_q_seq),
        .msg_out        (msg_out_seq)
    );

    scloud_msgfunc_bw32_demo #(
        .Q_WIDTH(Q_WIDTH),
        .TAU    (TAU)
    ) u_ref (
        .msg_in         (msg_in),
        .noise_q_flat   (noise_q_flat),
        .enc_q_flat     (enc_q_ref),
        .noisy_q_flat   (noisy_q_ref),
        .rounded_q_flat (rounded_q_ref),
        .msg_out        (msg_out_ref)
    );

    always #5 clk = ~clk;

    task clear_noise;
        begin
            noise_q_flat = {(COORDS*Q_WIDTH){1'b0}};
        end
    endtask

    task set_noise_coord;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_value;
        begin
            noise_q_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_value;
        end
    endtask

    task apply_noise_a;
        begin
            clear_noise;
            set_noise_coord(0,  10'd13);
            set_noise_coord(1,  10'h3f5);
            set_noise_coord(3,  10'd29);
            set_noise_coord(4,  10'h3e1);
            set_noise_coord(7,  10'd41);
            set_noise_coord(9,  10'h3ef);
            set_noise_coord(12, 10'd35);
            set_noise_coord(15, 10'h3eb);
            set_noise_coord(18, 10'd43);
            set_noise_coord(19, 10'h3d3);
            set_noise_coord(24, 10'd31);
            set_noise_coord(25, 10'h3df);
            set_noise_coord(30, 10'd15);
            set_noise_coord(31, 10'h3f1);
        end
    endtask

    task apply_noise_b;
        begin
            clear_noise;
            set_noise_coord(0,  10'h3d4);
            set_noise_coord(1,  10'd50);
            set_noise_coord(2,  10'd48);
            set_noise_coord(3,  10'h3d2);
            set_noise_coord(6,  10'd24);
            set_noise_coord(7,  10'h3ea);
            set_noise_coord(10, 10'd36);
            set_noise_coord(11, 10'h3de);
            set_noise_coord(14, 10'd42);
            set_noise_coord(15, 10'h3d8);
            set_noise_coord(18, 10'h3e2);
            set_noise_coord(19, 10'd28);
            set_noise_coord(22, 10'd28);
            set_noise_coord(23, 10'h3e6);
            set_noise_coord(28, 10'd4);
            set_noise_coord(29, 10'h3fe);
        end
    endtask

    task run_case;
        input [31:0] msg_value;
        begin
            @(negedge clk);
            msg_in <= msg_value;
            start  <= 1'b1;

            @(negedge clk);
            start <= 1'b0;

            cycle_count = 0;
            while (!done && cycle_count < 200) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end

            if (!done) begin
                $display("TB_ERROR timeout msg=%08x", msg_value);
                error_count = error_count + 1;
            end else begin
                if (enc_q_seq !== enc_q_ref) begin
                    $display("TB_ERROR enc mismatch msg=%08x", msg_value);
                    error_count = error_count + 1;
                end
                if (noisy_q_seq !== noisy_q_ref) begin
                    $display("TB_ERROR noisy mismatch msg=%08x", msg_value);
                    error_count = error_count + 1;
                end
                if (rounded_q_seq !== rounded_q_ref) begin
                    $display("TB_ERROR rounded mismatch msg=%08x", msg_value);
                    error_count = error_count + 1;
                end
                if (msg_out_seq !== msg_out_ref) begin
                    $display("TB_ERROR msg mismatch msg=%08x seq=%08x ref=%08x",
                             msg_value, msg_out_seq, msg_out_ref);
                    error_count = error_count + 1;
                end
                if ((enc_q_seq === enc_q_ref) &&
                    (noisy_q_seq === noisy_q_ref) &&
                    (rounded_q_seq === rounded_q_ref) &&
                    (msg_out_seq === msg_out_ref)) begin
                    pass_count = pass_count + 1;
                    $display("TB_INFO pass msg=%08x cycles=%0d", msg_value, cycle_count);
                end
            end

            @(posedge clk);
        end
    endtask

    initial begin
        clk         = 1'b0;
        rst_n       = 1'b0;
        start       = 1'b0;
        msg_in      = 32'd0;
        error_count = 0;
        pass_count  = 0;
        clear_noise;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        if (!start_ready || busy || done) begin
            $display("TB_ERROR bad idle handshake start_ready=%b busy=%b done=%b",
                     start_ready, busy, done);
            error_count = error_count + 1;
        end

        clear_noise;
        run_case(32'h00000000);
        run_case(32'hffffffff);
        run_case(32'h12345678);
        run_case(32'hdeadbeef);

        apply_noise_a;
        run_case(32'h13579bdf);
        run_case(32'ha5a55a5a);

        apply_noise_b;
        run_case(32'h2468ace0);
        run_case(32'h89abcdef);

        clear_noise;
        for (ni = 0; ni < COORDS; ni = ni + 5) begin
            set_noise_coord(ni, 10'h3ff);
        end
        run_case(32'h55aa33cc);

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_bw32_seq cases=%0d", pass_count);
        end else begin
            $display("TB_FAIL scloud_msgfunc_bw32_seq errors=%0d cases=%0d",
                     error_count, pass_count);
        end

        $finish;
    end

endmodule
