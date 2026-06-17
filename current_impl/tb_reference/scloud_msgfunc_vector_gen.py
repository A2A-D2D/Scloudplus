#!/usr/bin/env python3
"""
Generate Scloud+ MsgFunc test vectors using the C-aligned Python reference.

Produces $readmemh-compatible .mem files that can be loaded by Verilog
testbenches for RTL vs software/C-model cross-validation.

The Python reference mirrors the openHiTLS C model in rtl/cmodel/scloudplus_util.c:
  - ss=16: tau=3, mu=64 bits/block, muConut=2, logq=12 -> 16-byte messages
  - ss=24: tau=4, mu=96 bits/block, muConut=2, logq=12 -> 24-byte messages
  - ss=32: tau=3, mu=64 bits/block, muConut=4, logq=12 -> 32-byte messages

Usage:
  python tb/scripts/scloud_msgfunc_vector_gen.py --ss 16 --num 256 --seed 42
  python tb/scripts/scloud_msgfunc_vector_gen.py --ss all --num 128
  python tb/scripts/scloud_msgfunc_vector_gen.py --ss all --suite exhaustive --num 512
"""

import argparse
import random
import sys
from pathlib import Path
from typing import List, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

from scloud_msgfunc_sw_ref import (  # noqa: E402
    PARAM_SETS,
    msgfunc_encode,
    msgfunc_decode,
    add_noise,
    BW_COMPLEX_LEN,
    MOD_Q,
)


def _pattern_bytes(pattern: int, total_msg_bytes: int) -> bytes:
    return bytes([pattern & 0xFF] * total_msg_bytes)


def _ramp_bytes(total_msg_bytes: int, start: int = 0, step: int = 1) -> bytes:
    return bytes(((start + i * step) & 0xFF) for i in range(total_msg_bytes))


def _add_unique_case(cases: List[Tuple[str, bytes]], seen: set,
                     desc: str, msg: bytes):
    if msg not in seen:
        seen.add(msg)
        cases.append((desc, msg))


def build_message_cases(total_msg_bytes: int, num_vectors: int, seed: int,
                        suite: str) -> List[Tuple[str, bytes]]:
    """Build diverse messages for C/RTL comparison.

    The deterministic prefix targets bit-packing boundaries. Any remaining
    slots are filled with reproducible pseudo-random messages.
    """
    if num_vectors < 1:
        raise ValueError("--num must be >= 1")

    rng = random.Random(seed)
    cases: List[Tuple[str, bytes]] = []
    seen = set()
    total_bits = total_msg_bytes * 8

    def add(desc: str, msg: bytes):
        _add_unique_case(cases, seen, desc, msg)

    if suite == "random":
        while len(cases) < num_vectors:
            add(f"random_{len(cases):04d}",
                bytes(rng.randint(0, 255) for _ in range(total_msg_bytes)))
        return cases

    add("all_zero", bytes(total_msg_bytes))
    add("all_one", _pattern_bytes(0xFF, total_msg_bytes))
    add("repeat_aa", _pattern_bytes(0xAA, total_msg_bytes))
    add("repeat_55", _pattern_bytes(0x55, total_msg_bytes))
    add("repeat_33", _pattern_bytes(0x33, total_msg_bytes))
    add("repeat_cc", _pattern_bytes(0xCC, total_msg_bytes))
    add("repeat_0f", _pattern_bytes(0x0F, total_msg_bytes))
    add("repeat_f0", _pattern_bytes(0xF0, total_msg_bytes))
    add("ascending_bytes", _ramp_bytes(total_msg_bytes, 0x00, 1))
    add("descending_bytes", _ramp_bytes(total_msg_bytes, 0xFF, -1))
    add("odd_stride_bytes", _ramp_bytes(total_msg_bytes, 0x13, 0x25))

    magic = bytes.fromhex(
        "0123456789abcdeffedcba9876543210"
        "deadbeefcafebabe5a5aa5a53cc3c33c"
    )
    add("magic_prefix", magic[:total_msg_bytes])
    add("magic_suffix", magic[-total_msg_bytes:])

    half = total_msg_bytes // 2
    add("low_half_one", bytes(half) + bytes([0xFF] * (total_msg_bytes - half)))
    add("high_half_one", bytes([0xFF] * half) + bytes(total_msg_bytes - half))

    for byte_idx in range(total_msg_bytes):
        msg = bytearray(total_msg_bytes)
        msg[byte_idx] = 0xFF
        add(f"byte_{byte_idx:02d}_ff", bytes(msg))

    selected_bits = [
        0, 1, 2, 3, 4, 5, 6, 7,
        8, 15, 16, 23, 24, 31, 32,
        47, 48, 63, 64, 79, 80, 95,
        total_bits // 2, total_bits - 2, total_bits - 1,
    ]
    selected_bits = sorted({bit for bit in selected_bits if 0 <= bit < total_bits})
    walk_bits = list(range(total_bits)) if suite == "exhaustive" else selected_bits

    for bit in walk_bits:
        add(f"walking1_bit_{bit:03d}", (1 << bit).to_bytes(total_msg_bytes, "big"))

    for bit in walk_bits:
        mask = ((1 << total_bits) - 1) & ~(1 << bit)
        add(f"walking0_bit_{bit:03d}", mask.to_bytes(total_msg_bytes, "big"))

    if len(cases) > num_vectors:
        return cases[:num_vectors]

    while len(cases) < num_vectors:
        add(f"random_{len(cases):04d}",
            bytes(rng.randint(0, 255) for _ in range(total_msg_bytes)))

    return cases


