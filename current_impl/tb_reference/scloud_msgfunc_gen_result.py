#!/usr/bin/env python3
"""
Generate organized verification results for Scloud+ MsgFunc.

Output directory: tb/vectors/verify_result/
  00_params.txt              - official parameter regroup summary
  01_stress_summary.txt      - randomized message/noise summary
  02_process_compare_ss16.txt - per-vector process comparison for ss=16
  03_process_compare_ss24.txt - per-vector process comparison for ss=24
  04_process_compare_ss32.txt - per-vector process comparison for ss=32
  05_block_tau3.txt          - block-level tau=3 process vectors
  06_block_tau4.txt          - block-level tau=4 process vectors
  07_noise_sweep.txt         - randomized noise-level sweep
  08_rtl_mem_index.txt       - matching vector_gen commands
  09_summary.txt             - final pass/fail summary
"""

import argparse
import random
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

from scloud_msgfunc_sw_ref import (  # noqa: E402
    BW_COMPLEX_LEN,
    MOD_Q,
    PARAM_SETS,
    Complex,
    bdd_decode_bwn,
    delabeling_compute_u,
    delabeling_recover_w,
    labeling_compute_v,
    labeling_compute_w,
    msgfunc_decode,
    msgfunc_decode_block,
    msgfunc_encode,
    msgfunc_encode_block,
)
from scloud_msgfunc_vector_gen import build_message_cases  # noqa: E402


def qhex(vals: List[int]) -> str:
    return " ".join(f"{v & MOD_Q:03x}" for v in vals)


def bhex(msg: bytes) -> str:
    return msg.hex()


def noise_signed(noise_q: int) -> int:
    return noise_q - 4096 if noise_q & 0x800 else noise_q


def noise_hex_signed(vals: List[int]) -> str:
    return " ".join(f"{noise_signed(v):+d}" for v in vals)


def labels_hex(labels: List[Complex]) -> str:
    out = []
    for item in labels:
        out.append(f"{item.real:x}")
        out.append(f"{item.imag:x}")
    return " ".join(out)


def flatten_complex_q(vals: List[Complex]) -> List[int]:
    out = []
    for item in vals:
        out.append(item.real & MOD_Q)
        out.append(item.imag & MOD_Q)
    return out


def random_noise(rng: random.Random, n_coords: int, amplitude: int) -> List[int]:
    if amplitude <= 0:
        return [0] * n_coords
    return [(rng.randint(-amplitude, amplitude) & MOD_Q) for _ in range(n_coords)]


def add_noise_q(q_vals: List[int], noise_vals: List[int]) -> List[int]:
    return [(q + n) & MOD_Q for q, n in zip(q_vals, noise_vals)]


def block_process(msg_block: bytes, tau: int, logq: int,
                  noise_vals: List[int]) -> Dict[str, object]:
    label_v = labeling_compute_v(msg_block, tau)
    enc_q = msgfunc_encode_block(msg_block, tau, logq)
    noisy_q = add_noise_q(enc_q, noise_vals)
    rounded_q, msg_out = msgfunc_decode_block(noisy_q, tau, logq)

    noisy_complex = [
        Complex(noisy_q[2 * i], noisy_q[2 * i + 1])
        for i in range(BW_COMPLEX_LEN)
    ]
    bdd_complex = bdd_decode_bwn(noisy_complex, BW_COMPLEX_LEN * 2, logq, tau)
    bdd_q = flatten_complex_q(bdd_complex)
    recovered_labels = delabeling_recover_w(bdd_complex, logq, tau)
    recovered_msg = delabeling_compute_u(recovered_labels, tau)

    return {
        "msg": msg_block,
        "tau": tau,
        "logq": logq,
        "label_v": label_v,
        "enc_q": enc_q,
        "noise": noise_vals,
        "noisy_q": noisy_q,
        "bdd_q": bdd_q,
        "rounded_q": rounded_q,
        "recovered_labels": recovered_labels,
        "msg_out": msg_out,
        "recovered_msg": recovered_msg,
        "pass": msg_out == msg_block and recovered_msg == msg_block,
    }


