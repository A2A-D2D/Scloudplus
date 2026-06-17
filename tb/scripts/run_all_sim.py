#!/usr/bin/env python3
"""
Scloud+ Unified Simulation Runner.

Compiles and runs all Scloud+ RTL testbenches, parses results, and
optionally cross-validates against the Python software reference.

Usage:
  python tb/scripts/run_all_sim.py --cases all
  python tb/scripts/run_all_sim.py --cases bw32 --sw-compare --num-vectors 128
  python tb/scripts/run_all_sim.py --cases all --official --json result.json
"""

import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import List, Optional

# ==============================================================================
# Data classes
# ==============================================================================


@dataclass
class TestbenchCase:
    """One testbench that can be compiled and simulated."""
    name: str
    group: str
    tb_file: str           # relative to repo root
    tb_module: str
    rtl_globs: List[str]   # glob patterns for RTL files, relative to repo root
    iverilog_opts: str = "-g2001"
    timeout_cycles: int = 500
    supports_wave: bool = True
    bw_config: Optional[dict] = None  # for SW comparison


@dataclass
class SimResult:
    """Result of one simulation run."""
    case_name: str
    status: str = "UNKNOWN"    # PASS, FAIL, COMPILE_ERR, TIMEOUT, ERROR
    pass_count: int = 0
    error_count: int = 0
    duration_ms: float = 0.0
    output: str = ""


# ==============================================================================
# ANSI colors
# ==============================================================================

GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
BOLD = "\033[1m"
RESET = "\033[0m"


# ==============================================================================
# Case registry
# ==============================================================================


def _rtl(*paths: str) -> List[str]:
    """Shorthand for rtl/msgfunc paths."""
    return [f"rtl/msgfunc/{p}" for p in paths]


def _scplus(*paths: str) -> List[str]:
    """Shorthand for rtl/scloudplus paths."""
    return [f"rtl/scloudplus/{p}" for p in paths]


