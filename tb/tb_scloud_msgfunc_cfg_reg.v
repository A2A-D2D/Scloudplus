`timescale 1ns/1ps

module tb_scloud_msgfunc_cfg_reg;

    reg clk;
    reg rst_n;
    reg start;
    reg [1:0] cfg_bw_mode;
    reg [31:0] msg_in;
    reg [319:0] noise_q_flat;

    wire start_ready;
    wire busy;
    wire valid_out;
    wire [5:0] active_q_coords;
    wire [5:0] active_msg_bits;
    wire [319:0] enc_q_flat;
    wire [319:0] noisy_q_flat;
    wire [319:0] rounded_q_flat;
    wire [31:0] msg_out;

    integer error_count;

    scloud_msgfunc_cfg_reg dut (
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
            noise_q_flat = 320'b0;
        end
    endtask

    task set_noise;
        input integer coord_idx;
        input [9:0] noise_tc;
        begin
            noise_q_flat[(coord_idx*10)+:10] = noise_tc;
        end
    endtask

    task run_case;
        input [1:0] mode_value;
        input [31:0] msg_value;
        input [31:0] expect_msg;
        input [5:0] expect_coords;
        input [5:0] expect_bits;
        begin
            @(negedge clk);
            cfg_bw_mode = mode_value;
            msg_in = msg_value;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            cfg_bw_mode = 2'd2;
            msg_in = 32'hffffffff;
            noise_q_flat = {320{1'b1}};
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
        msg_in = 32'h00000000;
        clear_noise;
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        clear_noise;
        set_noise(0, 10'd13);
        set_noise(1, 10'h3f5);
        set_noise(5, 10'd31);
        set_noise(7, 10'h3e8);
        run_case(2'd0, 32'h00000a5c, 32'h00000a5c, 6'd8, 6'd12);

        clear_noise;
        set_noise(0, 10'd13);
        set_noise(1, 10'h3f5);
        set_noise(7, 10'd41);
        set_noise(15, 10'h3eb);
        run_case(2'd1, 32'h000abcde, 32'h000abcde, 6'd16, 6'd20);

        clear_noise;
        set_noise(0, 10'd13);
        set_noise(1, 10'h3f5);
        set_noise(18, 10'd43);
        set_noise(31, 10'h3f1);
        run_case(2'd2, 32'hdeadbeef, 32'hdeadbeef, 6'd32, 6'd32);

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_cfg_reg");
        end else begin
            $display("TB_FAIL scloud_msgfunc_cfg_reg errors=%0d", error_count);
        end
        $finish;
    end

endmodule