def full_message_process(msg: bytes, ss_level: int, rng: random.Random,
                         noise_amp: int) -> Dict[str, object]:
    cfg = PARAM_SETS[ss_level]
    mu_bytes = cfg["mu"] // 8
    mu_conut = cfg["mu_conut"]
    n_coords = mu_conut * BW_COMPLEX_LEN * 2
    noise = random_noise(rng, n_coords, noise_amp)
    enc_q = msgfunc_encode(msg, ss_level)
    noisy_q = add_noise_q(enc_q, noise)
    rounded_q, msg_out = msgfunc_decode(noisy_q, ss_level)

    blocks = []
    for block_idx in range(mu_conut):
        msg_block = msg[block_idx * mu_bytes:(block_idx + 1) * mu_bytes]
        n0 = block_idx * BW_COMPLEX_LEN * 2
        n1 = n0 + BW_COMPLEX_LEN * 2
        blocks.append(block_process(msg_block, cfg["tau"], cfg["logq"], noise[n0:n1]))

    return {
        "ss": ss_level,
        "cfg": cfg,
        "msg": msg,
        "enc_q": enc_q,
        "noise": noise,
        "noisy_q": noisy_q,
        "rounded_q": rounded_q,
        "msg_out": msg_out,
        "blocks": blocks,
        "pass": msg_out == msg and all(block["pass"] for block in blocks),
    }


class Writer:
    def __init__(self, out_dir: Path):
        self.out_dir = out_dir
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self.f = None

    def open(self, name: str):
        if self.f:
            self.f.close()
        self.f = open(self.out_dir / name, "w", encoding="ascii", newline="\n")
        return self.f

    def close(self):
        if self.f:
            self.f.close()
            self.f = None

    def line(self, text: str = ""):
        self.f.write(text + "\n")

    def h1(self, text: str):
        self.line("=" * 100)
        self.line(text)
        self.line("=" * 100)

    def h2(self, text: str):
        self.line()
        self.line("-" * 100)
        self.line(text)
        self.line("-" * 100)


def write_params(w: Writer):
    w.open("00_params.txt")
    w.h1("Scloud+ MsgFunc Parameter Regroup Summary")
    w.line("These are the C-model aligned official message-function parameter groups.")
    w.line()
    w.line("ss  tau  mu_bits  muConut  msg_bytes  q_coords  block_msg_bytes  block_q_coords")
    w.line("--  ---  -------  -------  ---------  --------  ---------------  --------------")
    for ss in [16, 24, 32]:
        cfg = PARAM_SETS[ss]
        msg_bytes = cfg["mu"] * cfg["mu_conut"] // 8
        block_msg_bytes = cfg["mu"] // 8
        q_coords = cfg["mu_conut"] * BW_COMPLEX_LEN * 2
        w.line(f"{ss:<3} {cfg['tau']:<4} {cfg['mu']:<8} {cfg['mu_conut']:<8} "
               f"{msg_bytes:<10} {q_coords:<9} {block_msg_bytes:<16} {BW_COMPLEX_LEN * 2}")
    w.line()
    w.line("Regroup coverage used by this report:")
    w.line("- ss=16: tau=3, two BW32 blocks, 16-byte messages")
    w.line("- ss=24: tau=4, two BW32 blocks, 24-byte messages")
    w.line("- ss=32: tau=3, four BW32 blocks, 32-byte messages")
    w.line("- block-level tau=3 and tau=4 process vectors are also emitted separately")


def write_process_file(w: Writer, filename: str, ss_level: int,
                       results: List[Tuple[str, Dict[str, object]]],
                       detail_limit: int):
    cfg = PARAM_SETS[ss_level]
    w.open(filename)
    w.h1(f"Process Compare ss={ss_level} tau={cfg['tau']} muConut={cfg['mu_conut']}")
    w.line("Each vector compares C/Python reference process stages used by RTL checking.")
    w.line("Noise values are shown as signed integers, while Q-domain buses are 12-bit hex.")

    total = len(results)
    passed = sum(1 for _, item in results if item["pass"])
    w.line()
    w.line(f"SUMMARY total={total} pass={passed} fail={total - passed}")

    for vec_idx, (case_name, item) in enumerate(results[:detail_limit]):
        w.h2(f"VECTOR {vec_idx:04d} case={case_name} pass={item['pass']}")
        w.line(f"msg      = {bhex(item['msg'])}")
        w.line(f"msg_out  = {bhex(item['msg_out'])}")
        w.line(f"enc_q    = {qhex(item['enc_q'])}")
        w.line(f"noise    = {noise_hex_signed(item['noise'])}")
        w.line(f"noisy_q  = {qhex(item['noisy_q'])}")
        w.line(f"rounded_q= {qhex(item['rounded_q'])}")
        for block_idx, block in enumerate(item["blocks"]):
            w.line()
            w.line(f"  [block {block_idx}] tau={block['tau']} pass={block['pass']}")
            w.line(f"    msg_block        = {bhex(block['msg'])}")
            w.line(f"    msg_to_label     = {labels_hex(block['label_v'])}")
            w.line(f"    enc_q            = {qhex(block['enc_q'])}")
            w.line(f"    noise            = {noise_hex_signed(block['noise'])}")
            w.line(f"    noisy_q          = {qhex(block['noisy_q'])}")
            w.line(f"    BDD rounded_q    = {qhex(block['bdd_q'])}")
            w.line(f"    q_to_label/phi^-1= {labels_hex(block['recovered_labels'])}")
            w.line(f"    msg_out          = {bhex(block['msg_out'])}")


