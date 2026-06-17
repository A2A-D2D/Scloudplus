#!/usr/bin/env python3
"""
Scloud+ MsgFunc comprehensive test vector generator.
Cross-check: Python SW ref vs C model vs RTL.

Usage:
  python tb/scripts/scloud_msgfunc_verify.py > verify_output.txt
"""

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scloud_msgfunc_sw_ref import (
    labeling_compute_v, labeling_compute_w,
    delabeling_recover_w, delabeling_compute_u,
    bdd_decode_bwn, msgfunc_encode_block, msgfunc_decode_block,
    add_noise, Complex, BW_COMPLEX_LEN, MOD_Q, PARAM_SETS,
    round_to_delta, msgfunc_encode, msgfunc_decode,
)

PASS = "PASS"
FAIL = "FAIL"


def banner(title, char="="):
    print(f"\n{char * 78}")
    print(f"  {title}")
    print(f"{char * 78}")


def sub_banner(title):
    print(f"\n  --- {title} ---")


def dump_q_flat(w, label="", qw=12):
    """Dump flat Q-domain array as hex."""
    if label:
        print(f"  {label}:")
    for row in range(4):
        vals = []
        for col in range(8):
            idx = row * 8 + col
            vals.append(f"[{idx:2d}]=0x{w[idx]:03x}")
        print(f"    " + "  ".join(vals))


