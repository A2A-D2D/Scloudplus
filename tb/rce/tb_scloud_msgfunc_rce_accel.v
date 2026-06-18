`timescale 1ns/1ps

module tb_scloud_msgfunc_rce_accel;

    localparam ADDR_WIDTH = 10;

    localparam [1:0] OP_MSGENC     = 2'd0;
    localparam [1:0] OP_MSGDEC     = 2'd1;
    localparam [1:0] OP_MSGENC_ADD = 2'd2;
    localparam [1:0] OP_SUB_MSGDEC = 2'd3;

    localparam [ADDR_WIDTH-1:0] MSG_IN_BASE   = 10'd0;
    localparam [ADDR_WIDTH-1:0] MSG_OUT_BASE  = 10'd16;
    localparam [ADDR_WIDTH-1:0] Q_IN_BASE     = 10'd64;
    localparam [ADDR_WIDTH-1:0] Q_AUX_BASE    = 10'd128;
    localparam [ADDR_WIDTH-1:0] Q_OUT_BASE    = 10'd192;
    localparam [ADDR_WIDTH-1:0] Q_ROUND_BASE  = 10'd256;
    localparam [ADDR_WIDTH-1:0] MSG_OUT2_BASE = 10'd320;
    localparam [ADDR_WIDTH-1:0] Q_ADD_BASE    = 10'd384;

    reg clk;
    reg rst_n;
    reg start;
    reg [1:0] op;
    reg tau_sel;
    reg [2:0] block_count;
    reg dec_write_q;
    reg [ADDR_WIDTH-1:0] msg_in_base;
    reg [ADDR_WIDTH-1:0] msg_out_base;
    reg [ADDR_WIDTH-1:0] q_in_base;
    reg [ADDR_WIDTH-1:0] q_aux_base;
    reg [ADDR_WIDTH-1:0] q_out_base;

    wire start_ready;
    wire busy;
    wire done;
    wire error;
    wire dpram_en;
    wire dpram_wr_en;
    wire [31:0] dpram_be;
    wire [ADDR_WIDTH-1:0] dpram_addr;
    wire [255:0] dpram_wdata;
    reg  [255:0] dpram_rdata;

    reg [255:0] dpram_mem [0:1023];

    integer i;
    integer b;
    integer lane;
    integer byte_idx;
    integer error_count;
    integer cycle_count;

    scloud_msgfunc_rce_accel #(
        .DPRAM_ADDR_WIDTH(ADDR_WIDTH),
        .Q_WIDTH         (12)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .op          (op),
        .tau_sel     (tau_sel),
        .block_count (block_count),
        .dec_write_q (dec_write_q),
        .msg_in_base (msg_in_base),
        .msg_out_base(msg_out_base),
        .q_in_base   (q_in_base),
        .q_aux_base  (q_aux_base),
        .q_out_base  (q_out_base),
        .start_ready (start_ready),
        .busy        (busy),
        .done        (done),
        .error       (error),
        .dpram_en    (dpram_en),
        .dpram_wr_en (dpram_wr_en),
        .dpram_be    (dpram_be),
        .dpram_addr  (dpram_addr),
        .dpram_wdata (dpram_wdata),
        .dpram_rdata (dpram_rdata)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (dpram_en) begin
            dpram_rdata <= dpram_mem[dpram_addr];
            if (dpram_wr_en) begin
                for (byte_idx = 0; byte_idx < 32; byte_idx = byte_idx + 1) begin
                    if (dpram_be[byte_idx])
                        dpram_mem[dpram_addr][(byte_idx*8)+:8] <=
                            dpram_wdata[(byte_idx*8)+:8];
                end
            end
        end
    end

    initial begin
        cycle_count = 0;
        forever begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (cycle_count > 200000) begin
                $display("TB_TIMEOUT");
                $finish;
            end
        end
    end

    task clear_mem;
        begin
            for (i = 0; i < 1024; i = i + 1)
                dpram_mem[i] = 256'b0;
        end
    endtask

    task write_tau3_msg;
        input integer block_index;
        input [63:0] msg;
        begin
            dpram_mem[MSG_IN_BASE + block_index] = 256'b0;
            dpram_mem[MSG_IN_BASE + block_index][63:0] = msg;
        end
    endtask

    task write_tau4_msg;
        input integer block_index;
        input [95:0] msg;
        begin
            dpram_mem[MSG_IN_BASE + block_index] = 256'b0;
            dpram_mem[MSG_IN_BASE + block_index][95:0] = msg;
        end
    endtask

    task write_q_block;
        input [ADDR_WIDTH-1:0] base_addr;
        input integer block_index;
        input integer seed;
        reg [255:0] word0;
        reg [255:0] word1;
        reg [11:0] q_value;
        begin
            word0 = 256'b0;
            word1 = 256'b0;
            for (lane = 0; lane < 16; lane = lane + 1) begin
                q_value = (seed + lane * 17) & 12'hfff;
                word0[(lane*16)+:12] = q_value;
                q_value = (seed + (lane + 16) * 17) & 12'hfff;
                word1[(lane*16)+:12] = q_value;
            end
            dpram_mem[base_addr + (block_index * 2)] = word0;
            dpram_mem[base_addr + (block_index * 2) + 1] = word1;
        end
    endtask

    task run_accel;
        input [1:0] op_value;
        input tau_value;
        input [2:0] blocks_value;
        input dec_write_q_value;
        input [ADDR_WIDTH-1:0] msg_in_value;
        input [ADDR_WIDTH-1:0] msg_out_value;
        input [ADDR_WIDTH-1:0] q_in_value;
        input [ADDR_WIDTH-1:0] q_aux_value;
        input [ADDR_WIDTH-1:0] q_out_value;
        begin
            @(negedge clk);
            op           = op_value;
            tau_sel      = tau_value;
            block_count  = blocks_value;
            dec_write_q  = dec_write_q_value;
            msg_in_base  = msg_in_value;
            msg_out_base = msg_out_value;
            q_in_base    = q_in_value;
            q_aux_base   = q_aux_value;
            q_out_base   = q_out_value;
            start        = 1'b1;
            @(negedge clk);
            start        = 1'b0;
            while (!done) @(posedge clk);
            @(posedge clk);
            if (error) begin
                error_count = error_count + 1;
                $display("FAIL unexpected accelerator error op=%0d", op_value);
            end
        end
    endtask

    task check_tau3_msg;
        input integer block_index;
        input [ADDR_WIDTH-1:0] base_addr;
        input [63:0] expected;
        reg [63:0] got;
        begin
            got = dpram_mem[base_addr + block_index][63:0];
            if (got !== expected) begin
                error_count = error_count + 1;
                $display("FAIL tau3 block=%0d got=%h expected=%h",
                         block_index, got, expected);
            end else begin
                $display("OK tau3 block=%0d msg=%h", block_index, got);
            end
        end
    endtask

    task check_tau4_msg;
        input integer block_index;
        input [ADDR_WIDTH-1:0] base_addr;
        input [95:0] expected;
        reg [95:0] got;
        begin
            got = dpram_mem[base_addr + block_index][95:0];
            if (got !== expected) begin
                error_count = error_count + 1;
                $display("FAIL tau4 block=%0d got=%h expected=%h",
                         block_index, got, expected);
            end else begin
                $display("OK tau4 block=%0d msg=%h", block_index, got);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_scloud_msgfunc_rce_accel.vcd");
        $dumpvars(0, tb_scloud_msgfunc_rce_accel);

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        op = OP_MSGENC;
        tau_sel = 1'b0;
        block_count = 3'd0;
        dec_write_q = 1'b0;
        msg_in_base = MSG_IN_BASE;
        msg_out_base = MSG_OUT_BASE;
        q_in_base = Q_IN_BASE;
        q_aux_base = Q_AUX_BASE;
        q_out_base = Q_OUT_BASE;
        dpram_rdata = 256'b0;
        error_count = 0;
        clear_mem;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("TEST 1: tau3 MSGENC -> MSGDEC");
        write_tau3_msg(0, 64'h0123456789abcdef);
        write_tau3_msg(1, 64'hfedcba9876543210);
        run_accel(OP_MSGENC, 1'b0, 3'd2,
                  1'b0,
                  MSG_IN_BASE, MSG_OUT_BASE, Q_IN_BASE, Q_AUX_BASE, Q_OUT_BASE);
        run_accel(OP_MSGDEC, 1'b0, 3'd2,
                  1'b0,
                  MSG_IN_BASE, MSG_OUT_BASE, Q_OUT_BASE, Q_AUX_BASE, Q_ROUND_BASE);
        check_tau3_msg(0, MSG_OUT_BASE, 64'h0123456789abcdef);
        check_tau3_msg(1, MSG_OUT_BASE, 64'hfedcba9876543210);

        $display("TEST 2: tau4 MSGENC_ADD -> SUB_MSGDEC");
        clear_mem;
        write_tau4_msg(0, 96'h13579bdffdb97531a5a55a5a);
        write_tau4_msg(1, 96'hc001d00d0123456789abcdef);
        for (b = 0; b < 2; b = b + 1) begin
            write_q_block(Q_AUX_BASE, b, 37 + b * 101);
            dpram_mem[Q_IN_BASE + (b * 2)] = dpram_mem[Q_AUX_BASE + (b * 2)];
            dpram_mem[Q_IN_BASE + (b * 2) + 1] = dpram_mem[Q_AUX_BASE + (b * 2) + 1];
        end
        run_accel(OP_MSGENC_ADD, 1'b1, 3'd2,
                  1'b0,
                  MSG_IN_BASE, MSG_OUT2_BASE, Q_IN_BASE, Q_AUX_BASE, Q_ADD_BASE);
        run_accel(OP_SUB_MSGDEC, 1'b1, 3'd2,
                  1'b0,
                  MSG_IN_BASE, MSG_OUT2_BASE, Q_ADD_BASE, Q_AUX_BASE, Q_ROUND_BASE);
        check_tau4_msg(0, MSG_OUT2_BASE, 96'h13579bdffdb97531a5a55a5a);
        check_tau4_msg(1, MSG_OUT2_BASE, 96'hc001d00d0123456789abcdef);

        if (error_count == 0)
            $display("TB_PASS scloud_msgfunc_rce_accel");
        else
            $display("TB_FAIL scloud_msgfunc_rce_accel errors=%0d", error_count);

        $finish;
    end

endmodule