def write_block_file(w: Writer, filename: str, tau: int, msg_bytes: int,
                     seed: int, detail_vectors: int, noise_amp: int):
    rng = random.Random(seed)
    cases = build_message_cases(msg_bytes, detail_vectors, seed, "mixed")
    w.open(filename)
    w.h1(f"Block-Level Process Compare tau={tau} msg_bytes={msg_bytes}")
    failures = 0
    for idx, (case_name, msg) in enumerate(cases):
        noise = random_noise(rng, BW_COMPLEX_LEN * 2, noise_amp)
        item = block_process(msg, tau, 12, noise)
        if not item["pass"]:
            failures += 1
        w.h2(f"BLOCK_VECTOR {idx:04d} case={case_name} pass={item['pass']}")
        w.line(f"msg              = {bhex(item['msg'])}")
        w.line(f"msg_to_label     = {labels_hex(item['label_v'])}")
        w.line(f"enc_q            = {qhex(item['enc_q'])}")
        w.line(f"noise            = {noise_hex_signed(item['noise'])}")
        w.line(f"noisy_q          = {qhex(item['noisy_q'])}")
        w.line(f"BDD rounded_q    = {qhex(item['bdd_q'])}")
        w.line(f"q_to_label/phi^-1= {labels_hex(item['recovered_labels'])}")
        w.line(f"msg_out          = {bhex(item['msg_out'])}")
    w.line()
    w.line(f"SUMMARY total={len(cases)} pass={len(cases) - failures} fail={failures}")


def write_noise_sweep(w: Writer, vectors_per_param: int, seed: int):
    w.open("07_noise_sweep.txt")
    w.h1("Random Message + Random Signed Noise Sweep")
    w.line("Noise is sampled independently per Q coordinate from [-amp, +amp].")
    w.line()
    w.line("ss  tau  amp  total  pass  fail  pass_rate")
    w.line("--  ---  ---  -----  ----  ----  ---------")
    rng = random.Random(seed)
    for ss in [16, 24, 32]:
        cfg = PARAM_SETS[ss]
        msg_bytes = cfg["mu"] * cfg["mu_conut"] // 8
        for amp in [0, 3, 7, 15, 31, 63, 127]:
            fail = 0
            for _ in range(vectors_per_param):
                msg = bytes(rng.randint(0, 255) for _ in range(msg_bytes))
                proc = full_message_process(msg, ss, rng, amp)
                if not proc["pass"]:
                    fail += 1
            passed = vectors_per_param - fail
            rate = 100.0 * passed / vectors_per_param
            w.line(f"{ss:<3} {cfg['tau']:<4} {amp:<4} {vectors_per_param:<6} "
                   f"{passed:<5} {fail:<5} {rate:>6.2f}%")


def write_stress_summary(w: Writer, all_results: Dict[int, List[Tuple[str, Dict[str, object]]]],
                         seed: int, vectors_per_param: int, noise_amp: int):
    w.open("01_stress_summary.txt")
    w.h1("Randomized Stress Summary")
    w.line(f"seed={seed}")
    w.line(f"vectors_per_param={vectors_per_param}")
    w.line(f"detail_noise_amp={noise_amp}")
    w.line()
    w.line("ss  tau  muConut  total  pass  fail")
    w.line("--  ---  -------  -----  ----  ----")
    for ss in [16, 24, 32]:
        cfg = PARAM_SETS[ss]
        results = all_results[ss]
        passed = sum(1 for _, item in results if item["pass"])
        w.line(f"{ss:<3} {cfg['tau']:<4} {cfg['mu_conut']:<8} "
               f"{len(results):<6} {passed:<5} {len(results) - passed:<5}")
    w.line()
    w.line("Message cases include deterministic edge patterns first, then random messages.")
    w.line("Noise is random signed per coordinate for every vector.")


