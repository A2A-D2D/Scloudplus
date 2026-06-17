`timescale 1ns/1ps

/*
 * Randomized stress test: seq vs comb cross-validation
 * 256 random (msg, noise) pairs covering:
 *   - zero noise, sparse noise, dense noise
 *   - low/high amplitude
 *   - edge cases: max noise, zero msg, all-ones msg
 */
module tb_scloud_msgfunc_bw32_stress;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam COORDS  = 32;
    localparam N_CASES = 256;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [31:0] msg_in;
    reg  [(COORDS*Q_WIDTH)-1:0] noise_q_flat;
    wire        seq_ready;
    wire        seq_busy;
    wire        seq_done;
    wire [(COORDS*Q_WIDTH)-1:0] seq_enc;
    wire [(COORDS*Q_WIDTH)-1:0] seq_noisy;
    wire [(COORDS*Q_WIDTH)-1:0] seq_rounded;
    wire [31:0] seq_msg;

    wire [(COORDS*Q_WIDTH)-1:0] ref_enc;
    wire [(COORDS*Q_WIDTH)-1:0] ref_noisy;
    wire [(COORDS*Q_WIDTH)-1:0] ref_rounded;
    wire [31:0] ref_msg;

    integer errors, cases, i, c, ci;
    integer seed;
    integer n_active;

    // DUT: sequential version
    scloud_msgfunc_bw32_seq #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_seq (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .msg_in        (msg_in),
        .noise_q_flat  (noise_q_flat),
        .start_ready   (seq_ready),
        .busy          (seq_busy),
        .done          (seq_done),
        .enc_q_flat    (seq_enc),
        .noisy_q_flat  (seq_noisy),
        .rounded_q_flat(seq_rounded),
        .msg_out       (seq_msg)
    );

    // Reference: combinational demo
    scloud_msgfunc_bw32_demo #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) u_ref (
        .msg_in        (msg_in),
        .noise_q_flat  (noise_q_flat),
        .enc_q_flat    (ref_enc),
        .noisy_q_flat  (ref_noisy),
        .rounded_q_flat(ref_rounded),
        .msg_out       (ref_msg)
    );

    always #5 clk = ~clk;

    // Simple LFSR for pseudorandom test vectors
    function [31:0] lfsr;
        input [31:0] s;
        begin
            lfsr = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
        end
    endfunction

    task run_one;
        input [31:0] m;
        begin
            msg_in = m;
            // Wait for ready at negedge, launch at next posedge
            while (!seq_ready) @(posedge clk);
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            // Wait for done with timeout
            c = 0;
            while (!seq_done && c < 500) begin
                @(posedge clk); c = c + 1;
            end
            // Compare
            if (!seq_done) begin
                $display("FAIL timeout msg=%08x cycles=%0d", m, c);
                errors = errors + 1;
            end else begin
                #1;  // let combinational ref settle
                if (seq_enc !== ref_enc) begin
                    $display("FAIL enc msg=%08x seq[0]=%h ref[0]=%h", m,
                             seq_enc[0+:Q_WIDTH], ref_enc[0+:Q_WIDTH]);
                    errors = errors + 1;
                end
                if (seq_rounded !== ref_rounded) begin
                    $display("FAIL rounded msg=%08x seq[0]=%h ref[0]=%h", m,
                             seq_rounded[0+:Q_WIDTH], ref_rounded[0+:Q_WIDTH]);
                    errors = errors + 1;
                end
                if (seq_msg !== ref_msg) begin
                    $display("FAIL msg msg=%08x seq=%08x ref=%08x", m, seq_msg, ref_msg);
                    errors = errors + 1;
                end
            end
            cases = cases + 1;
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; start = 0; msg_in = 0;
        noise_q_flat = 0; errors = 0; cases = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Phase 1: Corner cases with zero noise
        $display("--- Phase 1: Zero-noise corner cases ---");
        noise_q_flat = 0;
        run_one(32'h00000000);
        run_one(32'hffffffff);
        run_one(32'haaaaaaaa);
        run_one(32'h55555555);
        run_one(32'hffff0000);
        run_one(32'h0000ffff);

        // Phase 2: Single-coordinate max noise
        $display("--- Phase 2: Single-coord max noise ---");
        seed = 32'hdead;
        for (i = 0; i < 16; i = i + 1) begin
            seed = lfsr(seed);
            noise_q_flat = 0;
            noise_q_flat[(i*Q_WIDTH)+:Q_WIDTH] = {Q_WIDTH{1'b1}};  // all 1s
            run_one(seed);
            noise_q_flat = 0;
            noise_q_flat[(i*Q_WIDTH)+:Q_WIDTH] = {1'b1, {(Q_WIDTH-1){1'b0}}};  // max negative
            run_one(seed);
        end

        // Phase 3: Random (msg, noise) pairs
        $display("--- Phase 3: Randomized pairs ---");
        seed = 32'hbdd32;
        for (i = 0; i < 200; i = i + 1) begin
            seed = lfsr(seed);
            msg_in = lfsr(seed);
            seed = lfsr(seed);
            // Random noise: 0~15 active coords, amplitude 0~1023
            noise_q_flat = 0;
            n_active = seed[4:0];  // 0-31
            for (ci = 0; ci < 32; ci = ci + 1) begin
                seed = lfsr(seed);
                if (ci < n_active)
                    noise_q_flat[(ci*Q_WIDTH)+:Q_WIDTH] = seed[9:0];
            end
            run_one(msg_in);
        end

        // Phase 4: Dense noise (all coords)
        $display("--- Phase 4: All-coord dense noise ---");
        for (i = 0; i < 10; i = i + 1) begin
            seed = lfsr(seed);
            for (c = 0; c < 32; c = c + 1) begin
                seed = lfsr(seed);
                noise_q_flat[(c*Q_WIDTH)+:Q_WIDTH] = seed[9:0];
            end
            run_one(lfsr(seed));
        end

        if (errors == 0)
            $display("TB_PASS scloud_msgfunc_bw32_stress cases=%0d", cases);
        else
            $display("TB_FAIL scloud_msgfunc_bw32_stress errors=%0d cases=%0d", errors, cases);

        $finish;
    end

endmodule
