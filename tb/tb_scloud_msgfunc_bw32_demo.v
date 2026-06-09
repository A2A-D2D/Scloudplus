`timescale 1ns/1ps

module tb_scloud_msgfunc_bw32_demo;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam COORDS  = 32;

    reg  [31:0]                 msg_in;
    reg  [(COORDS*Q_WIDTH)-1:0] noise_q_flat;
    wire [(COORDS*Q_WIDTH)-1:0] enc_q_flat;
    wire [(COORDS*Q_WIDTH)-1:0] noisy_q_flat;
    wire [(COORDS*Q_WIDTH)-1:0] rounded_q_flat;
    wire [31:0]                 msg_out;

    integer error_count;
    integer idx;

    scloud_msgfunc_bw32_demo dut (
        .msg_in        (msg_in),
        .noise_q_flat  (noise_q_flat),
        .enc_q_flat    (enc_q_flat),
        .noisy_q_flat  (noisy_q_flat),
        .rounded_q_flat(rounded_q_flat),
        .msg_out       (msg_out)
    );

    task set_noise_coord;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            noise_q_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_tc;
        end
    endtask

    task check_case;
        input [31:0] msg_value;
        begin
            msg_in = msg_value;
            #1;
            if (msg_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL msg=%h out=%h enc=%h noisy=%h rounded=%h",
                         msg_value, msg_out, enc_q_flat, noisy_q_flat, rounded_q_flat);
            end else begin
                $display("PASS msg=%h out=%h", msg_value, msg_out);
            end
        end
    endtask

    task clear_noise;
        begin
            noise_q_flat = {COORDS*Q_WIDTH{1'b0}};
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

    initial begin
        $dumpfile("tb_scloud_msgfunc_bw32_demo.vcd");
        $dumpvars(0, tb_scloud_msgfunc_bw32_demo);

        error_count = 0;
        msg_in = 32'h00000000;
        clear_noise;
        #5;

        clear_noise;
        check_case(32'h00000000);
        check_case(32'h00000001);
        check_case(32'h80000000);
        check_case(32'h12345678);
        check_case(32'hdeadbeef);
        check_case(32'hffffffff);

        apply_noise_a;
        check_case(32'h13579bdf);
        check_case(32'ha5a55a5a);
        check_case(32'hc001d00d);

        apply_noise_b;
        check_case(32'h2468ace0);
        check_case(32'h89abcdef);
        check_case(32'h55aa33cc);

        clear_noise;
        for (idx = 0; idx < 32; idx = idx + 1) begin
            msg_in = (idx * 32'h00110203) ^ {idx[15:0], idx[15:0]};
            #1;
            if (msg_out !== msg_in) begin
                error_count = error_count + 1;
                $display("FAIL_SWEEP msg=%h out=%h enc=%h rounded=%h",
                         msg_in, msg_out, enc_q_flat, rounded_q_flat);
            end
        end

        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_bw32_demo");
        end else begin
            $display("TB_FAIL scloud_msgfunc_bw32_demo errors=%0d", error_count);
        end
        $finish;
    end

endmodule
