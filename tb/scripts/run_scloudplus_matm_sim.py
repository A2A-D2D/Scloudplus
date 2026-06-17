#!/usr/bin/env python3
"""One-command Icarus simulation runner for the Scloud+ MatM RTL.

Examples:
  python tb/scripts/run_scloudplus_matm_sim.py
  python tb/scripts/run_scloudplus_matm_sim.py --case bmm
  python tb/scripts/run_scloudplus_matm_sim.py --case matm128 --open-wave
  python tb/scripts/run_scloudplus_matm_sim.py --case official --regen-c-vectors
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TB_DIR = ROOT / "tb"
RTL_DIR = ROOT / "rtl" / "scloudplus"
BUILD_DIR = ROOT / "sim_build" / "scloudplus"

RTL_FILES = [
    RTL_DIR / "scloudplus_bmm_pe.v",
    RTL_DIR / "scloudplus_bmm_block.v",
    RTL_DIR / "scloudplus_block_add.v",
    RTL_DIR / "scloudplus_matmul_serial.v",
]
C_VECTOR_GEN = TB_DIR / "scripts" / "scloudplus_matm_vector_gen.c"
C_VECTOR_EXE = BUILD_DIR / "scloudplus_matm_vector_gen.exe"
OPENHITLS_COMPARE_GEN = TB_DIR / "scripts" / "scloudplus_openhitls_matm_compare.c"
OPENHITLS_COMPARE_EXE = BUILD_DIR / "scloudplus_openhitls_matm_compare.exe"

CASES = {
    "bmm": {
        "tb": TB_DIR / "matmul" / "tb_scloudplus_bmm.v",
        "out": BUILD_DIR / "tb_scloudplus_bmm.vvp",
        "vcd": ROOT / "tb_scloudplus_bmm.vcd",
        "pass": "TB_PASS scloudplus_bmm",
        "dump_plusarg": False,
    },
    "matm": {
        "tb": TB_DIR / "matmul" / "tb_scloudplus_matm_vectors.v",
        "out": BUILD_DIR / "tb_scloudplus_matm_vectors.vvp",
        "vcd": ROOT / "tb_scloudplus_matm_vectors.vcd",
        "pass": "TB_PASS scloudplus_matm_vectors",
        "dump_plusarg": True,
    },
    "matm128": {
        "tb": TB_DIR / "matmul" / "tb_scloudplus128_matm_vectors.v",
        "out": BUILD_DIR / "tb_scloudplus128_matm_vectors.vvp",
        "vcd": ROOT / "tb_scloudplus128_matm_vectors.vcd",
        "pass": "TB_PASS scloudplus128_matm_vectors",
        "dump_plusarg": True,
    },
    "official": {
        "tb": TB_DIR / "matmul" / "tb_scloudplus_official_params_vectors.v",
        "out": BUILD_DIR / "tb_scloudplus_official_params_vectors.vvp",
        "vcd": ROOT / "tb_scloudplus_official_params_vectors.vcd",
        "pass": "TB_PASS scloudplus_official_params_vectors",
        "dump_plusarg": True,
    },
}


def run_cmd(cmd, cwd):
    print("+ " + " ".join(str(x) for x in cmd))
    proc = subprocess.run(
        [str(x) for x in cmd],
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    print(proc.stdout, end="")
    if proc.returncode != 0:
        raise RuntimeError("command failed with exit code %d" % proc.returncode)
    return proc.stdout


def require_tool(name):
    if shutil.which(name) is None:
        raise RuntimeError("Cannot find '%s' in PATH. Please install it or add it to PATH." % name)


def compile_case(case_name):
    cfg = CASES[case_name]
    cfg["out"].parent.mkdir(parents=True, exist_ok=True)
    cmd = ["iverilog", "-g2001", "-Wall", "-o", cfg["out"]]
    cmd.extend(RTL_FILES)
    cmd.append(cfg["tb"])
    run_cmd(cmd, ROOT)


def simulate_case(case_name, dump_wave):
    cfg = CASES[case_name]
    if cfg["vcd"].exists():
        cfg["vcd"].unlink()

    cmd = ["vvp", cfg["out"]]
    if dump_wave and cfg["dump_plusarg"]:
        cmd.append("+dump")

    output = run_cmd(cmd, ROOT)
    if cfg["pass"] not in output:
        raise RuntimeError("PASS marker not found for case '%s'" % case_name)

    if dump_wave and not cfg["vcd"].exists():
        raise RuntimeError("simulation passed but VCD was not generated: %s" % cfg["vcd"])

    if dump_wave:
        print("VCD: %s" % cfg["vcd"])


def open_wave(case_names):
    require_tool("gtkwave")
    for name in case_names:
        vcd = CASES[name]["vcd"]
        if vcd.exists():
            subprocess.Popen(["gtkwave", str(vcd)], cwd=str(ROOT))


def regenerate_c_vectors():
    require_tool("gcc")
    C_VECTOR_EXE.parent.mkdir(parents=True, exist_ok=True)
    run_cmd(["gcc", "-std=c99", "-Wall", "-Wextra", "-O2", "-o", C_VECTOR_EXE, C_VECTOR_GEN], ROOT)
    run_cmd([C_VECTOR_EXE], ROOT)
    run_cmd(["gcc", "-std=c99", "-Wall", "-Wextra", "-O2", "-o", OPENHITLS_COMPARE_EXE, OPENHITLS_COMPARE_GEN], ROOT)
    output = run_cmd([OPENHITLS_COMPARE_EXE], ROOT)
    if "OPENHITLS_C_COMPARE_PASS" not in output:
        raise RuntimeError("openHiTLS-style C comparison did not pass")


def main():
    parser = argparse.ArgumentParser(description="Run Scloud+ MatM simulations and generate VCD waves.")
    parser.add_argument(
        "--case",
        choices=["all", "bmm", "matm", "matm128", "official"],
        default="all",
        help="simulation case to run",
    )
    parser.add_argument(
        "--no-wave",
        action="store_true",
        help="run simulation without generating VCD waves for vector tests",
    )
    parser.add_argument(
        "--open-wave",
        action="store_true",
        help="open generated VCD files with GTKWave after simulation",
    )
    parser.add_argument(
        "--regen-c-vectors",
        action="store_true",
        help="rebuild and run the C reference vector generator before simulation",
    )
    args = parser.parse_args()

    require_tool("iverilog")
    require_tool("vvp")

    if args.regen_c_vectors:
        print("\n=== regenerate C reference vectors ===")
        regenerate_c_vectors()

    case_names = ["bmm", "matm", "matm128", "official"] if args.case == "all" else [args.case]
    dump_wave = not args.no_wave

    for name in case_names:
        print("\n=== compile %s ===" % name)
        compile_case(name)
        print("=== simulate %s ===" % name)
        simulate_case(name, dump_wave)

    if args.open_wave:
        open_wave(case_names)

    print("\nALL REQUESTED SIMULATIONS PASSED")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("\nERROR: %s" % exc, file=sys.stderr)
        sys.exit(1)
