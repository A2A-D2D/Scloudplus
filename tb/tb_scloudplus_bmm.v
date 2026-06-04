`timescale 1ns/1ps

module tb_scloudplus_bmm;

    localparam B = 4;
    localparam Q_WIDTH = 4;
    localparam ACC_WIDTH = 8;
    localparam IDX_WIDTH = 4;
    localparam CFG_WIDTH = 4;

    reg clk;
    reg rst_n;
    reg start;
    reg blk_in_valid;
    reg c_block_ready;
    reg [CFG_WIDTH-1:0] cfg_b_active;
    reg [CFG_WIDTH-1:0] cfg_q_active;
    reg [1:0] cfg_coeff_mode;
    reg [IDX_WIDTH-1:0] cfg_row_blocks;
    reg [IDX_WIDTH-1:0] cfg_inner_blocks;
    reg [IDX_WIDTH-1:0] cfg_col_blocks;
    reg [B*B*Q_WIDTH-1:0] a_block;
    reg [B*B*2-1:0] s_block;

    wire [B*B*Q_WIDTH-1:0] c_direct;
    wire start_ready;
    wire busy;
    wire done;
    wire blk_req_valid;
    wire [IDX_WIDTH-1:0] a_row_blk;
    wire [IDX_WIDTH-1:0] a_col_blk;
    wire [IDX_WIDTH-1:0] s_col_blk;
    wire c_block_valid;
    wire [IDX_WIDTH-1:0] c_row_blk;
    wire [IDX_WIDTH-1:0] c_col_blk;
    wire [B*B*Q_WIDTH-1:0] c_block;

    integer errors;

    scloudplus_bmm_block #(
        .B(B),
        .Q_WIDTH(Q_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .CFG_WIDTH(CFG_WIDTH)
    ) u_direct (
        .cfg_b_active(cfg_b_active),
        .cfg_q_active(cfg_q_active),
        .cfg_coeff_mode(cfg_coeff_mode),
        .a_block(a_block),
        .s_block(s_block),
        .c_block(c_direct)
    );

    scloudplus_matmul_serial #(
        .B(B),
        .Q_WIDTH(Q_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .IDX_WIDTH(IDX_WIDTH),
        .CFG_WIDTH(CFG_WIDTH)
    ) u_serial (
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
        .a_block(a_block),
        .s_block(s_block),
        .c_block_valid(c_block_valid),
        .c_block_ready(c_block_ready),
        .c_row_blk(c_row_blk),
        .c_col_blk(c_col_blk),
        .c_block(c_block)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        blk_in_valid = 1'b0;
        c_block_ready = 1'b1;
        cfg_b_active = 4'd2;
        cfg_q_active = 4'd4;
        cfg_coeff_mode = 2'd0;
        cfg_row_blocks = 4'd1;
        cfg_inner_blocks = 4'd2;
        cfg_col_blocks = 4'd1;
        a_block = {B*B*Q_WIDTH{1'b0}};
        s_block = {B*B*2{1'b0}};
        errors = 0;

        $dumpfile("tb_scloudplus_bmm.vcd");
        $dumpvars(0, tb_scloudplus_bmm);

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        a_block[0*Q_WIDTH +: Q_WIDTH] = 4'd3;
        a_block[1*Q_WIDTH +: Q_WIDTH] = 4'd5;
        a_block[4*Q_WIDTH +: Q_WIDTH] = 4'd7;
        a_block[5*Q_WIDTH +: Q_WIDTH] = 4'd2;
        s_block[0*2 +: 2] = 2'b01;
        s_block[1*2 +: 2] = 2'b10;
        s_block[4*2 +: 2] = 2'b00;
        s_block[5*2 +: 2] = 2'b01;
        #1;

        if (c_direct[0*Q_WIDTH +: Q_WIDTH] !== 4'd3) begin errors = errors + 1; $display("FAIL direct c00"); end
        if (c_direct[1*Q_WIDTH +: Q_WIDTH] !== 4'd2) begin errors = errors + 1; $display("FAIL direct c01"); end
        if (c_direct[4*Q_WIDTH +: Q_WIDTH] !== 4'd7) begin errors = errors + 1; $display("FAIL direct c10"); end
        if (c_direct[5*Q_WIDTH +: Q_WIDTH] !== 4'd11) begin errors = errors + 1; $display("FAIL direct c11"); end
        if (c_direct[2*Q_WIDTH +: Q_WIDTH] !== 4'd0) begin errors = errors + 1; $display("FAIL inactive col"); end
        if (c_direct[8*Q_WIDTH +: Q_WIDTH] !== 4'd0) begin errors = errors + 1; $display("FAIL inactive row"); end

        cfg_q_active = 4'd3;
        cfg_coeff_mode = 2'd1;
        #1;
        if (c_direct[0*Q_WIDTH +: Q_WIDTH] !== 4'd3) begin errors = errors + 1; $display("FAIL binary q3 c00"); end
        if (c_direct[1*Q_WIDTH +: Q_WIDTH] !== 4'd5) begin errors = errors + 1; $display("FAIL binary q3 c01"); end

        cfg_q_active = 4'd4;
        cfg_coeff_mode = 2'd0;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        wait (blk_req_valid);
        @(negedge clk);
        a_block = {B*B*Q_WIDTH{1'b0}};
        s_block = {B*B*2{1'b0}};
        a_block[0*Q_WIDTH +: Q_WIDTH] = 4'd1;
        a_block[1*Q_WIDTH +: Q_WIDTH] = 4'd2;
        a_block[4*Q_WIDTH +: Q_WIDTH] = 4'd3;
        a_block[5*Q_WIDTH +: Q_WIDTH] = 4'd4;
        s_block[0*2 +: 2] = 2'b01;
        s_block[1*2 +: 2] = 2'b00;
        s_block[4*2 +: 2] = 2'b01;
        s_block[5*2 +: 2] = 2'b01;
        blk_in_valid = 1'b1;
        repeat (2) @(negedge clk);
        blk_in_valid = 1'b0;

        wait (blk_req_valid);
        @(negedge clk);
        a_block = {B*B*Q_WIDTH{1'b0}};
        s_block = {B*B*2{1'b0}};
        a_block[0*Q_WIDTH +: Q_WIDTH] = 4'd5;
        a_block[1*Q_WIDTH +: Q_WIDTH] = 4'd6;
        a_block[4*Q_WIDTH +: Q_WIDTH] = 4'd7;
        a_block[5*Q_WIDTH +: Q_WIDTH] = 4'd8;
        s_block[0*2 +: 2] = 2'b10;
        s_block[1*2 +: 2] = 2'b01;
        s_block[4*2 +: 2] = 2'b00;
        s_block[5*2 +: 2] = 2'b10;
        blk_in_valid = 1'b1;
        repeat (2) @(negedge clk);
        blk_in_valid = 1'b0;

        wait (c_block_valid);
        #1;
        if (c_block[0*Q_WIDTH +: Q_WIDTH] !== 4'd14) begin errors = errors + 1; $display("FAIL serial c00"); end
        if (c_block[1*Q_WIDTH +: Q_WIDTH] !== 4'd1) begin errors = errors + 1; $display("FAIL serial c01"); end
        if (c_block[4*Q_WIDTH +: Q_WIDTH] !== 4'd0) begin errors = errors + 1; $display("FAIL serial c10"); end
        if (c_block[5*Q_WIDTH +: Q_WIDTH] !== 4'd3) begin errors = errors + 1; $display("FAIL serial c11"); end
        if (c_block[2*Q_WIDTH +: Q_WIDTH] !== 4'd0) begin errors = errors + 1; $display("FAIL serial inactive col"); end

        wait (done);
        if (errors == 0) begin
            $display("TB_PASS scloudplus_bmm");
        end else begin
            $display("TB_FAIL scloudplus_bmm errors=%0d", errors);
        end
        $finish;
    end

    initial begin
        #2000;
        $display("TB_TIMEOUT scloudplus_bmm");
        $finish;
    end

endmodule
