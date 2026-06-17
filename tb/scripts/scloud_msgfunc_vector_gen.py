#!/usr/bin/env python3
"""
Generate Scloud+ MsgFunc test vectors using the C-aligned Python software reference.

Produces $readmemh-compatible .mem files that can be loaded by Verilog
testbenches for RTL vs software cross-validation.

The SW reference now matches the openHiTLS C model in rtl/cmodel/scloudplus_util.c:
  - ss=16: tau=3, mu=64 bits/block, muConut=2, logq=12 → 16-byte messages
  - ss=24: tau=4, mu=96 bits/block, muConut=2, logq=12 → 24-byte messages
  - ss=32: tau=3, mu=64 bits/block, muConut=4, logq=12 → 32-byte messages

Usage:
  python tb/scripts/scloud_msgfunc_vector_gen.py --ss 16 --num 256 --seed 42
  python tb/scripts/scloud_msgfunc_vector_gen.py --ss all --num 128
"""

import argparse
import random
import sys
from pathlib import Path

# Add scripts dir to path for import
sys.path.insert(0, str(Path(__file__).resolve().parent))

from scloud_msgfunc_sw_ref import (
    PARAM_SETS, msgfunc_encode, msgfunc_decode, add_noise,
    msgfunc_encode_block, msgfunc_decode_block,
    BW_COMPLEX_LEN, MOD_Q,
)


def generate_vectors(ss_level: int, num_vectors: int, seed: int = 42,
                     noise_level: int = 0):
    """Generate random (msg, noise) pairs with expected outputs.

    Args:
        ss_level: security level (16, 24, or 32)
        num_vectors: number of test vectors
        seed: random seed
        noise_level: max noise amplitude per coordinate (0 = zero noise)

    Returns dict with keys: msg, noise, enc_q, noisy_q, rounded_q, msg_out
    """
    cfg = PARAM_SETS[ss_level]
    tau = cfg["tau"]
    logq = cfg["logq"]
    mu_bytes = cfg["mu"] // 8
    mu_conut = cfg["mu_conut"]
    total_msg_bytes = mu_bytes * mu_conut
    total_coords = mu_conut * BW_COMPLEX_LEN * 2  # 32 coords per block

    rng = random.Random(seed)

    vectors = {
        "msg": [],
        "noise": [],
        "enc_q": [],
        "noisy_q": [],
        "rounded_q": [],
        "msg_out": [],
    }

    for _ in range(num_vectors):
        msg = bytes(rng.randint(0, 255) for _ in range(total_msg_bytes))
        if noise_level > 0:
            noise = [rng.randint(0, noise_level) for _ in range(total_coords)]
        else:
            noise = [0] * total_coords

        enc_q = msgfunc_encode(msg, ss_level)
        noisy_q = add_noise(enc_q, noise)
        rounded_q, msg_out = msgfunc_decode(noisy_q, ss_level)

        vectors["msg"].append(msg)
        vectors["noise"].append(noise)
        vectors["enc_q"].append(enc_q)
        vectors["noisy_q"].append(noisy_q)
        vectors["rounded_q"].append(rounded_q)
        vectors["msg_out"].append(msg_out)

    return vectors


def write_mem_files(output_dir: Path, ss_level: int, vectors: dict):
    """Write vectors to $readmemh-compatible .mem files.

    File format:
      msg.mem           — one hex byte-string per line
      noise_flat.mem    — one 12-bit hex value per line (flat coords, row-major)
      enc_q_flat.mem    — same layout
      rounded_q_flat.mem — same layout
      msg_out.mem       — one hex byte-string per line
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    cfg = PARAM_SETS[ss_level]
    qw = cfg["logq"]  # logq=12, so values are 12-bit (3 hex digits)
    hex_digits_q = (qw + 3) // 4  # 3
    n_coords = len(vectors["enc_q"][0])

    # Scalar .mem files (one value per line)
    for key in ["msg", "msg_out"]:
        path = output_dir / f"ss{ss_level}_{key}.mem"
        with open(path, "w", encoding="ascii") as f:
            for val in vectors[key]:
                if isinstance(val, bytes):
                    f.write(f"{val.hex()}\n")
                else:
                    f.write(f"{val:0{hex_digits_q}x}\n")
        print(f"  Wrote {path} ({len(vectors[key])} entries)")

    # Flat q-coordinate .mem files (n_coords values per vector, one per line)
    for key in ["noise", "enc_q", "noisy_q", "rounded_q"]:
        path = output_dir / f"ss{ss_level}_{key}_flat.mem"
        with open(path, "w", encoding="ascii") as f:
            for flat_list in vectors[key]:
                for val in flat_list:
                    f.write(f"{val:0{hex_digits_q}x}\n")
        print(f"  Wrote {path} ({len(vectors[key]) * n_coords} entries)")

    # Summary file
    summary_path = output_dir / f"ss{ss_level}_info.txt"
    with open(summary_path, "w", encoding="ascii") as f:
        f.write(f"# ss={ss_level} MsgFunc vectors (C-model aligned)\n")
        f.write(f"# num_vectors={len(vectors['msg'])}\n")
        f.write(f"# tau={cfg['tau']} logq={cfg['logq']} "
                f"mu={cfg['mu']} muConut={cfg['mu_conut']}\n")
        f.write(f"# msg_bytes={cfg['mu']*cfg['mu_conut']//8} "
                f"n_coords={n_coords}\n")
    print(f"  Wrote {summary_path}")


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
                        help="Max noise amplitude per coordinate (0=zero noise)")
    parser.add_argument("--output-dir", type=str,
                        default="tb/vectors/msgfunc_sw",
                        help="Output directory for .mem files")
    args = parser.parse_args()

    ss_list = [16, 24, 32] if args.ss == "all" else [int(args.ss)]

    # Determine output dir relative to repo root
    repo_root = Path(__file__).resolve().parents[2]
    output_dir = repo_root / args.output_dir

    print(f"=== Scloud+ MsgFunc Vector Generator (C-model aligned) ===")
    print(f"  Security levels: {ss_list}")
    print(f"  Vectors per level: {args.num}")
    print(f"  Seed: {args.seed}")
    print(f"  Noise level: {args.noise_level}")
    print(f"  Output: {output_dir}")
    print()

    for ss_level in ss_list:
        cfg = PARAM_SETS[ss_level]
        print(f"--- ss={ss_level} (tau={cfg['tau']}, mu={cfg['mu']}, "
              f"muConut={cfg['mu_conut']}) ---")
        vectors = generate_vectors(ss_level, args.num,
                                   args.seed + ss_level * 1000,
                                   args.noise_level)
        write_mem_files(output_dir, ss_level, vectors)

        # Quick sanity: count correct decodes
        correct = sum(1 for m, mo in zip(vectors["msg"], vectors["msg_out"])
                      if m == mo)
        total = len(vectors["msg"])
        expected = "PASS" if correct == total else f"{total - correct} errors"
        print(f"  Decode: {correct}/{total} ({expected})")
        print()

    print("=== Done ===")


if __name__ == "__main__":
    main()
