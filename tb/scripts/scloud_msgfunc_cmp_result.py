#!/usr/bin/env python3
"""
Scloud+ MsgFunc -- Comprehensive C Model vs RTL Comparison Vectors.

Generates rich, diverse test vectors showing every pipeline stage.
Use this to cross-check RTL waveforms against the C model reference.

Usage:
  python tb/scripts/scloud_msgfunc_cmp_result.py > cmp_result.txt
"""

import sys
import random
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scloud_msgfunc_sw_ref import (
    labeling_compute_v, labeling_compute_w,
    delabeling_recover_w, delabeling_compute_u,
    bdd_decode_bwn, msgfunc_encode_block, msgfunc_decode_block,
    Complex, BW_COMPLEX_LEN, MOD_Q, PARAM_SETS,
    round_to_delta, msgfunc_encode, msgfunc_decode,
)

SEP = "=" * 120
SEP2 = "-" * 120


def hex32(vals, w=3):
    """Format 32 values as hex string."""
    return " ".join(f"{v:0{w}x}" for v in vals)


def hex16(vals):
    """Format 16 complex pairs as 're,im' hex."""
    return " ".join(f"{vals[i].real:01x},{vals[i].imag:01x}" for i in range(16))


def label_flat_hex(v, tau):
    """Flatten 16 Complex labels into 32 hex values."""
    flat = []
    for i in range(16):
        flat.append(v[i].real)
        flat.append(v[i].imag)
    return " ".join(f"{x:01x}" for x in flat)


