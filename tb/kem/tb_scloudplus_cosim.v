/*
 * tb_scloudplus_cosim.v — Scloud+ HW-SW Co-Verification (simplified)
 *
 * Tests MsgFunc encode/decode roundtrip via RTL accelerator,
 * with input vectors from file and output written to file.
 *
 * Input:  tb/kem/vec_msg_enc.mem (message bytes for encode)
 *         tb/kem/vec_q_enc.mem  (encoded Q for decode test)
 * Output: tb/kem/vec_q_hw.mem   (RTL-encoded Q codeword)
 *         tb/kem/vec_msg_hw.mem  (RTL-decoded message)
 *
 * Build:
 *   iverilog -g2001 -o build/cosim.vvp rtl/... tb/kem/tb_scloudplus_cosim.v
 * Run:
 *   vvp build/cosim.vvp
 */

`define Q_WIDTH      12
`define DPRAM_DEPTH 1024

module tb_scloudplus_cosim;

  reg clk, rst_n;

  /* =======================================================================
   * DPRAM
   * ======================================================================= */

  reg [255:0] dpram_mem [0:`DPRAM_DEPTH-1];

  /* =======================================================================
   * MsgFunc RCE accelerator
   * ======================================================================= */

  reg  mf_start, mf_tau_sel, mf_dec_write_q;
  reg  [1:0] mf_op;
  reg  [2:0] mf_block_count;
  reg  [15:0] mf_msg_in_base, mf_msg_out_base, mf_q_in_base, mf_q_aux_base, mf_q_out_base;
  wire mf_start_ready, mf_busy, mf_done, mf_error;
  wire mf_dpram_en, mf_dpram_wr_en;
  wire [31:0] mf_dpram_be;
  wire [15:0] mf_dpram_addr;
  wire [255:0] mf_dpram_wdata;
  reg  [255:0] mf_dpram_rdata;

  scloud_msgfunc_rce_accel #(.DPRAM_ADDR_WIDTH(16), .Q_WIDTH(`Q_WIDTH))
  u_msgfunc (
    .clk(clk), .rst_n(rst_n),
    .start(mf_start), .op(mf_op), .tau_sel(mf_tau_sel),
    .block_count(mf_block_count), .dec_write_q(mf_dec_write_q),
    .start_ready(mf_start_ready), .busy(mf_busy), .done(mf_done), .error(mf_error),
    .dpram_en(mf_dpram_en), .dpram_wr_en(mf_dpram_wr_en),
    .dpram_be(mf_dpram_be), .dpram_addr(mf_dpram_addr),
    .dpram_wdata(mf_dpram_wdata), .dpram_rdata(mf_dpram_rdata),
    .msg_in_base(mf_msg_in_base), .msg_out_base(mf_msg_out_base),
    .q_in_base(mf_q_in_base), .q_aux_base(mf_q_aux_base),
    .q_out_base(mf_q_out_base)
  );

  /* DPRAM read/write for msgfunc */
  always @(posedge clk) begin : dpram_logic
    integer b;
    if (mf_dpram_en) begin
      mf_dpram_rdata <= dpram_mem[mf_dpram_addr];
      if (mf_dpram_wr_en) begin
        for (b = 0; b < 32; b = b + 1) begin
          if (mf_dpram_be[b])
            dpram_mem[mf_dpram_addr][b*8 +: 8] <= mf_dpram_wdata[b*8 +: 8];
        end
      end
    end
  end

  /* =======================================================================
   * Clock & Reset
   * ======================================================================= */

  always #5 clk = ~clk;

  /* =======================================================================
   * Helper: wait for done, count ticks
   * ======================================================================= */

  integer tick_counter;

  always @(posedge clk) begin
    if (!rst_n) tick_counter <= 0;
    else tick_counter <= tick_counter + 1;
  end

  /* =======================================================================
   * Main Test
   * ======================================================================= */

  reg [7:0] msg_in_bytes [0:15];    /* up to 16 bytes of msg */
  reg [11:0] q_vals [0:63];         /* up to 64 Q values (2 blocks × 32) */
  reg [7:0] msg_out_bytes [0:15];
  integer i, j, pass, fail;
  reg [11:0] qword0 [0:15], qword1 [0:15]; /* for saving Q output */
  reg [7:0] mb_out [0:15];                   /* for saving msg output */

  initial begin
    pass = 0; fail = 0;
    clk = 0; rst_n = 0;
    mf_start = 0;
    #20 rst_n = 1; #10;

    $display("\n============================================================");
    $display("  Scloud+ HW-SW Co-Verification (MsgFunc only)");
    $display("============================================================\n");

    /* ===============================================================
     * Test 1: MsgEncode via RTL
     * Message (8 bytes, tau=3) → Q codeword (32 × 12-bit)
     * =============================================================== */

    $display("--- Test 1: RTL MsgEncode ---");

    /* Clear DPRAM */
    for (i = 0; i < `DPRAM_DEPTH; i = i + 1) dpram_mem[i] = 256'd0;

    /* Load message from file (or use inline) */
    $readmemh("tb/kem/vec_msg_in.mem", msg_in_bytes, 0, 7);

    /* Write message to DPRAM[0] (MSG_IN_BASE = 0) */
    dpram_mem[0] = 256'd0;
    for (i = 0; i < 8; i = i + 1)
      dpram_mem[0][i*8 +: 8] = msg_in_bytes[i];

    /* Run OP_MSGENC: msg at [0] → Q at [64] (Q_OUT_BASE=192?) — use Q_OUT_BASE=64 */
    $display("  Starting encode...");
    mf_op = 2'd0;       /* OP_MSGENC */
    mf_tau_sel = 1'b0;  /* tau=3 */
    mf_block_count = 3'd1;
    mf_dec_write_q = 1'b0;
    mf_msg_in_base = 16'd0;
    mf_msg_out_base = 16'd0;
    mf_q_in_base = 16'd0;
    mf_q_aux_base = 16'd0;
    mf_q_out_base = 16'd64;

    /* Pulse start (exact pattern from working TB) */
    @(negedge clk);
    mf_start = 1'b1;
    @(negedge clk);
    mf_start = 1'b0;

    /* Wait for done */
    while (!mf_done) @(posedge clk);
    @(posedge clk);
    $display("  Encode done at tick %0d", tick_counter);

    /* Save all 32 Q values to one array then write */
    for (i = 0; i < 16; i = i + 1) qword0[i] = dpram_mem[64][i*16 +: 12];
    for (i = 0; i < 16; i = i + 1) qword1[i] = dpram_mem[65][i*16 +: 12];
    /* Write as two files or one combined */
    $writememh("tb/kem/vec_q_hw0.mem", qword0, 0, 15);
    $writememh("tb/kem/vec_q_hw1.mem", qword1, 0, 15);
    $display("  Encoded Q saved (2 files)");
    $display("  Q[0]=%03x Q[1]=%03x ... Q[31]=%03x",
             qword0[0], qword0[1], qword1[15]);
    pass = pass + 1;

    /* ===============================================================
     * Test 2: MsgDecode via RTL
     * Q codeword → decoded message
     * =============================================================== */

    $display("\n--- Test 2: RTL MsgDecode ---");

    /* The encoded Q is already at DPRAM[64:65] from Test 1 */

    /* Run OP_MSGDEC: Q at [64] → msg at [16] (MSG_OUT_BASE=16) */
    $display("  Starting decode...");
    mf_op = 2'd1;       /* OP_MSGDEC */
    mf_tau_sel = 1'b0;
    mf_block_count = 3'd1;
    mf_dec_write_q = 1'b0;
    mf_msg_in_base = 16'd0;
    mf_msg_out_base = 16'd16;
    mf_q_in_base = 16'd64;
    mf_q_aux_base = 16'd0;
    mf_q_out_base = 16'd0;

    @(negedge clk);
    mf_start = 1'b1;
    @(negedge clk);
    mf_start = 1'b0;

    while (!mf_done) @(posedge clk);
    @(posedge clk);
    $display("  Decode done at tick %0d", tick_counter);

    /* Save decoded message */
    for (i = 0; i < 8; i = i + 1) mb_out[i] = dpram_mem[16][i*8 +: 8];
    $writememh("tb/kem/vec_msg_hw.mem", mb_out, 0, 7);
    $display("  Decoded msg: %02x %02x %02x %02x %02x %02x %02x %02x",
             mb_out[0], mb_out[1], mb_out[2], mb_out[3],
             mb_out[4], mb_out[5], mb_out[6], mb_out[7]);

    /* Compare with original message */
    j = 0;
    for (i = 0; i < 8; i = i + 1) if (mb_out[i] != msg_in_bytes[i]) j = j + 1;
    if (j == 0) begin
      $display("  [PASS] Roundtrip: decoded msg matches input");
      pass = pass + 1;
    end else begin
      $display("  [FAIL] %0d bytes differ", j);
      fail = fail + 1;
    end

    /* ===============================================================
     * Summary
     * =============================================================== */

    $display("\n============================================================");
    $display("  Results: %0d pass, %0d fail", pass, fail);
    $display("============================================================\n");
    $finish;
  end

endmodule