def build_registry() -> dict:
    """Build the case registry.

    Returns dict mapping case_name → TestbenchCase.
    """
    cases = {}

    # ── BW8 ──
    cases["bw8_demo"] = TestbenchCase(
        name="bw8_demo", group="bw8",
        tb_file="tb/bw8/tb_scloud_msgfunc_bw8_demo.v",
        tb_module="tb_scloud_msgfunc_bw8_demo",
        rtl_globs=_rtl("bw8/*.v"),
        bw_config={"complex_n": 4, "tau": 2, "q_width": 10, "msg_width": 12},
    )

    # ── BW16 ──
    cases["bw16_demo"] = TestbenchCase(
        name="bw16_demo", group="bw16",
        tb_file="tb/bw16/tb_scloud_msgfunc_bw16_demo.v",
        tb_module="tb_scloud_msgfunc_bw16_demo",
        rtl_globs=_rtl("bw16/*.v"),
        bw_config={"complex_n": 8, "tau": 2, "q_width": 10, "msg_width": 20},
    )

    # ── BW32 Combo ──
    cases["bw32_combo_demo"] = TestbenchCase(
        name="bw32_combo_demo", group="bw32",
        tb_file="tb/bw32_combo/tb_scloud_msgfunc_bw32_demo.v",
        tb_module="tb_scloud_msgfunc_bw32_demo",
        rtl_globs=_rtl("bw32_combo/*.v", "bdd/*.v", "param/*.v"),
        timeout_cycles=2000,
        bw_config={"complex_n": 16, "tau": 2, "q_width": 10, "msg_width": 32},
    )

    # ── BW32 Sequential ──
    cases["bw32_seq"] = TestbenchCase(
        name="bw32_seq", group="bw32",
        tb_file="tb/bw32_seq/tb_scloud_msgfunc_bw32_seq.v",
        tb_module="tb_scloud_msgfunc_bw32_seq",
        rtl_globs=_rtl("bw32_combo/*.v", "bw32_seq/*.v", "bdd/*.v"),
        timeout_cycles=10000,
        bw_config={"complex_n": 16, "tau": 2, "q_width": 10, "msg_width": 32},
    )

    cases["bw32_stress"] = TestbenchCase(
        name="bw32_stress", group="bw32",
        tb_file="tb/bw32_seq/tb_scloud_msgfunc_bw32_stress.v",
        tb_module="tb_scloud_msgfunc_bw32_stress",
        rtl_globs=_rtl("bw32_combo/*.v", "bw32_seq/*.v", "bdd/*.v"),
        timeout_cycles=200000,
        bw_config={"complex_n": 16, "tau": 2, "q_width": 10, "msg_width": 32},
    )

    cases["msgenc_bw32_seq"] = TestbenchCase(
        name="msgenc_bw32_seq", group="bw32",
        tb_file="tb/bw32_seq/tb_scloud_msgenc_bw32_seq.v",
        tb_module="tb_scloud_msgenc_bw32_seq",
        rtl_globs=_rtl("bw32_combo/*.v", "bw32_seq/scloud_msgenc_bw32_seq.v"),
        timeout_cycles=5000,
    )

    cases["msgdec_bw32_seq"] = TestbenchCase(
        name="msgdec_bw32_seq", group="bw32",
        tb_file="tb/bw32_seq/tb_scloud_msgdec_bw32_seq.v",
        tb_module="tb_scloud_msgdec_bw32_seq",
        rtl_globs=_rtl("bw32_combo/*.v", "bw32_seq/scloud_msgdec_bw32_seq.v",
                       "bdd/*.v"),
        timeout_cycles=5000,
    )

    # ── BDD ──
    for n in [4, 8, 16, 32]:
        cases[f"bdd{n}_seq"] = TestbenchCase(
            name=f"bdd{n}_seq", group="bdd",
            tb_file=f"tb/bdd/tb_scloud_bdd{n}_seq.v",
            tb_module=f"tb_scloud_bdd{n}_seq",
            rtl_globs=_rtl("bdd/*.v"),
            timeout_cycles=10000 if n >= 16 else 2000,
        )

    cases["bdd32_seq_smoke"] = TestbenchCase(
        name="bdd32_seq_smoke", group="bdd",
        tb_file="tb/bdd/tb_scloud_bdd32_seq_smoke.v",
        tb_module="tb_scloud_bdd32_seq_smoke",
        rtl_globs=_rtl("bdd/*.v"),
        timeout_cycles=5000,
    )

    cases["bdd32_recursive"] = TestbenchCase(
        name="bdd32_recursive", group="bdd",
        tb_file="tb/bdd/tb_scloud_bdd32_recursive.v",
        tb_module="tb_scloud_bdd32_recursive",
        rtl_globs=_rtl("bdd/*.v"),
        timeout_cycles=200000,
        iverilog_opts="-g2012",
    )

    # ── Parameterized ──
    cases["param"] = TestbenchCase(
        name="param", group="param",
        tb_file="tb/param/tb_scloud_msgfunc_param.v",
        tb_module="tb_scloud_msgfunc_param",
        rtl_globs=_rtl("param/*.v", "bdd/*.v"),
        timeout_cycles=10000,
        bw_config={"complex_n": 16, "tau": 3, "q_width": 12, "msg_width": 64},
    )

    cases["cfg_reg"] = TestbenchCase(
        name="cfg_reg", group="param",
        tb_file="tb/param/tb_scloud_msgfunc_cfg_reg.v",
        tb_module="tb_scloud_msgfunc_cfg_reg",
        rtl_globs=_rtl("param/*.v", "bdd/*.v"),
        timeout_cycles=5000,
    )

    # ── MatMul ──
    cases["matmul_bmm"] = TestbenchCase(
        name="matmul_bmm", group="matmul",
        tb_file="tb/matmul/tb_scloudplus_bmm.v",
        tb_module="tb_scloudplus_bmm",
        rtl_globs=_scplus("*.v"),
        timeout_cycles=5000,
    )

    cases["matmul_vectors"] = TestbenchCase(
        name="matmul_vectors", group="matmul",
        tb_file="tb/matmul/tb_scloudplus_matm_vectors.v",
        tb_module="tb_scloudplus_matm_vectors",
        rtl_globs=_scplus("*.v"),
        timeout_cycles=50000,
    )

    cases["matmul_vectors128"] = TestbenchCase(
        name="matmul_vectors128", group="matmul",
        tb_file="tb/matmul/tb_scloudplus128_matm_vectors.v",
        tb_module="tb_scloudplus128_matm_vectors",
        rtl_globs=_scplus("*.v"),
        timeout_cycles=50000,
    )

    cases["matmul_official"] = TestbenchCase(
        name="matmul_official", group="matmul",
        tb_file="tb/matmul/tb_scloudplus_official_params_vectors.v",
        tb_module="tb_scloudplus_official_params_vectors",
        rtl_globs=_scplus("*.v"),
        timeout_cycles=200000,
        iverilog_opts="-g2012",
    )

    cases["matmul_scloud256"] = TestbenchCase(
        name="matmul_scloud256", group="matmul",
        tb_file="tb/matmul/tb_pqc_matmul_scloud256.v",
        tb_module="tb_pqc_matmul_scloud256",
        rtl_globs=_scplus("*.v"),
        timeout_cycles=500000,
        iverilog_opts="-g2012",
    )

    return cases


