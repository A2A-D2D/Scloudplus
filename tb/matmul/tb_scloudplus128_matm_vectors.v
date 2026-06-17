`timescale 1ns/1ps

module tb_scloudplus128_matm_vectors;

    localparam B = 8;
    localparam Q_WIDTH = 12;
    localparam ACC_WIDTH = 20;
    localparam IDX_WIDTH = 8;
    localparam CFG_WIDTH = 5;
    localparam BLOCK_BITS = B*B*Q_WIDTH;
    localparam S_BITS = B*B*2;
    localparam REQ_BITS = BLOCK_BITS + S_BITS;
    localparam MAX_REQ = 150;
    localparam MAX_EXP = 2;

    reg clk;
    reg rst_n;
    reg start;
    reg blk_in_valid;
    reg [CFG_WIDTH-1:0] cfg_b_active;
    reg [CFG_WIDTH-1:0] cfg_q_active;
    reg [1:0] cfg_coeff_mode;
    reg [IDX_WIDTH-1:0] cfg_row_blocks;
    reg [IDX_WIDTH-1:0] cfg_inner_blocks;
    reg [IDX_WIDTH-1:0] cfg_col_blocks;
    reg [BLOCK_BITS-1:0] a_block;
    reg [S_BITS-1:0] s_block;

    wire start_ready;
    wire busy;
    wire done;
    wire blk_req_valid;
    wire blk_in_ready;
    wire [IDX_WIDTH-1:0] a_row_blk;
    wire [IDX_WIDTH-1:0] a_col_blk;
    wire [IDX_WIDTH-1:0] s_col_blk;
    wire c_block_valid;
    wire [IDX_WIDTH-1:0] c_row_blk;
    wire [IDX_WIDTH-1:0] c_col_blk;
    wire [BLOCK_BITS-1:0] c_block;

    reg [REQ_BITS-1:0] req_mem [0:MAX_REQ-1];
    reg [BLOCK_BITS-1:0] exp_mem [0:MAX_EXP-1];
    integer errors;
    integer req_idx;
    integer exp_idx;

    scloudplus_matmul_serial #(
        .B(B),
        .Q_WIDTH(Q_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .IDX_WIDTH(IDX_WIDTH),
        .CFG_WIDTH(CFG_WIDTH)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .cfg_b_active(cfg_b_active),
        .cfg_q_active(cfg_q_active),
        .cfg_coeff_mode(cfg_coeff_mode),
        .cfg_row_blocks(cfg_row_blocks),
        .cfg_inner_blocks(cfg_inner_blocks),
        .cfg_col_blocks(cfg_col_blocks),
        .start_ready(start_ready),
        .busy(busy),
        .done(done),
        .blk_req_valid(blk_req_valid),
        .blk_req_ready(1'b1),
        .a_row_blk(a_row_blk),
        .a_col_blk(a_col_blk),
        .s_col_blk(s_col_blk),
        .blk_in_valid(blk_in_valid),
        .blk_in_ready(blk_in_ready),
        .a_block(a_block),
        .s_block(s_block),
        .c_block_valid(c_block_valid),
        .c_block_ready(1'b1),
        .c_row_blk(c_row_blk),
        .c_col_blk(c_col_blk),
        .c_block(c_block)
    );

    always #5 clk = ~clk;

    task drive_req_block;
        begin
            wait (blk_in_ready);
            @(negedge clk);
            blk_in_valid = 1'b1;
            @(negedge clk);
            blk_in_valid = 1'b0;
        end
    endtask

    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("tb_scloudplus128_matm_vectors.vcd");
            $dumpvars(0, tb_scloudplus128_matm_vectors);
        end

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        blk_in_valid = 1'b0;
        cfg_b_active = 5'd8;
        cfg_q_active = 5'd12;
        cfg_coeff_mode = 2'd0;
        cfg_row_blocks = 8'd0;
        cfg_inner_blocks = 8'd0;
        cfg_col_blocks = 8'd0;
        a_block = {BLOCK_BITS{1'b0}};
        s_block = {S_BITS{1'b0}};
        errors = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        run_common("keygen_as",
                   "tb/vectors/scloudplus128/keygen_as_req.mem",
                   "tb/vectors/scloudplus128/keygen_as_exp.mem",
                   8'd2, 8'd75, 8'd1, 150, 2);
        run_common("enc_c1_transpose",
                   "tb/vectors/scloudplus128/enc_c1_transpose_req.mem",
                   "tb/vectors/scloudplus128/enc_c1_transpose_exp.mem",
                   8'd2, 8'd75, 8'd1, 150, 2);
        run_common("dec_c1s",
                   "tb/vectors/scloudplus128/dec_c1s_req.mem",
                   "tb/vectors/scloudplus128/dec_c1s_exp.mem",
                   8'd1, 8'd75, 8'd1, 75, 1);
        run_common("c_keygen_as",
                   "tb/vectors/scloudplus128_c/keygen_as_req.mem",
                   "tb/vectors/scloudplus128_c/keygen_as_exp.mem",
                   8'd2, 8'd75, 8'd1, 150, 2);
        run_common("c_enc_c1_transpose",
                   "tb/vectors/scloudplus128_c/enc_c1_transpose_req.mem",
                   "tb/vectors/scloudplus128_c/enc_c1_transpose_exp.mem",
                   8'd2, 8'd75, 8'd1, 150, 2);
        run_common("c_dec_c1s",
                   "tb/vectors/scloudplus128_c/dec_c1s_req.mem",
                   "tb/vectors/scloudplus128_c/dec_c1s_exp.mem",
                   8'd1, 8'd75, 8'd1, 75, 1);

        if (errors == 0) begin
            $display("TB_PASS scloudplus128_matm_vectors");
        end else begin
            $display("TB_FAIL scloudplus128_matm_vectors errors=%0d", errors);
        end
        $finish;
    end

    task run_common;
        input [8*64-1:0] name;
        input [8*128-1:0] req_file;
        input [8*128-1:0] exp_file;
        input [IDX_WIDTH-1:0] row_blocks;
        input [IDX_WIDTH-1:0] inner_blocks;
        input [IDX_WIDTH-1:0] col_blocks;
        input integer req_count;
        input integer exp_count;
        begin
            $display("RUN %0s", name);
            $readmemh(req_file, req_mem);
            $readmemh(exp_file, exp_mem);
            cfg_row_blocks = row_blocks;
            cfg_inner_blocks = inner_blocks;
            cfg_col_blocks = col_blocks;
            req_idx = 0;
            exp_idx = 0;
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!done) begin
                if (blk_req_valid) begin
                    {a_block, s_block} = req_mem[req_idx];
                    req_idx = req_idx + 1;
                    drive_req_block;
                end else begin
                    @(negedge clk);
                end
                if (c_block_valid) begin
                    if (c_block !== exp_mem[exp_idx]) begin
                        $display("FAIL %0s output=%0d row=%0d col=%0d", name, exp_idx, c_row_blk, c_col_blk);
                        $display("  got=%h", c_block);
                        $display("  exp=%h", exp_mem[exp_idx]);
                        errors = errors + 1;
                    end
                    exp_idx = exp_idx + 1;
                end
            end
            if (req_idx != req_count) begin
                $display("FAIL %0s req_count got=%0d exp=%0d", name, req_idx, req_count);
                errors = errors + 1;
            end
            if (exp_idx != exp_count) begin
                $display("FAIL %0s exp_count got=%0d exp=%0d", name, exp_idx, exp_count);
                errors = errors + 1;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        #5000000;
        $display("TB_TIMEOUT scloudplus128_matm_vectors");
        $finish;
    end

endmodule