def generate_vectors(ss_level: int, num_vectors: int, seed: int = 42,
                     noise_level: int = 0, suite: str = "mixed"):
    """Generate (msg, noise) pairs with expected outputs."""
    cfg = PARAM_SETS[ss_level]
    mu_bytes = cfg["mu"] // 8
    mu_conut = cfg["mu_conut"]
    total_msg_bytes = mu_bytes * mu_conut
    total_coords = mu_conut * BW_COMPLEX_LEN * 2

    rng = random.Random(seed ^ 0x5C10D)
    msg_cases = build_message_cases(total_msg_bytes, num_vectors, seed, suite)

    vectors = {
        "case": [],
        "msg": [],
        "noise": [],
        "enc_q": [],
        "noisy_q": [],
        "rounded_q": [],
        "msg_out": [],
    }

    for case_desc, msg in msg_cases:
        if noise_level > 0:
            noise = [(rng.randint(-noise_level, noise_level) & MOD_Q)
                     for _ in range(total_coords)]
        else:
            noise = [0] * total_coords

        enc_q = msgfunc_encode(msg, ss_level)
        noisy_q = add_noise(enc_q, noise)
        rounded_q, msg_out = msgfunc_decode(noisy_q, ss_level)

        vectors["case"].append(case_desc)
        vectors["msg"].append(msg)
        vectors["noise"].append(noise)
        vectors["enc_q"].append(enc_q)
        vectors["noisy_q"].append(noisy_q)
        vectors["rounded_q"].append(rounded_q)
        vectors["msg_out"].append(msg_out)

    return vectors


