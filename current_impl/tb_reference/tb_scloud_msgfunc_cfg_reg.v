`timescale 1ns/1ps

module tb_scloud_msgfunc_cfg_reg;

    localparam Q_WIDTH      = 12;
    localparam TAU          = 3;
    localparam MAX_Q_BITS   = 32 * Q_WIDTH;
    localparam MAX_MSG_BITS = (16*(2*TAU)) - ((16*4)/2);

    reg clk;
    reg rst_n;
    reg start;
    reg [1:0] cfg_bw_mode;
    reg [MAX_MSG_BITS-1:0] msg_in;
    reg [MAX_Q_BITS-1:0]   noise_q_flat;

    wire start_ready;
    wire busy;
    wire valid_out;
    wire [5:0] active_q_coords;
    wire [6:0] active_msg_bits;
    wire [MAX_Q_BITS-1:0]   enc_q_flat;
    wire [MAX_Q_BITS-1:0]   noisy_q_flat;
    wire [MAX_Q_BITS-1:0]   rounded_q_flat;
    wire [MAX_MSG_BITS-1:0] msg_out;

    integer error_count;

    scloud_msgfunc_cfg_reg #(
        .Q_WIDTH     (Q_WIDTH),
        .TAU         (TAU),
        .MAX_Q_BITS  (MAX_Q_BITS),
        .MAX_MSG_BITS(MAX_MSG_BITS)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .cfg_bw_mode    (cfg_bw_mode),
        .msg_in         (msg_in),
        .noise_q_flat   (noise_q_flat),
        .start_ready    (start_ready),
        .busy           (busy),
        .valid_out      (valid_out),
        .active_q_coords(active_q_coords),
        .active_msg_bits(active_msg_bits),
        .enc_q_flat     (enc_q_flat),
        .noisy_q_flat   (noisy_q_flat),
        .rounded_q_flat (rounded_q_flat),
        .msg_out        (msg_out)
    );

    always #5 clk = ~clk;

    task clear_noise;
        begin
            noise_q_flat = {MAX_Q_BITS{1'b0}};
        end
    endtask

    task set_noise;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            noise_q_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_tc;
        end
    endtask

    task run_case;
        input [1:0] mode_value;
        input [MAX_MSG_BITS-1:0] msg_value;
        input [MAX_MSG_BITS-1:0] expect_msg;
        input [5:0] expect_coords;
        input [6:0] expect_bits;
        begin
            @(negedge clk);
            cfg_bw_mode = mode_value;
            msg_in = msg_value;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            cfg_bw_mode = 2'd2;
            msg_in = {MAX_MSG_BITS{1'b1}};
            noise_q_flat = {MAX_Q_BITS{1'b1}};
            wait (valid_out);
            #1;
            if (msg_out !== expect_msg) begin
                error_count = error_count + 1;
                $display("FAIL msg mode=%0d got=%h exp=%h", mode_value, msg_out, expect_msg);
            end
            if (active_q_coords !== expect_coords) begin
                error_count = error_count + 1;
                $display("FAIL coords mode=%0d got=%0d exp=%0d", mode_value, active_q_coords, expect_coords);
            end
            if (active_msg_bits !== expect_bits) begin
                error_count = error_count + 1;
                $display("FAIL bits mode=%0d got=%0d exp=%0d", mode_value, active_msg_bits, expect_bits);
            end
            clear_noise;
        end
    endtask

    initial begin
        $dumpfile("tb_scloud_msgfunc_cfg_reg.vcd");
        $dumpvars(0, tb_scloud_msgfunc_cfg_reg);

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        cfg_bw_mode = 2'd0;
        msg_in = {MAX_MSG_BITS{1'b0}};
        clear_noise;
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        clear_noise;
        set_noise(0, 12'd13);
        set_noise(1, 12'hff5);
        set_noise(5, 12'd31);
        set_noise(7, 12'hfe8);
        run_case(2'd0, 64'h00000000000abcde, 64'h00000000000abcde, 6'd8, 7'd20);

        clear_noise;
        set_noise(0, 12'd13);
        set_noise(1, 12'hff5);
        set_noise(7, 12'd41);
        set_noise(15, 12'hfeb);
        run_case(2'd1, 64'h0000000abcde1234, 64'h0000000abcde1234, 6'd16, 7'd36);

        clear_noise;
        set_noise(0, 12'd13);
        set_noise(1, 12'hff5);
        set_noise(18, 12'd43);
        set_noise(31, 12'hff1);
        run_case(2'd2, 64'hdeadbeef12345678, 64'hdeadbeef12345678, 6'd32, 7'd64);

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_cfg_reg");
        end else begin
            $display("TB_FAIL scloud_msgfunc_cfg_reg errors=%0d", error_count);
        end
        $finish;
    end

endmodule