def write_rtl_index(w: Writer, vectors_per_param: int, seed: int, noise_amp: int):
    w.open("08_rtl_mem_index.txt")
    w.h1("RTL .mem Vector Generation Commands")
    w.line("Use these commands to regenerate $readmemh-compatible vectors with the")
    w.line("same randomized message/noise philosophy used by this report.")
    w.line()
    w.line("Full official parameter regroup:")
    w.line(f"python tb/scripts/scloud_msgfunc_vector_gen.py --ss all --num {vectors_per_param} "
           f"--suite mixed --seed {seed} --noise-level {noise_amp} "
           "--output-dir tb/vectors/msgfunc_sw")
    w.line()
    w.line("Deeper walking-bit regroup:")
    w.line(f"python tb/scripts/scloud_msgfunc_vector_gen.py --ss all --num {max(vectors_per_param, 512)} "
           f"--suite exhaustive --seed {seed} --noise-level {noise_amp} "
           "--output-dir tb/vectors/msgfunc_sw_exhaustive")


def write_summary(w: Writer, all_results: Dict[int, List[Tuple[str, Dict[str, object]]]],
                  vectors_per_param: int, detail_vectors: int):
    total = sum(len(v) for v in all_results.values())
    passed = sum(1 for entries in all_results.values() for _, item in entries if item["pass"])
    w.open("09_summary.txt")
    w.h1("Verification Result Summary")
    w.line(f"stress_vectors_total={total}")
    w.line(f"stress_vectors_pass={passed}")
    w.line(f"stress_vectors_fail={total - passed}")
    w.line(f"detail_vectors_per_param={detail_vectors}")
    w.line()
    w.line("Generated files:")
    for path in sorted(w.out_dir.iterdir()):
        if path.is_file() and path.name != "09_summary.txt":
            w.line(f"- {path.name} ({path.stat().st_size} bytes)")
    w.line()
    w.line("OVERALL=" + ("PASS" if passed == total else "FAIL"))


def generate_report(out_dir: Path, vectors_per_param: int, detail_vectors: int,
                    seed: int, noise_amp: int, clean: bool):
    if clean and out_dir.exists():
        shutil.rmtree(out_dir)

    w = Writer(out_dir)
    rng = random.Random(seed)
    all_results: Dict[int, List[Tuple[str, Dict[str, object]]]] = {}

    for ss in [16, 24, 32]:
        cfg = PARAM_SETS[ss]
        msg_bytes = cfg["mu"] * cfg["mu_conut"] // 8
        cases = build_message_cases(msg_bytes, vectors_per_param,
                                    seed + ss * 1000, "mixed")
        entries = []
        for case_name, msg in cases:
            proc = full_message_process(msg, ss, rng, noise_amp)
            entries.append((case_name, proc))
        all_results[ss] = entries

    write_params(w)
    write_stress_summary(w, all_results, seed, vectors_per_param, noise_amp)
    write_process_file(w, "02_process_compare_ss16.txt", 16, all_results[16], detail_vectors)
    write_process_file(w, "03_process_compare_ss24.txt", 24, all_results[24], detail_vectors)
    write_process_file(w, "04_process_compare_ss32.txt", 32, all_results[32], detail_vectors)
    write_block_file(w, "05_block_tau3.txt", 3, 8, seed + 3003, detail_vectors, noise_amp)
    write_block_file(w, "06_block_tau4.txt", 4, 12, seed + 4004, detail_vectors, noise_amp)
    write_noise_sweep(w, max(16, vectors_per_param // 4), seed + 707, )
    write_rtl_index(w, vectors_per_param, seed, noise_amp)
    write_summary(w, all_results, vectors_per_param, detail_vectors)
    w.close()

    print(f"Result files written to {out_dir}")
    for path in sorted(out_dir.iterdir()):
        if path.is_file():
            print(f"  {path.name} ({path.stat().st_size:,} bytes)")


def main():
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Generate randomized Scloud+ MsgFunc verification process reports")
    parser.add_argument("--output-dir", default="tb/vectors/verify_result",
                        help="Output directory relative to repo root")
    parser.add_argument("--vectors-per-param", type=int, default=256,
                        help="Stress vectors per official ss parameter group")
    parser.add_argument("--detail-vectors", type=int, default=16,
                        help="Detailed process vectors written per report")
    parser.add_argument("--seed", type=int, default=0x5C10D,
                        help="Deterministic random seed")
    parser.add_argument("--noise-level", type=int, default=31,
                        help="Signed random noise amplitude for process vectors")
    parser.add_argument("--no-clean", action="store_true",
                        help="Do not remove existing verify_result files first")
    args = parser.parse_args()

    out_dir = repo_root / args.output_dir
    generate_report(out_dir, args.vectors_per_param, args.detail_vectors,
                    args.seed, args.noise_level, clean=not args.no_clean)


if __name__ == "__main__":
    main()