def write_mem_files(output_dir: Path, ss_level: int, vectors: dict,
                    suite: str, seed: int, noise_level: int):
    """Write vectors to $readmemh-compatible .mem files."""
    output_dir.mkdir(parents=True, exist_ok=True)

    cfg = PARAM_SETS[ss_level]
    hex_digits_q = (cfg["logq"] + 3) // 4
    n_coords = len(vectors["enc_q"][0])

    for key in ["msg", "msg_out"]:
        path = output_dir / f"ss{ss_level}_{key}.mem"
        with open(path, "w", encoding="ascii") as f:
            for val in vectors[key]:
                f.write(f"{val.hex()}\n")
        print(f"  Wrote {path} ({len(vectors[key])} entries)")

    for key in ["noise", "enc_q", "noisy_q", "rounded_q"]:
        path = output_dir / f"ss{ss_level}_{key}_flat.mem"
        with open(path, "w", encoding="ascii") as f:
            for flat_list in vectors[key]:
                for val in flat_list:
                    f.write(f"{val & MOD_Q:0{hex_digits_q}x}\n")
        print(f"  Wrote {path} ({len(vectors[key]) * n_coords} entries)")

    summary_path = output_dir / f"ss{ss_level}_info.txt"
    with open(summary_path, "w", encoding="ascii") as f:
        f.write(f"# ss={ss_level} MsgFunc vectors (C-model aligned)\n")
        f.write(f"# num_vectors={len(vectors['msg'])}\n")
        f.write(f"# suite={suite} seed={seed} noise_level={noise_level}\n")
        f.write(f"# tau={cfg['tau']} logq={cfg['logq']} "
                f"mu={cfg['mu']} muConut={cfg['mu_conut']}\n")
        f.write(f"# msg_bytes={cfg['mu'] * cfg['mu_conut'] // 8} "
                f"n_coords={n_coords}\n")
    print(f"  Wrote {summary_path}")

    meta_path = output_dir / f"ss{ss_level}_meta.txt"
    with open(meta_path, "w", encoding="ascii") as f:
        f.write("# idx case decode msg msg_out\n")
        for idx, (case_desc, msg, msg_out) in enumerate(
                zip(vectors["case"], vectors["msg"], vectors["msg_out"])):
            status = "PASS" if msg == msg_out else "FAIL"
            f.write(f"{idx:04d} {case_desc} {status} {msg.hex()} {msg_out.hex()}\n")
    print(f"  Wrote {meta_path} ({len(vectors['case'])} entries)")


def main():
    parser = argparse.ArgumentParser(
        description="Generate Scloud+ MsgFunc test vectors (C-model aligned SW reference)")
    parser.add_argument("--ss", type=str, default="16",
                        help="Security level: 16, 24, 32, or 'all'")
    parser.add_argument("--num", type=int, default=256,
                        help="Number of test vectors")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed")
    parser.add_argument("--noise-level", type=int, default=0,
                        help="Max signed noise amplitude per coordinate (0=zero noise)")
    parser.add_argument("--suite", choices=["mixed", "random", "exhaustive"],
                        default="mixed",
                        help=("Message suite: mixed=corner + selected walking + random, "
                              "random=random only, exhaustive=corner + all walking + random"))
    parser.add_argument("--output-dir", type=str,
                        default="tb/vectors/msgfunc_sw",
                        help="Output directory for .mem files")
    args = parser.parse_args()

    ss_list = [16, 24, 32] if args.ss == "all" else [int(args.ss)]
    repo_root = Path(__file__).resolve().parents[2]
    output_dir = repo_root / args.output_dir

    print("=== Scloud+ MsgFunc Vector Generator (C-model aligned) ===")
    print(f"  Security levels: {ss_list}")
    print(f"  Vectors per level: {args.num}")
    print(f"  Message suite: {args.suite}")
    print(f"  Seed: {args.seed}")
    print(f"  Noise level: {args.noise_level}")
    print(f"  Output: {output_dir}")
    print()

    for ss_level in ss_list:
        cfg = PARAM_SETS[ss_level]
        seed = args.seed + ss_level * 1000
        print(f"--- ss={ss_level} (tau={cfg['tau']}, mu={cfg['mu']}, "
              f"muConut={cfg['mu_conut']}) ---")
        vectors = generate_vectors(ss_level, args.num, seed,
                                   args.noise_level, args.suite)
        write_mem_files(output_dir, ss_level, vectors, args.suite,
                        seed, args.noise_level)

        correct = sum(1 for m, mo in zip(vectors["msg"], vectors["msg_out"])
                      if m == mo)
        total = len(vectors["msg"])
        expected = "PASS" if correct == total else f"{total - correct} errors"
        print(f"  Decode: {correct}/{total} ({expected})")
        print()

    print("=== Done ===")


if __name__ == "__main__":
    main()
