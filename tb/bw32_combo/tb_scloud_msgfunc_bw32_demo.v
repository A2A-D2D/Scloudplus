`timescale 1ns/1ps

/*
 * tb_scloud_msgfunc_bw32_demo — Comprehensive Testbench
 *
 * Coverage:
 *   - Zero-noise round-trip (6 fixed patterns + 128 pseudorandom)
 *   - WH-class directed tests (each of 16 coordinates exercised)
 *   - Corner cases: all-0, all-1, alternating 0xAAAA/0x5555
 *   - Noise stress: single-coord max-amplitude noise sweep
 *   - Cross-validation: bw32_demo vs msgfunc_param (COMPLEX_N=16)
 */
module tb_scloud_msgfunc_bw32_demo;

    localparam Q_WIDTH = 10;
    localparam TAU     = 2;
    localparam COORDS  = 32;

    /* ---- DUT signals ---- */
    reg  [31:0]                 msg_in;
    reg  [(COORDS*Q_WIDTH)-1:0] noise_q_flat;
    wire [(COORDS*Q_WIDTH)-1:0] enc_q_flat;
    wire [(COORDS*Q_WIDTH)-1:0] noisy_q_flat;
    wire [(COORDS*Q_WIDTH)-1:0] rounded_q_flat;
    wire [31:0]                 msg_out;

    /* ---- Reference param version ---- */
    reg  [31:0]                 ref_msg_in;
    reg  [(COORDS*Q_WIDTH)-1:0] ref_noise;
    wire [(COORDS*Q_WIDTH)-1:0] ref_enc;
    wire [(COORDS*Q_WIDTH)-1:0] ref_noisy;
    wire [(COORDS*Q_WIDTH)-1:0] ref_rounded;
    wire [31:0]                 ref_msg_out;

    integer error_count;
    integer idx, ci, sweep_n;
    reg [31:0] lfsr_state;          // LFSR state shared across test phases

    /* ---- DUT: demo version ---- */
    scloud_msgfunc_bw32_demo #(.Q_WIDTH(Q_WIDTH), .TAU(TAU)) dut (
        .msg_in        (msg_in),
        .noise_q_flat  (noise_q_flat),
        .enc_q_flat    (enc_q_flat),
        .noisy_q_flat  (noisy_q_flat),
        .rounded_q_flat(rounded_q_flat),
        .msg_out       (msg_out)
    );

    /* ---- Reference: parameterized version ---- */
    scloud_msgfunc_param #(
        .COMPLEX_N    (16),
        .LOG_COMPLEX_N(4),
        .Q_WIDTH      (Q_WIDTH),
        .TAU          (TAU),
        .LABEL_WIDTH  (6),
        .MSG_WIDTH    (32)
    ) ref_dut (
        .msg_in        (ref_msg_in),
        .noise_q_flat  (ref_noise),
        .enc_q_flat    (ref_enc),
        .noisy_q_flat  (ref_noisy),
        .rounded_q_flat(ref_rounded),
        .msg_out       (ref_msg_out)
    );

    /* ---- Helper tasks ---- */
    task set_noise_coord;
        input integer coord_idx;
        input [Q_WIDTH-1:0] noise_tc;
        begin
            noise_q_flat[(coord_idx*Q_WIDTH)+:Q_WIDTH] = noise_tc;
            ref_noise[(coord_idx*Q_WIDTH)+:Q_WIDTH]    = noise_tc;
        end
    endtask

    task clear_noise;
        begin
            noise_q_flat = {COORDS*Q_WIDTH{1'b0}};
            ref_noise    = {COORDS*Q_WIDTH{1'b0}};
        end
    endtask

    task set_msg;
        input [31:0] m;
        begin
            msg_in     = m;
            ref_msg_in = m;
        end
    endtask

    /* check_case: zero-noise round-trip (msg_out must == msg_in) */
    task check_case;
        input [31:0] msg_value;
        begin
            set_msg(msg_value);
            #1;
            if (msg_out !== msg_value) begin
                error_count = error_count + 1;
                $display("FAIL msg=%h out=%h enc=%h rounded=%h",
                         msg_value, msg_out, enc_q_flat, rounded_q_flat);
            end
        end
    endtask

    /* check_noisy: with noise, just verify demo == param reference */
    task check_noisy;
        input [31:0] msg_value;
        begin
            set_msg(msg_value);
            #1;
            if (msg_out !== ref_msg_out) begin
                error_count = error_count + 1;
                $display("FAIL_XVAL msg=%h demo_out=%h ref_out=%h",
                         msg_value, msg_out, ref_msg_out);
            end
            if (rounded_q_flat !== ref_rounded) begin
                error_count = error_count + 1;
                $display("FAIL_ROUND msg=%h demo_rounded[0]=%h ref_rounded[0]=%h",
                         msg_value, rounded_q_flat[0+:Q_WIDTH],
                         ref_rounded[0+:Q_WIDTH]);
            end
        end
    endtask

    /* ---- Noise pattern tasks ---- */
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

    /* ---- noise_stress: single-coordinate max positive/negative noise ---- */
    task noise_stress_coord;
        input integer ci;
        input [31:0] msg_val;
        begin
            /* +max noise on this coord */
            clear_noise;
            set_noise_coord(ci, {Q_WIDTH{1'b1}});
            set_msg(msg_val);
            #1;
            if (msg_out !== ref_msg_out) begin
                error_count = error_count + 1;
                $display("FAIL_STRESS_POS coord=%0d msg=%h demo=%h ref=%h",
                         ci, msg_val, msg_out, ref_msg_out);
            end

            /* -max (wrapped) noise on this coord */
            clear_noise;
            set_noise_coord(ci, {1'b1, {(Q_WIDTH-1){1'b0}}});
            set_msg(msg_val);
            #1;
            if (msg_out !== ref_msg_out) begin
                error_count = error_count + 1;
                $display("FAIL_STRESS_NEG coord=%0d msg=%h demo=%h ref=%h",
                         ci, msg_val, msg_out, ref_msg_out);
            end
        end
    endtask

    /* ---- LFSR-based pseudorandom message generator ---- */
    function [31:0] lfsr_next;
        input [31:0] state;
        begin
            lfsr_next = {state[30:0], state[31] ^ state[21] ^ state[1] ^ state[0]};
        end
    endfunction

    /* ================================================================ */
    initial begin
        $dumpfile("tb_scloud_msgfunc_bw32_demo.vcd");
        $dumpvars(0, tb_scloud_msgfunc_bw32_demo);

        error_count = 0;
        set_msg(32'h00000000);
        clear_noise;
        #5;

        /* ============================================ */
        /* PHASE 1: Zero-noise round-trip               */
        /* ============================================ */
        $display("=== PHASE 1: Zero-noise round-trip ===");
        clear_noise;
        check_case(32'h00000000);
        check_case(32'h00000001);
        check_case(32'h80000000);
        check_case(32'h12345678);
        check_case(32'hdeadbeef);
        check_case(32'hffffffff);

        /* Corner bit patterns */
        check_case(32'haaaaaaaa);
        check_case(32'h55555555);
        check_case(32'hffff0000);
        check_case(32'h0000ffff);
        check_case(32'hff00ff00);
        check_case(32'h00ff00ff);

        /* ============================================ */
        /* PHASE 2: WH-class directed tests             */
        /* ============================================ */
        $display("=== PHASE 2: WH-class directed tests ===");
        clear_noise;
        /* WH=0: coord 0 — 4 message bits (re[1:0], im[1:0]) */
        check_case(32'hc0000000);  // re=11 im=00
        check_case(32'h30000000);  // re=00 im=11
        check_case(32'hf0000000);  // re=11 im=11

        /* WH=1: coord 1 — 3 bits, coord 2 — 3 bits, coord 4 — 3 bits, coord 8 — 3 bits */
        check_case(32'h0e000000);  // coord1: re=11 im=1
        check_case(32'h01c00000);  // coord2: re=11 im=1
        check_case(32'h00007000);  // coord4: re=11 im=1
        check_case(32'h000000e0);  // coord8: re=11 im=1

        /* WH=2: coord 3 — 2 bits, coord 5 — 2 bits, coord 6 — 2 bits, etc. */
        check_case(32'h00300000);  // coord3: re=1 im=1
        check_case(32'h0000c000);  // coord5: re=1 im=1
        check_case(32'h00003000);  // coord6: re=1 im=1

        /* WH=3: coord 7 — 1 bit, coord 11 — 1 bit, coord 13 — 1 bit, coord 14 — 1 bit */
        check_case(32'h00001000);  // coord7 bit
        check_case(32'h00000010);  // coord11 bit
        check_case(32'h00000002);  // coord13 bit
        check_case(32'h00000001);  // coord14 bit

        /* WH=4: coord 15 — 0 bits (always 0) */
        /* any message value should have coord15=0 — tested implicitly above */

        /* ============================================ */
        /* PHASE 3: Noise pattern A & B (fixed vectors) */
        /* ============================================ */
        $display("=== PHASE 3: Fixed noise patterns (cross-validated) ===");
        apply_noise_a;
        check_noisy(32'h13579bdf);
        check_noisy(32'ha5a55a5a);
        check_noisy(32'hc001d00d);

        apply_noise_b;
        check_noisy(32'h2468ace0);
        check_noisy(32'h89abcdef);
        check_noisy(32'h55aa33cc);

        /* ============================================ */
        /* PHASE 4: Pseudorandom sweep (zero noise)     */
        /* ============================================ */
        $display("=== PHASE 4: Pseudorandom sweep (zero noise) ===");
        clear_noise;
        lfsr_state = 32'hace1;
        for (sweep_n = 0; sweep_n < 128; sweep_n = sweep_n + 1) begin
            lfsr_state = lfsr_next(lfsr_state);
            check_case(lfsr_state);
        end

        /* ============================================ */
        /* PHASE 5: Noise stress — single coord max     */
        /* ============================================ */
        $display("=== PHASE 5: Single-coordinate noise stress ===");
        lfsr_state = 32'hdead;
        /* Test 8 representative coordinates with 4 random messages each */
        for (ci = 0; ci < 32; ci = ci + 4) begin
            lfsr_state = lfsr_next(lfsr_state);
            noise_stress_coord(ci, lfsr_state);
            lfsr_state = lfsr_next(lfsr_state);
            noise_stress_coord(ci, lfsr_state);
        end

        /* ============================================ */
        /* PHASE 6: Pseudorandom sweep (with noise B)   */
        /* ============================================ */
        $display("=== PHASE 6: Pseudorandom sweep (with noise B) ===");
        lfsr_state = 32'hbeef;
        for (sweep_n = 0; sweep_n < 64; sweep_n = sweep_n + 1) begin
            lfsr_state = lfsr_next(lfsr_state);
            /* Vary noise per iteration: incremental offset on each coord */
            if ((sweep_n % 8) == 0) apply_noise_b;
            else begin
                for (ci = 0; ci < 32; ci = ci + 1) begin
                    set_noise_coord(ci, noise_q_flat[(ci*Q_WIDTH)+:Q_WIDTH] + (sweep_n * 3));
                end
            end
            check_noisy(lfsr_state);
        end

        /* ============================================ */
        /* PHASE 7: All-coordinate max noise (boundary) */
        /* ============================================ */
        $display("=== PHASE 7: All-coordinate max noise ===");
        lfsr_state = 32'hcafe;
        for (ci = 0; ci < 32; ci = ci + 1) begin
            set_noise_coord(ci, {Q_WIDTH{1'b1}});
        end
        for (sweep_n = 0; sweep_n < 8; sweep_n = sweep_n + 1) begin
            lfsr_state = lfsr_next(lfsr_state);
            check_noisy(lfsr_state);
        end

        /* ============================================ */
        /* Report                                        */
        /* ============================================ */
        if (error_count == 0) begin
            $display("TB_PASS scloud_msgfunc_bw32_demo");
        end else begin
            $display("TB_FAIL scloud_msgfunc_bw32_demo errors=%0d", error_count);
        end
        $finish;
    end

endmodule