# ==============================================================================
# SimRunner
# ==============================================================================


class SimRunner:
    """Compiles and runs Scloud+ testbenches with iverilog/vvp."""

    def __init__(self, repo_root: Path, vvp_dir: Path = None):
        self.root = repo_root
        self.vvp_dir = vvp_dir or (repo_root / "sim_build")
        self.vvp_dir.mkdir(parents=True, exist_ok=True)
        self.cases = build_registry()
        self.results: List[SimResult] = []

    # ── Compile ──

    def _collect_rtl_files(self, case: TestbenchCase) -> List[Path]:
        """Expand glob patterns to actual RTL file paths."""
        files = []
        for pattern in case.rtl_globs:
            matches = sorted(self.root.glob(pattern))
            if not matches:
                print(f"  {YELLOW}WARNING: no files match '{pattern}'{RESET}")
            files.extend(matches)
        return files

    def compile(self, case_name: str) -> bool:
        """Compile one testbench. Returns True on success."""
        case = self.cases[case_name]
        vvp_path = self.vvp_dir / f"{case.tb_module}.vvp"
        tb_path = self.root / case.tb_file

        if not tb_path.exists():
            print(f"  {RED}ERROR: testbench not found: {tb_path}{RESET}")
            return False

        rtl_files = self._collect_rtl_files(case)
        if not rtl_files:
            print(f"  {YELLOW}WARNING: no RTL files found for {case_name}{RESET}")

        cmd = ["iverilog"]
        if case.iverilog_opts:
            cmd.append(case.iverilog_opts)
        cmd += ["-Wall", "-o", str(vvp_path)]
        cmd += [str(f) for f in rtl_files]
        cmd.append(str(tb_path))

        try:
            proc = subprocess.run(
                cmd,
                cwd=str(self.root),
                capture_output=True, text=True,
                timeout=60,
            )
            if proc.returncode != 0:
                stderr = proc.stderr.strip()
                stdout = proc.stdout.strip()
                if stderr:
                    print(f"  {RED}iverilog stderr:{RESET}")
                    for line in stderr.split("\n")[-8:]:
                        print(f"    {line}")
                if stdout:
                    print(f"  {RED}iverilog stdout:{RESET}")
                    for line in stdout.split("\n")[-4:]:
                        print(f"    {line}")
                return False
            return True
        except subprocess.TimeoutExpired:
            print(f"  {RED}iverilog timed out (60s){RESET}")
            return False
        except FileNotFoundError:
            print(f"  {RED}iverilog not found in PATH{RESET}")
            return False

    # ── Run ──

    def run(self, case_name: str, wave: bool = False,
            timeout_s: int = 300) -> SimResult:
        """Compile and run one testbench. Returns SimResult."""
        case = self.cases[case_name]
        vvp_path = self.vvp_dir / f"{case.tb_module}.vvp"

        result = SimResult(case_name=case_name)

        # Compile
        t0 = time.time()
        if not vvp_path.exists():
            ok = self.compile(case_name)
            if not ok:
                result.status = "COMPILE_ERR"
                result.duration_ms = (time.time() - t0) * 1000
                return result

        # Run
        cmd = ["vvp", str(vvp_path)]
        if wave and case.supports_wave:
            cmd.append("+dump")

        t0 = time.time()
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(self.root),
                capture_output=True, text=True,
                timeout=timeout_s,
            )
        except subprocess.TimeoutExpired:
            result.status = "TIMEOUT"
            result.duration_ms = timeout_s * 1000
            return result
        except FileNotFoundError:
            result.status = "ERROR"
            result.output = "vvp not found in PATH"
            result.duration_ms = (time.time() - t0) * 1000
            return result

        result.duration_ms = (time.time() - t0) * 1000
        result.output = proc.stdout + proc.stderr

        # Parse result
        if "TB_TIMEOUT" in result.output:
            result.status = "TIMEOUT"
        elif "TB_PASS" in result.output:
            result.status = "PASS"
            m = re.search(r"TB_PASS\s+\S+\s+cases=(\d+)", result.output)
            if m:
                result.pass_count = int(m.group(1))
        elif "TB_FAIL" in result.output:
            result.status = "FAIL"
            m = re.search(r"TB_FAIL\s+\S+\s+errors=(\d+)", result.output)
            if m:
                result.error_count = int(m.group(1))
        elif "ALL REQUESTED SIMULATIONS PASSED" in result.output:
            result.status = "PASS"
        else:
            result.status = "UNKNOWN"

        return result

    # ── SW Compare ──

    # Noise sweep levels for the C-aligned software reference.
    # For official logq=12, Delta is 512 at tau=3 and 256 at tau=4.
    NOISE_LEVELS = [
        ("zero",      0),
        ("D/8=32",   32),    # well within correction radius
        ("D/4=63",   63),    # within correction radius
        ("D/2=127", 127),    # edge of guaranteed correction
        ("D=255",   255),    # beyond guaranteed correction
        ("2D=511",  511),    # heavy noise — many failures expected
    ]

    def sw_compare(self, case_name: str, num_vectors: int = 128,
                   seed: int = 42, timeout_s: int = 300) -> SimResult:
        """Multi-level noise sweep for MsgFunc SW validation.

        Tests zero-noise roundtrip (must be 100%) + graduated noise levels
        to characterize BDD decoder correction capability.

        Uses the C-aligned SW reference (tau=3/4, logq=12).
        Does NOT require RTL simulation.

        Legacy fixed BW demos still use tau=2, q_width=10. The
        parameterized RTL path uses the C-model logq=12 parameter shape.
        """
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from scloud_msgfunc_sw_ref import (
            PARAM_SETS, msgfunc_encode, msgfunc_decode, add_noise
        )

        case = self.cases[case_name]
        if not case.bw_config:
            result = SimResult(case_name=case_name)
            result.status = "ERROR"
            result.output = "SW compare requires bw_config"
            return result

        cfg = case.bw_config
        cn = cfg["complex_n"]
        tau = cfg["tau"]
        qw = cfg["q_width"]

        # Map RTL bw_config to nearest C-model ss_level
        if tau == 2:
            # RTL uses simplified parameters — use ss=16 C-model params for SW validation
            ss_level = 16
            cm_cfg = PARAM_SETS[ss_level]
            print(f"    {YELLOW}Note: RTL uses tau=2,q_width=10; SW compare uses C-model "
                  f"ss={ss_level} (tau={cm_cfg['tau']},logq={cm_cfg['logq']}){RESET}")
        else:
            # Find matching ss_level
            ss_level = None
            for sl, pc in PARAM_SETS.items():
                if pc["tau"] == tau and pc["logq"] == qw:
                    ss_level = sl
                    break
            if ss_level is None:
                result = SimResult(case_name=case_name)
                result.status = "ERROR"
                result.output = f"No C-model config matches tau={tau}, q_width={qw}"
                return result

        cm_cfg = PARAM_SETS[ss_level]
        msg_bytes = cm_cfg["mu"] * cm_cfg["mu_conut"] // 8

        import random as py_random
        rng = py_random.Random(seed)

        # Pre-generate message set
        messages = [bytes(rng.randint(0, 255) for _ in range(msg_bytes))
                    for _ in range(num_vectors)]

        t0 = time.time()
        results_per_level = []

        for level_name, noise_max in self.NOISE_LEVELS:
            errors = 0
            for msg in messages:
                enc_q = msgfunc_encode(msg, ss_level)

                if noise_max == 0:
                    noisy_q = enc_q
                else:
                    noise = [rng.randint(0, noise_max) for _ in range(len(enc_q))]
                    noisy_q = add_noise(enc_q, noise)

                _, msg_out = msgfunc_decode(noisy_q, ss_level)
                if msg_out != msg:
                    errors += 1

            ok = num_vectors - errors
            rate = 100 * errors / num_vectors
            results_per_level.append(f"{level_name}:{ok}/{num_vectors}")
            if errors > 0:
                results_per_level[-1] += f"({rate:.1f}%)"

        elapsed_ms = (time.time() - t0) * 1000

        zero_errors = num_vectors - int(results_per_level[0].split(":")[1].split("/")[0])

        result = SimResult(case_name=f"{case_name} (SW)")
        result.error_count = zero_errors
        result.pass_count = num_vectors - zero_errors
        result.status = "PASS" if zero_errors == 0 else "FAIL"
        result.duration_ms = elapsed_ms
        result.output = " | ".join(results_per_level)
        return result

    # ── Batch run ──

    def run_group(self, group: str, **kwargs) -> List[SimResult]:
        """Run all cases in a group."""
        names = [n for n, c in self.cases.items()
                 if c.group == group or group == "all"]
        return self._run_sequential(names, **kwargs)

    def run_all(self, case_names: List[str] = None, **kwargs) -> List[SimResult]:
        """Run multiple cases."""
        if case_names is None:
            case_names = list(self.cases.keys())
        return self._run_sequential(case_names, **kwargs)

    def _run_sequential(self, names: List[str], wave: bool = False,
                        sw_compare: bool = False, num_vectors: int = 128,
                        seed: int = 42, timeout_s: int = 300,
                        keep_going: bool = True,
                        sw_only: bool = False) -> List[SimResult]:
        """Run cases sequentially. SW compare runs BEFORE RTL for speed."""
        results = []
        for name in names:
            if name not in self.cases:
                print(f"  {YELLOW}Unknown case: {name}{RESET}")
                continue

            case = self.cases[name]

            # ── SW compare first (fast, pure Python) ──
            if sw_compare and case.bw_config:
                label = f"{CYAN}{case.name}{RESET} (SW-cmp)"
                print(f"  {label:<50}", end=" ", flush=True)
                result = self.sw_compare(name, num_vectors, seed, timeout_s)
                results.append(result)
                self.results.append(result)
                status_str = f"{GREEN}PASS{RESET}" if result.status == "PASS" else f"{RED}FAIL{RESET}"
                print(f"{status_str:<30} {result.output:<35} {result.duration_ms:7.0f}ms")

            # ── RTL simulation (skip if --sw-only) ──
            if not sw_only:
                label = f"{CYAN}{case.name}{RESET} ({case.group})"
                print(f"  {label:<50}", end=" ", flush=True)

                result = self.run(name, wave, timeout_s)
                results.append(result)
                self.results.append(result)

                if result.status == "PASS":
                    status_str = f"{GREEN}PASS{RESET}"
                elif result.status == "FAIL":
                    status_str = f"{RED}FAIL{RESET}"
                elif result.status == "TIMEOUT":
                    status_str = f"{YELLOW}TIMEOUT{RESET}"
                else:
                    status_str = f"{RED}{result.status}{RESET}"

                    pct = f"pass={result.pass_count}" if result.pass_count else ""
                    ect = f"err={result.error_count}" if result.error_count else ""
                    detail = " ".join(x for x in [pct, ect] if x)
                    print(f"{status_str:<30} {detail:<20} {result.duration_ms:7.0f}ms")

                    if result.status not in ("PASS",) and not keep_going:
                        print(f"\n  {RED}Stopping after failure (--no-keep-going){RESET}")
                        break

        return results

    # ── Summary ──

    def print_summary(self, json_path: str = None):
        """Print formatted summary of all results."""
        results = self.results
        if not results:
            print("No results.")
            return

        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print()
        print("=" * 72)
        print(f"  Scloud+ Simulation Runner  |  {now}")
        print("=" * 72)
        print(f"  {'Case':<30} {'Status':<12} {'Pass':>6} {'Fail':>6} {'Time':>8}")
        print("  " + "-" * 68)

        total_pass = 0
        total_fail = 0
        for r in results:
            s = r.status
            if s == "PASS":
                color = GREEN
                total_pass += 1
            else:
                color = RED
                if s != "UNKNOWN":
                    total_fail += 1
            t_str = f"{r.duration_ms / 1000:.1f}s" if r.duration_ms > 10000 else f"{r.duration_ms:.0f}ms"
            print(f"  {r.case_name:<30} {color}{s:<12}{RESET} "
                  f"{r.pass_count:>6} {r.error_count:>6} {t_str:>8}")

        print("  " + "-" * 68)
        print(f"  TOTAL: {total_pass} passed, {total_fail} failed "
              f"({len(results)} cases)")
        print("=" * 72)

        # JSON output
        if json_path:
            data = {
                "timestamp": now,
                "cases": [
                    {
                        "name": r.case_name,
                        "status": r.status,
                        "pass_count": r.pass_count,
                        "error_count": r.error_count,
                        "duration_ms": round(r.duration_ms, 1),
                    }
                    for r in results
                ],
                "summary": {
                    "total": len(results),
                    "passed": total_pass,
                    "failed": total_fail,
                },
            }
            path = Path(json_path)
            path.write_text(json.dumps(data, indent=2), encoding="ascii")
            print(f"\n  JSON summary: {path}")