def dump_labels(v, tau, label=""):
    """Dump label vector."""
    bits_w = tau
    if label:
        print(f"  {label}:")
    print(f"  {'idx':>4} {'WH':>3}  {'re':>6} {'im':>6}  {'re_bin':>8} {'im_bin':>8}")
    for i in range(16):
        wh = i.bit_count()
        re_b = max(0, tau - wh // 2)
        im_b = max(0, tau - (wh + 1) // 2)
        re_str = f"0b{v[i].real:0{re_b}b}" if re_b > 0 else "-"
        im_str = f"0b{v[i].imag:0{im_b}b}" if im_b > 0 else "-"
        print(f"  [{i:2d}] WH={wh}  {v[i].real:>6} {v[i].imag:>6}  {re_str:>8} {im_str:>8}")


def encode_pipeline_dump(msg_hex, tau, logq=12):
    """Dump all encode intermediate values."""
    msg = bytes.fromhex(msg_hex)
    mu_bytes = 8 if tau == 3 else 12
    msg = msg[:mu_bytes].ljust(mu_bytes, b'\x00')

    banner(f"ENCODE tau={tau} msg={msg.hex()}")

    # Step 1: msg_to_label
    v = labeling_compute_v(msg, tau)
    dump_labels(v, tau, "Step1: msg_to_label output")

    # Step 2: phi_encode (manual to show intermediates)
    phi = Complex(1, 1)
    tmp = [Complex(v[i].real, v[i].imag) for i in range(16)]
    # stage 1 (step=1)
    for i in range(8):
        tmp[2*i+1] = Complex(
            tmp[2*i].real + tmp[2*i+1].real - tmp[2*i+1].imag,
            tmp[2*i].imag + tmp[2*i+1].real + tmp[2*i+1].imag)
    # stage 2 (step=2)
    for i in range(4):
        for j in [2, 3]:
            idx, left = 4*i+j, 4*i+(j%2)
            tmp[idx] = Complex(
                tmp[left].real + tmp[idx].real - tmp[idx].imag,
                tmp[left].imag + tmp[idx].real + tmp[idx].imag)
    # stage 3 (step=4)
    for i in range(2):
        for j in [4, 5, 6, 7]:
            idx, left = 8*i+j, 8*i+(j%4)
            tmp[idx] = Complex(
                tmp[left].real + tmp[idx].real - tmp[idx].imag,
                tmp[left].imag + tmp[idx].real + tmp[idx].imag)
    # stage 4 (step=8)
    for i in range(8):
        tmp[8+i] = Complex(
            tmp[i].real + tmp[8+i].real - tmp[8+i].imag,
            tmp[i].imag + tmp[8+i].real + tmp[8+i].imag)

    tau_mask = (1 << tau) - 1
    print(f"  Step2: phi_encode output (low {tau} bits -> label_to_q):")
    print(f"  {'idx':>4}  {'full_re':>8} {'full_im':>8}  "
          f"  {'tau_re':>6}  {'tau_im':>6}")
    for i in range(16):
        r = tmp[i].real & tau_mask
        im = tmp[i].imag & tau_mask
        print(f"  [{i:2d}]  {tmp[i].real:>8} {tmp[i].imag:>8}  "
              f"  {fmt_bits(r, tau):>6}  {fmt_bits(im, tau):>6}")

    # Step 3: label_to_q
    w = labeling_compute_w(v, logq, tau)
    dump_q_flat(w, "Step3: label_to_q (Q-domain codeword)")

    return w


def decode_pipeline_dump(noisy_flat, tau, logq=12):
    """Dump all decode intermediate values."""
    banner(f"DECODE tau={tau}")

    bwn = 32
    enc_msg = [Complex(noisy_flat[2*i], noisy_flat[2*i+1]) for i in range(16)]

    # Step 1: BDD
    w_dec = bdd_decode_bwn(enc_msg, bwn, logq, tau)
    q_shift = logq - tau

    # Show BDD input vs output comparison
    print(f"  Step1: BDD (target -> decoded), q_shift={q_shift}:")
    print(f"  {'idx':>4} {'target':>8} {'decoded':>8}  "
          f"{'t_label':>8} {'d_label':>8}  {'match':>6}")
    matches = 0
    for i in range(32):
        t_val = noisy_flat[i]
        d_idx = i // 2
        d_val = w_dec[d_idx].real if i % 2 == 0 else w_dec[d_idx].imag
        t_label = t_val >> q_shift
        d_label = d_val >> q_shift
        m = "OK" if t_val == d_val else "DIFF"
        if t_val == d_val:
            matches += 1
        print(f"  [{i:2d}] {fmt_hex(t_val,12):>8} {fmt_hex(d_val,12):>8}  "
              f"{t_label:>8} {d_label:>8}  {m:>6}")
    print(f"  BDD corrections: {32-matches}/32 coords changed")

    # Step 2: Q-to-label + inverse phi + reduce
    u = delabeling_recover_w(w_dec, logq, tau)
    dump_labels(u, tau, "Step2: phi_decode + DelabelingReduceW output")

    # Step 3: label_to_msg
    msg_out = delabeling_compute_u(u, tau)
    print(f"\n  Step3: label_to_msg -> recovered message:")
    print(f"  msg = {msg_out.hex()}")
    for i, b in enumerate(msg_out):
        print(f"  m[{i}] = 0x{b:02x}  (0b{b:08b})")

    return msg_out


def fmt_bits(val, w):
    if w == 0:
        return "-"
    return f"0b{val:0{w}b}"


def fmt_hex(val, w):
    return f"0x{val:0{(w+3)//4}x}"


def noise_test(msg_hex, noise_vals, tau, logq=12):
    """Encode -> add specific noise -> decode, show full pipeline."""
    msg = bytes.fromhex(msg_hex)
    mu_bytes = 8 if tau == 3 else 12
    msg = msg[:mu_bytes].ljust(mu_bytes, b'\x00')

    banner(f"NOISE TEST tau={tau} msg={msg.hex()}")

    # Encode
    w = encode_pipeline_dump(msg_hex, tau, logq)

    # Add noise
    noisy = [(w[i] + noise_vals[i]) & MOD_Q for i in range(32)]

    print(f"\n  Added noise per coord:")
    for row in range(4):
        vals = []
        for col in range(8):
            idx = row * 8 + col
            vals.append(f"[{idx:2d}]=+{noise_vals[idx]:4d}")
        print(f"    " + "  ".join(vals))

    dump_q_flat(noisy, "Noisy Q-domain values")

    # Decode
    msg_out = decode_pipeline_dump(noisy, tau, logq)

    ok = (msg_out == msg)
    print(f"\n  >>> RESULT: {PASS if ok else FAIL} <<<")
    return ok


# ==============================================================================
# Main verification suite
# ==============================================================================

def main():
    print("=" * 78)
    print("  Scloud+ MsgFunc COMPREHENSIVE VERIFICATION VECTORS")
    print("  Python SW Ref (matches C model) -> RTL Cross-Check")
    print("=" * 78)

    # ============================================================
    # TAU=3 complete pipeline dumps
    # ============================================================
    banner("TAU=3 COMPLETE PIPELINE EXAMPLES", "#")

    # Zero message
    encode_pipeline_dump("0000000000000000", tau=3)
    decode_pipeline_dump([0]*32, tau=3)

    # All-ones message
    encode_pipeline_dump("FFFFFFFFFFFFFFFF", tau=3)
    w_allones = msgfunc_encode_block(bytes([0xFF]*8), tau=3)
    decode_pipeline_dump(w_allones, tau=3)

    # Known pattern
    encode_pipeline_dump("0123456789ABCDEF", tau=3)
    w_pat = msgfunc_encode_block(bytes.fromhex("0123456789ABCDEF"), tau=3)
    decode_pipeline_dump(w_pat, tau=3)

    # ============================================================
    # TAU=3 Walking-1 bit test (64 bits)
    # ============================================================
    banner("TAU=3 WALKING-1: 64 individual message bits", "#")
    print(f"  {'bit':>4}  {'msg_hex':<18}  {'#nonzero_labels':>16}  {'roundtrip':>10}")
    print(f"  {'-'*54}")
    failures = 0
    for bit in range(64):
        msg_int = 1 << bit
        msg_hex = f"{msg_int:016x}"
        msg = bytes.fromhex(msg_hex)
        v = labeling_compute_v(msg, 3)
        non_zero = sum(1 for i in range(16) if v[i].real != 0 or v[i].imag != 0)
        w = labeling_compute_w(v, 12, 3)
        _, mo = msgfunc_decode_block(w, 3)
        ok = PASS if mo == msg else FAIL
        if ok == FAIL:
            failures += 1
        print(f"  [{bit:2d}]  {msg_hex}  {non_zero:>16}  {ok:>10}")
    print(f"  Total failures: {failures}/64")

    # ============================================================
    # TAU=3 Noise resilience: walking-1 with small noise
    # ============================================================
    banner("TAU=3 NOISE RESILIENCE: Walking-1 + noise(D/4=128)", "#")
    rng = random.Random(42)
    for bit in [0, 7, 15, 31, 47, 63]:
        msg_int = 1 << bit
        msg_hex = f"{msg_int:016x}"
        noise = [rng.randint(0, 128) for _ in range(32)]
        noise_test(msg_hex, noise, tau=3)

    # ============================================================
    # TAU=3 Special message patterns
    # ============================================================
    banner("TAU=3 SPECIAL MESSAGE PATTERNS", "#")
    patterns = [
        ("0000000000000001", "LSB only"),
        ("8000000000000000", "MSB only (bit 63)"),
        ("0123456789ABCDEF", "Ascending nibbles"),
        ("FEDCBA9876543210", "Descending nibbles"),
        ("AAAAAAAAAAAAAAAA", "0b1010 repeating"),
        ("5555555555555555", "0b0101 repeating"),
        ("3333333333333333", "0b0011 repeating"),
        ("DEADBEEFCAFEBABE", "Magic pattern"),
    ]
    for msg_hex, desc in patterns:
        sub_banner(desc)
        encode_pipeline_dump(msg_hex, tau=3)

    # ============================================================
    # TAU=4 Tests
    # ============================================================
    banner("TAU=4 PIPELINE EXAMPLES", "#")
    encode_pipeline_dump("000000000000000000000000", tau=4)
    encode_pipeline_dump("FFFFFFFFFFFFFFFFFFFFFFFF", tau=4)
    encode_pipeline_dump("0123456789ABCDEFFEDCBA987654321001122334", tau=4)

    # Walking-1 for tau=4 (key bits)
    banner("TAU=4 WALKING-1: key bit positions", "#")
    for bit in [0, 23, 47, 71, 95]:
        msg_int = 1 << bit
        msg_hex = f"{msg_int:024x}"
        msg = bytes.fromhex(msg_hex)
        v = labeling_compute_v(msg, 4)
        w = labeling_compute_w(v, 12, 4)
        _, mo = msgfunc_decode_block(w, 4)
        ok = PASS if mo == msg else FAIL
        print(f"  bit[{bit:2d}] msg=...{msg_hex[-8:]} roundtrip: {ok}")

    # ============================================================
    # BDD rounding boundary tests
    # ============================================================
    banner("BDD ROUNDING BOUNDARY (tau=3, Delta=512)", "#")
    print(f"  {'input':>6}  {'BDD_output':>10}  {'expected':>10}  {'match':>6}")
    print(f"  {'-'*40}")
    for b in [0, 128, 255, 256, 257, 384, 511, 512, 513, 640, 767, 768, 769, 896, 1023, 1024]:
        t = [Complex(b, 0) for _ in range(16)]
        w = bdd_decode_bwn(t, 32, 12, 3)
        exp = round_to_delta(b, 12, 3)
        ok = PASS if w[0].real == exp else FAIL
        print(f"  {b:>6}  {w[0].real:>10}  {exp:>10}  {ok:>6}")

    # ============================================================
    # Phi symmetry test
    # ============================================================
    banner("PHI SYMMETRY: encode->decode identity (tau=3)", "#")
    rng = random.Random(12345)
    all_ok = True
    for ti in range(16):
        msg = bytes(rng.randint(0, 255) for _ in range(8))
        v = labeling_compute_v(msg, 3)
        # Manual phi encode + decode + reduce
        phi = Complex(1, 1)
        te = [Complex(v[i].real, v[i].imag) for i in range(16)]
        # Encode stages
        for i in range(8):
            te[2*i+1] = Complex(te[2*i].real + te[2*i+1].real - te[2*i+1].imag,
                               te[2*i].imag + te[2*i+1].real + te[2*i+1].imag)
        for i in range(4):
            for j in [2, 3]:
                idx, left = 4*i+j, 4*i+(j%2)
                te[idx] = Complex(te[left].real + te[idx].real - te[idx].imag,
                                  te[left].imag + te[idx].real + te[idx].imag)
        for i in range(2):
            for j in [4,5,6,7]:
                idx, left = 8*i+j, 8*i+(j%4)
                te[idx] = Complex(te[left].real + te[idx].real - te[idx].imag,
                                  te[left].imag + te[idx].real + te[idx].imag)
        for i in range(8):
            te[8+i] = Complex(te[i].real + te[8+i].real - te[8+i].imag,
                              te[i].imag + te[8+i].real + te[8+i].imag)
        # Decode stages (inverse)
        td = [Complex(te[i].real, te[i].imag) for i in range(16)]
        for i in range(8):
            d = Complex(td[8+i].real - td[i].real, td[8+i].imag - td[i].imag)
            td[8+i] = Complex((d.real + d.imag) >> 1, (d.imag - d.real) >> 1)
        for i in range(2):
            for j in [4,5,6,7]:
                idx, left = 8*i+j, 8*i+(j%4)
                d = Complex(td[idx].real - td[left].real, td[idx].imag - td[left].imag)
                td[idx] = Complex((d.real + d.imag) >> 1, (d.imag - d.real) >> 1)
        for i in range(4):
            for j in [2,3]:
                idx, left = 4*i+j, 4*i+(j%2)
                d = Complex(td[idx].real - td[left].real, td[idx].imag - td[left].imag)
                td[idx] = Complex((d.real + d.imag) >> 1, (d.imag - d.real) >> 1)
        for i in range(8):
            d = Complex(td[2*i+1].real - td[2*i].real, td[2*i+1].imag - td[2*i].imag)
            td[2*i+1] = Complex((d.real + d.imag) >> 1, (d.imag - d.real) >> 1)
        # Reduce
        from scloud_msgfunc_sw_ref import delabeling_reduce_w
        u_dec = delabeling_reduce_w(td, 3)
        match = all(u_dec[i].real == v[i].real and u_dec[i].imag == v[i].imag
                   for i in range(16))
        if not match:
            all_ok = False
            print(f"  MISMATCH[{ti}]: msg={msg.hex()}")
            for i in range(16):
                if u_dec[i].real != v[i].real or u_dec[i].imag != v[i].imag:
                    print(f"    [{i:2d}] orig=({v[i].real},{v[i].imag}) "
                          f"dec=({u_dec[i].real},{u_dec[i].imag})")
    print(f"  Result: {PASS if all_ok else FAIL}")

    # ============================================================
    # Noise sweep
    # ============================================================
    banner("NOISE SWEEP (tau=3, Delta=512)", "#")
    rng = random.Random(999)
    for noise_name, noise_max in [
        ("zero", 0), ("D/8 (64)", 64), ("D/4 (128)", 128),
        ("D/2 (256)", 256), ("3D/4 (384)", 384), ("D (512)", 512),
    ]:
        errors = 0
        n_tests = 128
        for _ in range(n_tests):
            msg = bytes(rng.randint(0, 255) for _ in range(8))
            w = msgfunc_encode_block(msg, 3, 12)
            noise = [rng.randint(0, noise_max) if noise_max > 0 else 0 for _ in range(32)]
            noisy = [(w[i] + noise[i]) & MOD_Q for i in range(32)]
            _, mo = msgfunc_decode_block(noisy, 3)
            if mo != msg:
                errors += 1
        pct = 100 * (n_tests - errors) / n_tests
        print(f"  {noise_name:<16}: {n_tests-errors:>3}/{n_tests} OK ({pct:.1f}%)"
              f"{'  <-- should be 100%' if noise_max <= 128 and errors > 0 else ''}")

    # ============================================================
    # Multi-block (ss=16/24/32) roundtrip
    # ============================================================
    banner("MULTI-BLOCK ROUNDTRIP (ss=16,24,32)", "#")
    rng = random.Random(777)
    for ss in [16, 24, 32]:
        cfg = PARAM_SETS[ss]
        msg_bytes = cfg["mu"] * cfg["mu_conut"] // 8
        errors = 0
        for _ in range(64):
            msg = bytes(rng.randint(0, 255) for _ in range(msg_bytes))
            q = msgfunc_encode(msg, ss)
            _, mo = msgfunc_decode(q, ss)
            if msg != mo:
                errors += 1
        print(f"  ss={ss:>2} (tau={cfg['tau']}, muConut={cfg['mu_conut']}, "
              f"{msg_bytes}B msg): {PASS if errors == 0 else FAIL} "
              f"({64-errors}/64)")

    # ============================================================
    # RTL-compatible hex dump
    # ============================================================
    banner("RTL-COMPATIBLE TEST VECTORS ($readmemh format)", "#")
    rng = random.Random(0x5C10D)

    print(f"\n  # === tau=3 vectors (8 per msg block) ===")
    for vi in range(8):
        msg = bytes(rng.randint(0, 255) for _ in range(8))
        v = labeling_compute_v(msg, 3)
        w = msgfunc_encode_block(msg, 3, 12)
        print(f"\n  # Vector tau3_{vi}: msg={msg.hex()}")
        # Dump all intermediate values in RTL signal order
        print(f"  # msg_to_label output (label_flat, tau bits per lane):")
        for i in range(0, 32, 8):
            vals = " ".join(f"{v[i//2].real if i%2==0 else v[i//2].imag:01x}"
                          for i in range(i, min(i+8, 32)))
            print(f"  #   lanes[{i:2d}:{min(i+7,31):2d}] = {vals}")
        print(f"  # label_to_q output (enc_q_flat, Q_WIDTH=12):")
        for i in range(0, 32, 8):
            vals = " ".join(f"{w[i+j]:03x}" for j in range(8))
            print(f"  #   [{i:2d}:{i+7:2d}] = {vals}")

    print(f"\n  # === tau=4 vectors (12 per msg block) ===")
    for vi in range(4):
        msg = bytes(rng.randint(0, 255) for _ in range(12))
        v = labeling_compute_v(msg, 4)
        w = msgfunc_encode_block(msg, 4, 12)
        print(f"\n  # Vector tau4_{vi}: msg={msg.hex()}")
        print(f"  # msg_to_label output (label_flat):")
        for i in range(0, 32, 8):
            vals = " ".join(f"{v[i//2].real if i%2==0 else v[i//2].imag:01x}"
                          for i in range(i, min(i+8, 32)))
            print(f"  #   lanes[{i:2d}:{min(i+7,31):2d}] = {vals}")
        print(f"  # label_to_q output (enc_q_flat):")
        for i in range(0, 32, 8):
            vals = " ".join(f"{w[i+j]:03x}" for j in range(8))
            print(f"  #   [{i:2d}:{i+7:2d}] = {vals}")

    print(f"\n{'=' * 78}")
    print(f"  VERIFICATION COMPLETE")
    print(f"{'=' * 78}")


if __name__ == "__main__":
    main()
