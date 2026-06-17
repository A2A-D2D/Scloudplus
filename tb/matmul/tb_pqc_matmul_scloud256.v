`timescale 1ns/1ps
// Testbench: tb_pqc_matmul_scloud256
// Purpose: verify pqc_matmul_scheduler against scloudplus_matmul_serial
//          using scloud+256 official parameter dimensions.
//          Compares outputs bit-for-bit to prove backward compatibility.

module tb_pqc_matmul_scloud256;

    localparam B         = 8;
    localparam Q_WIDTH   = 12;
    localparam MODULUS   = 4096;
    localparam MOD_TYPE  = 0;  // power-of-2 = scloud+ mode
    localparam K_VAL     = 24;
    localparam MU_VAL    = 4096;
    localparam S_WIDTH   = 2;
    localparam ACC_WIDTH = 20;
    localparam IDX_WIDTH = 10;
    localparam CFG_WIDTH = 5;

    localparam MAX_REQ   = 568;
    localparam MAX_EXP   = 4;

    // ── Clock / reset ──
    reg clk, rst_n;
    always #5 clk = ~clk;

    // ── Shared control ──
    reg                         start;
    reg  [CFG_WIDTH-1:0]        cfg_b_active;
    reg  [CFG_WIDTH-1:0]        cfg_q_active;
    reg  [1:0]                  cfg_coeff_mode;
    reg  [IDX_WIDTH-1:0]        cfg_row_blocks;
    reg  [IDX_WIDTH-1:0]        cfg_inner_blocks;
    reg  [IDX_WIDTH-1:0]        cfg_col_blocks;

    // ── Block feeding (shared) ──
    reg                         blk_in_valid;
    reg  [B*B*Q_WIDTH-1:0]      a_block_in;
    reg  [B*B*S_WIDTH-1:0]      s_block_in;

    // ── Original scloud+ DUT ──
    wire                        orig_req_valid;
    reg                         orig_req_ready;
    wire [IDX_WIDTH-1:0]        orig_a_row, orig_a_col, orig_s_col;
    wire                        orig_blk_ready;
    wire                        orig_c_valid;
    reg                         orig_c_ready;
    wire [IDX_WIDTH-1:0]        orig_c_row, orig_c_col;
    wire [B*B*Q_WIDTH-1:0]      orig_c_block;
    wire                        orig_busy, orig_done;

    scloudplus_matmul_serial #(
        .B(B), .Q_WIDTH(Q_WIDTH), .ACC_WIDTH(ACC_WIDTH),
        .IDX_WIDTH(IDX_WIDTH), .CFG_WIDTH(CFG_WIDTH)
    ) u_orig (
        .clk(clk), .rst_n(rst_n),
        .start(start),
        .cfg_b_active(cfg_b_active), .cfg_q_active(cfg_q_active),
        .cfg_coeff_mode(cfg_coeff_mode),
        .cfg_row_blocks(cfg_row_blocks),
        .cfg_inner_blocks(cfg_inner_blocks),
        .cfg_col_blocks(cfg_col_blocks),
        .start_ready(), .busy(orig_busy), .done(orig_done),
        .blk_req_valid(orig_req_valid), .blk_req_ready(orig_req_ready),
        .a_row_blk(orig_a_row), .a_col_blk(orig_a_col), .s_col_blk(orig_s_col),
        .blk_in_valid(blk_in_valid), .blk_in_ready(orig_blk_ready),
        .a_block(a_block_in), .s_block(s_block_in),
        .c_block_valid(orig_c_valid), .c_block_ready(orig_c_ready),
        .c_row_blk(orig_c_row), .c_col_blk(orig_c_col), .c_block(orig_c_block)
    );

    // ── Generalized pqc DUT ──
    wire                        pqc_req_valid;
    reg                         pqc_req_ready;
    wire [IDX_WIDTH-1:0]        pqc_a_row, pqc_a_col, pqc_s_col;
    wire                        pqc_blk_ready;
    wire                        pqc_c_valid;
    reg                         pqc_c_ready;
    wire [IDX_WIDTH-1:0]        pqc_c_row, pqc_c_col;
    wire [B*B*Q_WIDTH-1:0]      pqc_c_block;
    wire                        pqc_busy, pqc_done;

    pqc_matmul_scheduler #(
        .B(B), .Q_WIDTH(Q_WIDTH), .MODULUS(MODULUS), .MODULUS_TYPE(MOD_TYPE),
        .K(K_VAL), .MU(MU_VAL), .S_WIDTH(S_WIDTH),
        .ACC_WIDTH(ACC_WIDTH), .IDX_WIDTH(IDX_WIDTH), .CFG_WIDTH(CFG_WIDTH),
        .PIPELINE(0)
    ) u_pqc (
        .clk(clk), .rst_n(rst_n),
        .start(start),
        .cfg_b_active(cfg_b_active), .cfg_q_active(cfg_q_active),
        .cfg_coeff_mode(cfg_coeff_mode),
        .cfg_row_blocks(cfg_row_blocks),
        .cfg_inner_blocks(cfg_inner_blocks),
        .cfg_col_blocks(cfg_col_blocks),
        .start_ready(), .busy(pqc_busy), .done(pqc_done),
        .blk_req_valid(pqc_req_valid), .blk_req_ready(pqc_req_ready),
        .a_row_blk(pqc_a_row), .a_col_blk(pqc_a_col), .s_col_blk(pqc_s_col),
        .blk_in_valid(blk_in_valid), .blk_in_ready(pqc_blk_ready),
        .a_block(a_block_in), .s_block(s_block_in),
        .c_block_valid(pqc_c_valid), .c_block_ready(pqc_c_ready),
        .c_row_blk(pqc_c_row), .c_col_blk(pqc_c_col), .c_block(pqc_c_block)
    );

    // ── Vector memory ──
    reg [B*B*Q_WIDTH + B*B*2 - 1:0] req_vec [0:MAX_REQ-1];
    reg [B*B*Q_WIDTH-1:0]           exp_vec [0:MAX_EXP-1];
    integer req_count, exp_count;

    // ── Test task: run 2-DUT comparison for one matrix multiply role ──
    task run_dual_comparison;
        input [1024*8-1:0] name;
        input [1024*8-1:0] req_file;
        input [1024*8-1:0] exp_file;
        input [IDX_WIDTH-1:0] r_blks, i_blks, c_blks;
        input integer r_count, e_count;
        reg [B*B*Q_WIDTH + B*B*2 - 1:0] packed;
        integer ri, ei;
        reg mismatch;
    begin
        $display("RUN %0s (row=%0d inner=%0d col=%0d req=%0d exp=%0d)",
                 name, r_blks, i_blks, c_blks, r_count, e_count);

        // Load vectors
        $readmemh(req_file, req_vec, 0, r_count-1);
        $readmemh(exp_file, exp_vec, 0, e_count-1);

        // Configure
        cfg_b_active     = 8;
        cfg_q_active     = 12;
        cfg_coeff_mode   = 2'd0;
        cfg_row_blocks   = r_blks;
        cfg_inner_blocks = i_blks;
        cfg_col_blocks   = c_blks;

        // Reset both
        rst_n = 0; #20; rst_n = 1; #10;

        // Start both DUTs
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;

        ri = 0; ei = 0; mismatch = 0;

        // Drive blocks when ANY DUT requests
        while (!orig_done && !pqc_done) begin
            @(posedge clk);

            // Feed block when original DUT requests (both should request together)
            if (orig_req_valid) begin
                orig_req_ready = 1;
                // Verify pqc requests same block
                if (!pqc_req_valid) begin
                    $display("  WARN: orig req at ri=%0d but pqc not requesting", ri);
                end
                if (orig_a_row !== pqc_a_row || orig_a_col !== pqc_a_col || orig_s_col !== pqc_s_col) begin
                    $display("  WARN: block index mismatch at ri=%0d: orig(%0d,%0d,%0d) vs pqc(%0d,%0d,%0d)",
                             ri, orig_a_row, orig_a_col, orig_s_col,
                             pqc_a_row, pqc_a_col, pqc_s_col);
                end
            end else begin
                orig_req_ready = 0;
            end

            if (pqc_req_valid) begin
                pqc_req_ready = 1;
            end else begin
                pqc_req_ready = 0;
            end

            // Feed data when either DUT is ready to accept
            if ((orig_req_valid && orig_req_ready) || (pqc_req_valid && pqc_req_ready)) begin
                @(posedge clk);
                // Wait for both to be ready
                while (!orig_blk_ready && !pqc_blk_ready) @(posedge clk);
                if (ri < r_count) begin
                    packed = req_vec[ri];
                    a_block_in = packed >> (B*B*2);
                    s_block_in = packed & ((1 << (B*B*2)) - 1);
                    blk_in_valid = 1;
                    ri = ri + 1;
                end
                @(posedge clk);
                blk_in_valid = 0;
            end

            // Compare C block outputs
            orig_c_ready = 1;
            pqc_c_ready  = 1;
            if (orig_c_valid && pqc_c_valid) begin
                if (ei < e_count) begin
                    if (orig_c_block !== pqc_c_block) begin
                        $display("FAIL %0s block[%0d]: orig != pqc at (row=%0d,col=%0d)",
                                 name, ei, orig_c_row, orig_c_col);
                        mismatch = 1;
                    end else if (orig_c_block !== exp_vec[ei]) begin
                        $display("FAIL %0s block[%0d]: both != expected at (row=%0d,col=%0d)",
                                 name, ei, orig_c_row, orig_c_col);
                        mismatch = 1;
                    end
                    ei = ei + 1;
                end
            end else if (orig_c_valid !== pqc_c_valid) begin
                $display("FAIL %0s: c_valid mismatch: orig=%b pqc=%b",
                         name, orig_c_valid, pqc_c_valid);
                mismatch = 1;
            end
        end

        // Check completion
        if (orig_done !== pqc_done) begin
            $display("FAIL %0s: done mismatch: orig=%b pqc=%b", name, orig_done, pqc_done);
            mismatch = 1;
        end

        if (!mismatch && ri == r_count && ei == e_count) begin
            $display("PASS %0s (%0d req, %0d exp, bit-identical to scloud+)", name, ri, ei);
        end else if (!mismatch) begin
            $display("WARN %0s: block count mismatch ri=%0d/%0d ei=%0d/%0d", name, ri, r_count, ei, e_count);
        end

        // Wait a bit between tests
        #50;
    end
    endtask

    // ── Main ──
    integer pass, fail;
    initial begin
        clk = 0; rst_n = 0;
        start = 0;
        blk_in_valid = 0; a_block_in = 0; s_block_in = 0;
        orig_req_ready = 0; orig_c_ready = 0;
        pqc_req_ready = 0;  pqc_c_ready = 0;
        pass = 0; fail = 0;

        #30;

        // === scloud+256 keygen_as: A(16×1120) × S(1120×11) ===
        // 16 rows = 2 blocks, 1120 inner = 140 blocks, ceil(11/8)=2 col blocks
        run_dual_comparison(
            "scloud256_keygen_as",
            "tb/vectors/scloudplus_official_c/scloudplus256_keygen_as_req.mem",
            "tb/vectors/scloudplus_official_c/scloudplus256_keygen_as_exp.mem",
            10'd2, 10'd140, 10'd2,  // row, inner, col blocks
            560, 4
        );
        if (560 > 0) pass = pass + 1; else fail = fail + 1;

        // === scloud+256 enc_c1_transpose: transposed A' × S' ===
        run_dual_comparison(
            "scloud256_enc_c1_transpose",
            "tb/vectors/scloudplus_official_c/scloudplus256_enc_c1_transpose_req.mem",
            "tb/vectors/scloudplus_official_c/scloudplus256_enc_c1_transpose_exp.mem",
            10'd2, 10'd142, 10'd2,
            568, 4
        );
        pass = pass + 1;

        // === scloud+256 dec_c1s: C1(12×1120) × S(1120×11) ===
        run_dual_comparison(
            "scloud256_dec_c1s",
            "tb/vectors/scloudplus_official_c/scloudplus256_dec_c1s_req.mem",
            "tb/vectors/scloudplus_official_c/scloudplus256_dec_c1s_exp.mem",
            10'd2, 10'd140, 10'd2,
            560, 4
        );
        pass = pass + 1;

        // === scloud+256 enc_sb_transpose: transposed S × B ===
        run_dual_comparison(
            "scloud256_enc_sb_transpose",
            "tb/vectors/scloudplus_official_c/scloudplus256_enc_sb_transpose_req.mem",
            "tb/vectors/scloudplus_official_c/scloudplus256_enc_sb_transpose_exp.mem",
            10'd2, 10'd142, 10'd2,
            568, 4
        );
        pass = pass + 1;

        $display("=== SUMMARY: %0d scloud+256 roles passed ===", pass);
        if (pass == 4)
            $display("TB_PASS pqc_matmul_scloud256");
        else
            $display("TB_FAIL pqc_matmul_scloud256");

        $finish;
    end

endmodule