def print_pipeline(msg_bytes, tau, logq, label=""):
    """Print full encode+decode pipeline for one message block."""
    msg_hex = msg_bytes.hex()
    mu = len(msg_bytes)

    print(f"\n{SEP}")
    print(f"  VECTOR: tau={tau}  msg={msg_hex}  ({mu} bytes)  {label}")
    print(f"{SEP}")

    # ===== ENCODE =====
    print(f"\n  ---- ENCODE PIPELINE ----")

    # Input
    print(f"\n  [IN] msg_bytes:")
    for i in range(0, mu, 8):
        chunk = msg_bytes[i:i+8]
        print(f"    m[{i:2d}:{i+7:2d}] = " +
              " ".join(f"0x{b:02x}" for b in chunk) +
              f"   (msg_in[{8*mu-8*i-1}:{8*mu-8*i-8}])")

    # Step 1: msg_to_label
    v = labeling_compute_v(msg_bytes, tau)
    print(f"\n  [STEP1] msg_to_label -> label_flat (C model / Python SW ref):")
    print(f"    coord  WH  re_b  im_b   re_val  im_val    label_flat[2i]  label_flat[2i+1]")
    print(f"    {SEP2[:90]}")
    for i in range(16):
        wh = i.bit_count()
        rb = max(0, tau - wh // 2)
        ib = max(0, tau - (wh + 1) // 2)
        rstr = f"0b{v[i].real:0{rb}b}" if rb > 0 else "0b0"
        istr = f"0b{v[i].imag:0{ib}b}" if ib > 0 else "0b0"
        print(f"    [{i:2d}]   {wh:2d}    {rb:2d}    {ib:2d}    "
              f"0x{v[i].real:01x}    0x{v[i].imag:01x}       "
              f"0x{v[i].real:01x} ({rstr})      0x{v[i].imag:01x} ({istr})")

    # RTL expected label assignment
    print(f"\n  [RTL] Expected label_flat bus (32 lanes x LABEL_WIDTH bits):")
    print(f"    label_flat = {{")
    for row in range(4):
        vals = []
        for col in range(8):
            i = row * 8 + col
            vals.append(f"lane[{i:2d}]=0x{v[i//2].real if i%2==0 else v[i//2].imag:01x}")
        print(f"      " + "  ".join(vals))
    print(f"    }}")

    # Step 2: phi_encode
    phi = Complex(1, 1)
    tmp = [Complex(v[i].real, v[i].imag) for i in range(16)]
    for i in range(8):
        tmp[2*i+1] = Complex(tmp[2*i].real + tmp[2*i+1].real - tmp[2*i+1].imag,
                             tmp[2*i].imag + tmp[2*i+1].real + tmp[2*i+1].imag)
    for i in range(4):
        for j in [2, 3]:
            idx, left = 4*i+j, 4*i+(j%2)
            tmp[idx] = Complex(tmp[left].real + tmp[idx].real - tmp[idx].imag,
                               tmp[left].imag + tmp[idx].real + tmp[idx].imag)
    for i in range(2):
        for j in [4, 5, 6, 7]:
            idx, left = 8*i+j, 8*i+(j%4)
            tmp[idx] = Complex(tmp[left].real + tmp[idx].real - tmp[idx].imag,
                               tmp[left].imag + tmp[idx].real + tmp[idx].imag)
    for i in range(8):
        tmp[8+i] = Complex(tmp[i].real + tmp[8+i].real - tmp[8+i].imag,
                           tmp[i].imag + tmp[8+i].real + tmp[8+i].imag)

    tau_mask = (1 << tau) - 1
    print(f"\n  [STEP2] phi_encode -> enc_label_flat (low {tau} bits -> label_to_q):")
    print(f"    coord   full_re   full_im    re_tau    im_tau")
    print(f"    {SEP2[:60]}")
    for i in range(16):
        print(f"    [{i:2d}]   {tmp[i].real:>8}  {tmp[i].imag:>8}    "
              f"0b{tmp[i].real & tau_mask:0{tau}b}   0b{tmp[i].imag & tau_mask:0{tau}b}")

    # Step 3: label_to_q
    w_enc = labeling_compute_w(v, logq, tau)
    print(f"\n  [STEP3] label_to_q -> enc_q_flat (Q_WIDTH={logq}, 32 coords):")
    for row in range(4):
        vals = "  ".join(f"[{row*8+j:2d}]=0x{w_enc[row*8+j]:03x}" for j in range(8))
        print(f"    {vals}")

    # ===== DECODE =====
    print(f"\n  ---- DECODE PIPELINE (zero noise) ----")

    # Step 4: BDD
    enc_msg = [Complex(w_enc[2*i], w_enc[2*i+1]) for i in range(16)]
    w_dec = bdd_decode_bwn(enc_msg, 32, logq, tau)
    flat_dec = []
    for i in range(16):
        flat_dec.append(w_dec[i].real)
        flat_dec.append(w_dec[i].imag)

    print(f"\n  [STEP4] BDD -> rounded_q_flat (should == enc_q_flat for zero noise):")
    for row in range(4):
        vals = "  ".join(f"[{row*8+j:2d}]=0x{flat_dec[row*8+j]:03x}" for j in range(8))
        print(f"    {vals}")
    bdd_changes = sum(1 for i in range(32) if flat_dec[i] != w_enc[i])
    print(f"    BDD corrections: {bdd_changes}/32 (should be 0 for zero noise)")

    # Step 5: phi_decode + reduce
    u = delabeling_recover_w(w_dec, logq, tau)
    print(f"\n  [STEP5] phi_decode + DelabelingReduceW -> decoded labels:")
    print(f"    coord  WH  re_b  im_b   re_val  im_val")
    print(f"    {SEP2[:52]}")
    for i in range(16):
        wh = i.bit_count()
        rb = max(0, tau - wh // 2)
        ib = max(0, tau - (wh + 1) // 2)
        print(f"    [{i:2d}]   {wh:2d}    {rb:2d}    {ib:2d}    "
              f"0x{u[i].real:01x}    0x{u[i].imag:01x}")

    # Step 6: label_to_msg
    msg_out = delabeling_compute_u(u, tau)
    print(f"\n  [STEP6] label_to_msg -> recovered msg:")
    for i in range(0, mu, 8):
        chunk_out = msg_out[i:i+8]
        chunk_in = msg_bytes[i:i+8]
        match = "OK" if chunk_out == chunk_in else "MISMATCH"
        print(f"    m[{i:2d}:{i+7:2d}] out = " +
              " ".join(f"0x{b:02x}" for b in chunk_out) +
              f"   (in: " +
              " ".join(f"0x{b:02x}" for b in chunk_in) +
              f")  {match}")

    ok = "PASS" if msg_out == msg_bytes else "FAIL"
    print(f"\n  >>> ROUNDTRIP: {ok} <<<")
    return ok


# ==============================================================================
# Main
# ==============================================================================
def main():
    print(SEP)
    print("  Scloud+ MsgFunc -- C MODEL vs RTL COMPARISON VECTORS")
    print("  Python SW ref = bit-exact C model reference")
    print("  Use these vectors to cross-check RTL waveforms stage-by-stage")
    print(SEP)

    tau = 3
    logq = 12

    # =========================================================================
    # SECTION 1: Corner-case messages
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 1: CORNER-CASE MESSAGES (tau={tau})")
    print(f"{'#'*120}")

    corner_msgs = [
        ("00"*8, "all zeros"),
        ("FF"*8, "all ones"),
        ("0000000000000001", "LSB only (bit 0)"),
        ("0000000000000002", "bit 1 only"),
        ("0000000000000004", "bit 2 only"),
        ("8000000000000000", "MSB only (bit 63)"),
        ("0000000000000003", "bits 0,1 (test B[0])"),
        ("0000000000000007", "bits 0,1,2 (test A[0] max = 7)"),
        ("000000000000001C", "bits 2,3,4 (test B[1] + A[3] overlap)"),
        ("0123456789ABCDEF", "ascending nibbles"),
        ("FEDCBA9876543210", "descending nibbles"),
        ("AAAAAAAAAAAAAAAA", "0xAA repeating (0b10101010)"),
        ("5555555555555555", "0x55 repeating (0b01010101)"),
        ("3333333333333333", "0x33 repeating (0b00110011)"),
        ("CCCCCCCCCCCCCCCC", "0xCC repeating (0b11001100)"),
        ("0F0F0F0F0F0F0F0F", "0x0F repeating (0b00001111)"),
        ("F0F0F0F0F0F0F0F0", "0xF0 repeating (0b11110000)"),
        ("DEADBEEFCAFEBABE", "magic DEADBEEF"),
        ("C0FFEE123456789A", "mixed pattern"),
        ("00000000FFFFFFFF", "half zeros, half ones"),
        ("FFFFFFFF00000000", "half ones, half zeros"),
    ]
    for msg_hex, desc in corner_msgs:
        print_pipeline(bytes.fromhex(msg_hex), tau, logq, desc)

    # =========================================================================
    # SECTION 2: Walking-1 and Walking-0
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 2: WALKING-1 and WALKING-0 (tau={tau}, 64 bits)")
    print(f"{'#'*120}")

    print(f"\n  --- Walking-1 (set one bit at a time) ---")
    walk1_fail = 0
    for bit in range(64):
        msg_int = 1 << bit
        msg = msg_int.to_bytes(8, 'big')
        v = labeling_compute_v(msg, tau)
        w_enc = labeling_compute_w(v, logq, tau)
        _, mo = msgfunc_decode_block(w_enc, tau, logq)
        if mo != msg:
            walk1_fail += 1

        # Print detail for selected bits
        if bit in [0, 1, 2, 3, 7, 8, 15, 16, 31, 32, 47, 48, 62, 63] or walk1_fail > 0:
            active = [(i, v[i].real, v[i].imag) for i in range(16)
                      if v[i].real != 0 or v[i].imag != 0]
            active_str = ", ".join(f"c{i}(re={r},im={im})" for i, r, im in active)
            status = "OK" if mo == msg else "FAIL"
            print(f"  bit[{bit:2d}] msg=0x{msg.hex()}  active_labels: {active_str}  {status}")
    print(f"  Walking-1 summary: {64-walk1_fail}/64 OK")

    print(f"\n  --- Walking-0 (clear one bit, all others set) ---")
    walk0_fail = 0
    all_ones = (1 << 64) - 1
    for bit in range(64):
        msg_int = all_ones & ~(1 << bit)
        msg = msg_int.to_bytes(8, 'big')
        v = labeling_compute_v(msg, tau)
        w_enc = labeling_compute_w(v, logq, tau)
        _, mo = msgfunc_decode_block(w_enc, tau, logq)
        if mo != msg:
            walk0_fail += 1
        if bit in [0, 1, 2, 3, 7, 15, 31, 47, 63]:
            status = "OK" if mo == msg else "FAIL"
            print(f"  bit[{bit:2d}]=0 (others=1) msg=0x{msg.hex()[:16]}...  {status}")
    print(f"  Walking-0 summary: {64-walk0_fail}/64 OK")

    # =========================================================================
    # SECTION 3: WH-class isolation
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 3: WALSH-HAMMING CLASS ISOLATION (tau={tau})")
    print(f"  Messages that activate only one WH class at a time")
    print(f"{'#'*120}")

    # WH=0 only: coord[0] has re=3b, im=3b = 6 bits -> msg bits [0:5]
    msg_wh0 = int('111000', 2)  # set max values for WH0 labels
    print_pipeline(msg_wh0.to_bytes(8, 'big'), tau, logq, "WH=0 only (coord[0] re=7,im=0)")

    msg_wh0_full = int('111111', 2)  # all WH0 bits set
    print_pipeline(msg_wh0_full.to_bytes(8, 'big'), tau, logq, "WH=0 only (coord[0] re=7,im=7)")

    # WH=1: coord[1,2,4,8] each re=3b,im=2b = 5 bits -> 4*5=20 bits
    # These occupy msg bits after WH0
    msg_wh1 = (0b111111 << 6) | 0b11111  # fill WH0 + first WH1 coord
    print_pipeline(msg_wh1.to_bytes(8, 'big'), tau, logq, "WH0+WH1 partial")

    # WH=4 only: coord[15] has re=1b,im=1b = 2 bits -> last 2 bits of msg (bits 62,63)
    msg_wh4 = (3 << 62)
    print_pipeline(msg_wh4.to_bytes(8, 'big'), tau, logq, "WH=4 only (coord[15] re=1,im=1)")

    # WH=3 only: coord[7,11,13,14] each re=2b,im=1b = 3 bits -> 4*3=12 bits
    msg_wh3 = (0xFFF << 50)  # set bits in the WH3 region (bits 50-61)
    print_pipeline(msg_wh3.to_bytes(8, 'big'), tau, logq, "WH=3 region active")

    # WH=2: coord[3,5,6,9,10,12] each re=2b,im=2b = 4 bits -> 6*4=24 bits
    msg_wh2 = (0xFFFFFF << 26)  # set bits in the WH2 region (bits 26-49)
    print_pipeline(msg_wh2.to_bytes(8, 'big'), tau, logq, "WH=2 region active")

    # =========================================================================
    # SECTION 4: Label boundary tests
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 4: LABEL BOUNDARY TESTS (tau={tau})")
    print(f"  Messages that produce min/max label values for each WH class")
    print(f"{'#'*120}")

    # For each WH class, design messages that produce label values at boundaries
    label_boundary_msgs = [
        # All zeros -> all labels = 0 (min)
        ("00"*8, "ALL ZERO labels (min boundary)"),
        # All ones -> all labels = max for their bit width
        ("FF"*8, "ALL MAX labels (max boundary)"),
    ]
    for msg_hex, desc in label_boundary_msgs:
        print_pipeline(bytes.fromhex(msg_hex), tau, logq, desc)

    # =========================================================================
    # SECTION 5: Random messages
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 5: RANDOM MESSAGES (tau={tau})")
    print(f"{'#'*120}")

    rng = random.Random(12345)
    for vi in range(8):
        msg = bytes(rng.randint(0, 255) for _ in range(8))
        print_pipeline(msg, tau, logq, f"random #{vi}")

    # =========================================================================
    # SECTION 6: Noise injection tests
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 6: NOISE INJECTION TESTS (tau={tau})")
    print(f"  Encode -> add noise -> BDD decode -> verify")
    print(f"{'#'*120}")

    rng2 = random.Random(999)
    noise_cases = [
        ("0123456789ABCDEF", [
            0, 0, 0, 0, 0, 0, 0, 0,   0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,   0, 0, 0, 0, 0, 0, 0, 0,
        ], "zero noise"),
        ("FEDCBA9876543210", [
            13, 0x3F5, 0, 29, 0x3E1, 0, 0, 41,
            0, 0x3EF, 0, 35, 0, 0, 0x3EB, 0,
            43, 0x3D3, 0, 0, 0, 0, 31, 0x3DF,
            0, 0, 0, 0, 15, 0, 0x3F1, 0,
        ], "structured noise (D/4 level)"),
    ]
    for vi, (msg_hex, noise, desc) in enumerate(noise_cases):
        print(f"\n{SEP}")
        print(f"  NOISE VECTOR {vi}: msg={msg_hex}  noise={desc}")
        print(f"{SEP}")

        msg = bytes.fromhex(msg_hex)
        w_enc = msgfunc_encode_block(msg, tau, logq)
        noisy = [(w_enc[i] + noise[i]) & MOD_Q for i in range(32)]

        print(f"\n  [NOISE] per-coord noise values:")
        for row in range(4):
            vals = "  ".join(f"[{row*8+j:2d}]=+{noise[row*8+j]:4d}" for j in range(8))
            print(f"    {vals}")

        print(f"\n  [COMPARE] enc_q vs noisy_q vs BDD output:")
        enc_msg = [Complex(noisy[2*i], noisy[2*i+1]) for i in range(16)]
        w_dec = bdd_decode_bwn(enc_msg, 32, logq, tau)
        print(f"    {'idx':>4}  {'enc_q':>8}  {'noise':>6}  {'noisy_q':>8}  {'decoded_q':>9}  {'corr?':>6}")
        print(f"    {SEP2[:70]}")
        corrections = 0
        for i in range(32):
            dv = w_dec[i//2].real if i % 2 == 0 else w_dec[i//2].imag
            corr = "FIX" if noisy[i] != dv else "ok"
            if noisy[i] != dv:
                corrections += 1
            print(f"    [{i:2d}]  0x{w_enc[i]:03x}   +{noise[i]:3d}   0x{noisy[i]:03x}     0x{dv:03x}       {corr}")

        _, msg_out = msgfunc_decode_block(noisy, tau, logq)
        print(f"\n    msg_out = {msg_out.hex()}")
        print(f"    msg_in  = {msg.hex()}")
        print(f"    BDD fixed {corrections}/32 coords")
        print(f"    >>> RESULT: {'PASS' if msg_out == msg else 'FAIL'} <<<")

    # =========================================================================
    # SECTION 7: tau=4 vectors
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 7: TAU=4 VECTORS")
    print(f"{'#'*120}")
    tau4 = 4
    tau4_msgs = [
        ("00"*12, "all zeros"),
        ("FF"*12, "all ones"),
        ("0123456789ABCDEFFEDCBA987654321001122334", "full 12-byte pattern"),
        ("000000000000000000000001", "LSB only"),
        ("800000000000000000000000", "MSB only (bit 95)"),
    ]
    for msg_hex, desc in tau4_msgs:
        print_pipeline(bytes.fromhex(msg_hex), tau4, logq, desc)

    rng3 = random.Random(7777)
    for vi in range(4):
        msg = bytes(rng3.randint(0, 255) for _ in range(12))
        print_pipeline(msg, tau4, logq, f"tau=4 random #{vi}")

    # =========================================================================
    # SECTION 8: Multi-block summary (ss=16,24,32)
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 8: MULTI-BLOCK ROUNDTRIP SUMMARY")
    print(f"{'#'*120}")

    rng4 = random.Random(0xBEEF)
    for ss in [16, 24, 32]:
        cfg = PARAM_SETS[ss]
        msg_bytes = cfg["mu"] * cfg["mu_conut"] // 8
        n_tests = 64
        errors = 0
        for _ in range(n_tests):
            msg = bytes(rng4.randint(0, 255) for _ in range(msg_bytes))
            q_enc = msgfunc_encode(msg, ss)
            _, mo = msgfunc_decode(q_enc, ss)
            if msg != mo:
                errors += 1
        print(f"\n  ss={ss:>2}  tau={cfg['tau']}  mu={cfg['mu']}  "
              f"muConut={cfg['mu_conut']}  msg_bytes={msg_bytes}  "
              f"Q_coords={cfg['mu_conut']*32}")
        print(f"    Zero-noise roundtrip: {n_tests-errors}/{n_tests} PASS")

    # =========================================================================
    # SECTION 9: RTL hex dump (compact)
    # =========================================================================
    print(f"\n\n{'#'*120}")
    print(f"  SECTION 9: RTL-COMPATIBLE HEX DUMP (tau=3, sorted by complexity)")
    print(f"  Format: msg | label_flat(32 hex) | enc_q_flat(32 hex)")
    print(f"{'#'*120}")

    rng5 = random.Random(0xAB)
    all_msgs = []

    # Add corner cases
    for msg_hex, _ in corner_msgs[:16]:
        all_msgs.append(bytes.fromhex(msg_hex))
    # Add walking-1 key bits
    for bit in [0, 1, 2, 3, 7, 8, 15, 16, 31, 47, 63]:
        all_msgs.append((1 << bit).to_bytes(8, 'big'))
    # Add random
    for _ in range(16):
        all_msgs.append(bytes(rng5.randint(0, 255) for _ in range(8)))

    for vi, msg in enumerate(all_msgs):
        v = labeling_compute_v(msg, tau)
        w = msgfunc_encode_block(msg, tau, logq)
        lf = label_flat_hex(v, tau)
        qf = hex32(w)
        print(f"  vec[{vi:3d}] msg={msg.hex()} | labels={lf} | q={qf}")

    print(f"\n{SEP}")
    print(f"  COMPARISON COMPLETE -- All vectors generated")
    print(f"{SEP}")


if __name__ == "__main__":
    main()