# ==============================================================================
# CLI
# ==============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Scloud+ Unified Simulation Runner")
    parser.add_argument("--cases", type=str, default="all",
                        help="Comma-separated groups or names: "
                             "bw8,bw16,bw32,bdd,param,matmul,all")
    parser.add_argument("--wave", action="store_true",
                        help="Enable VCD waveform dump (+dump)")
    parser.add_argument("--sw-compare", action="store_true",
                        help="Cross-validate RTL against Python SW reference")
    parser.add_argument("--sw-only", action="store_true",
                        help="SW sweep only (skip RTL simulation entirely)")
    parser.add_argument("--official", action="store_true",
                        help="Run official Scloud+ 128/192/256 parameter tests "
                             "(same as --cases bw32,matmul --sw-compare)")
    parser.add_argument("--num-vectors", type=int, default=128,
                        help="Number of SW comparison vectors (default: 128)")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed for SW comparison")
    parser.add_argument("--timeout", type=int, default=300,
                        help="Timeout per case in seconds (default: 300)")
    parser.add_argument("--json", type=str, default=None,
                        help="Write JSON summary to file")
    parser.add_argument("--keep-going", action="store_true", default=True,
                        help="Continue after failures (default)")
    parser.add_argument("--no-keep-going", dest="keep_going",
                        action="store_false",
                        help="Stop after first failure")
    parser.add_argument("--vvp-dir", type=str, default="sim_build",
                        help="Directory for compiled .vvp files")
    args = parser.parse_args()

    # Resolve repo root
    repo_root = Path(__file__).resolve().parents[2]
    vvp_dir = repo_root / args.vvp_dir

    runner = SimRunner(repo_root, vvp_dir)

    # Resolve cases
    if args.official:
        case_names = [
            "bw32_combo_demo", "bw32_seq", "bw32_stress",
            "msgenc_bw32_seq", "msgdec_bw32_seq",
            "bdd32_seq", "bdd32_seq_smoke", "bdd32_recursive",
            "matmul_official", "matmul_scloud256",
        ]
        args.sw_compare = True
    elif args.cases == "all":
        case_names = list(runner.cases.keys())
    else:
        # Parse comma-separated: can be groups or individual names
        names = []
        for tok in args.cases.split(","):
            tok = tok.strip()
            if tok in runner.cases:
                names.append(tok)
            else:
                # Treat as group name
                group_members = [n for n, c in runner.cases.items()
                                 if c.group == tok]
                if group_members:
                    names.extend(group_members)
                else:
                    print(f"Warning: unknown case/group '{tok}'")
        case_names = names

    if not case_names:
        print("No cases selected. Use --cases all or specify groups.")
        print(f"Available groups: bw8, bw16, bw32, bdd, param, matmul")
        print(f"Available cases: {', '.join(sorted(runner.cases.keys()))}")
        return

    print(f"\n{BOLD}=== Scloud+ Simulation Runner ==={RESET}")
    print(f"  Cases: {len(case_names)}")
    print(f"  Wave: {args.wave}")
    print(f"  SW Compare: {args.sw_compare}")
    print(f"  Timeout: {args.timeout}s per case")
    print()

    # ── SW compare: generate vectors first if needed ──
    if args.sw_compare:
        print(f"{BOLD}--- SW Reference Sanity Check (C-model aligned) ---{RESET}")
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from scloud_msgfunc_sw_ref import PARAM_SETS, msgfunc_roundtrip
        import random as _random
        rng = _random.Random(args.seed)
        for ss_level in [16, 24, 32]:
            cfg = PARAM_SETS[ss_level]
            msg_bytes = cfg["mu"] * cfg["mu_conut"] // 8
            ok = True
            for _ in range(32):
                m = bytes(rng.randint(0, 255) for _ in range(msg_bytes))
                mo, _, _ = msgfunc_roundtrip(m, ss_level=ss_level)
                if mo != m:
                    ok = False
                    break
            print(f"  ss={ss_level} (tau={cfg['tau']}) zero-noise roundtrip: "
                  f"{GREEN}PASS{RESET}" if ok else f"{RED}FAIL{RESET}")
            if not ok:
                print(f"  {RED}SW reference self-check failed — aborting{RESET}")
                return
        print(f"  {YELLOW}Note: legacy fixed BW demos still use tau=2,q_width=10; "
              f"the parameterized RTL path uses C-model logq=12 params{RESET}")
        print()

    # ── Run ──
    print(f"{BOLD}--- Simulation ---{RESET}")
    runner.run_all(
        case_names,
        wave=args.wave,
        sw_compare=args.sw_compare or args.sw_only,
        num_vectors=args.num_vectors,
        seed=args.seed,
        timeout_s=args.timeout,
        keep_going=args.keep_going,
        sw_only=args.sw_only,
    )

    # ── Summary ──
    runner.print_summary(args.json)


if __name__ == "__main__":
    main()
