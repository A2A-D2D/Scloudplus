# Scloud+ Hardware Implementation

Verilog-2001 RTL implementation of the Scloud+ post-quantum cryptography scheme, focusing on the Barnes-Wall message function (MsgEnc/MsgDec) and block matrix multiplier (MatM) submodules.

Reference paper: [fast-scloud+.pdf](doc/fast-scloud+.pdf)

## Directory Structure

```
scloud+
├── rtl/
│   ├── msgfunc/                  # Barnes-Wall message function
│   │   ├── bw8/                  # BW8  combinational (12-bit msg,  8 q-coords)
│   │   ├── bw16/                 # BW16 combinational (20-bit msg, 16 q-coords)
│   │   ├── bw32_combo/           # BW32 combinational (32-bit msg, 32 q-coords)
│   │   ├── bw32_seq/             # BW32 sequential    (FSM-pipelined)
│   │   ├── bdd/                  # Shared BDD decoders (recursive + seq4/8/16/32)
│   │   └── param/                # Parameterized BW8/BW16/BW32 (compile-time config)
│   └── scloudplus/               # Block matrix multiplier (MatM)
├── tb/
│   ├── bw8/                      # BW8 testbenches
│   ├── bw16/                     # BW16 testbenches
│   ├── bw32_combo/               # BW32 combinational testbench
│   ├── bw32_seq/                  # BW32 sequential testbenches (unit + stress)
│   ├── bdd/                      # BDD decoder testbenches
│   ├── param/                    # Parameterized MsgFunc testbenches
│   ├── matmul/                   # Matrix multiplier testbenches
│   ├── scripts/                  # Python/C build & vector generation scripts
│   └── vectors/                  # Golden test vectors (.mem)
├── sim_build/                    # Compiled .vvp binaries
├── doc/                          # Design documents
│   ├── fast-scloud+.pdf
│   └── BDD_OPTIMIZATION_PROPOSAL.md
└── README.md
```

## Module Overview

### Barnes-Wall Message Function (`rtl/msgfunc/`)

Encodes/decodes messages through Barnes-Wall lattice coordinates with noise addition.

| Variant | Q-Coords | Msg Bits | Style | Directory |
|---------|----------|----------|-------|-----------|
| BW8 | 8 | 12 | Combinational | [`rtl/msgfunc/bw8/`](rtl/msgfunc/bw8/) |
| BW16 | 16 | 20 | Combinational | [`rtl/msgfunc/bw16/`](rtl/msgfunc/bw16/) |
| BW32 | 32 | 32 | Combinational | [`rtl/msgfunc/bw32_combo/`](rtl/msgfunc/bw32_combo/) |
| BW32 | 32 | 32 | Sequential (FSM) | [`rtl/msgfunc/bw32_seq/`](rtl/msgfunc/bw32_seq/) |
| BW8/16/32 | — | — | Parameterized | [`rtl/msgfunc/param/`](rtl/msgfunc/param/) |

All variants share the BDD decoders in [`rtl/msgfunc/bdd/`](rtl/msgfunc/bdd/).

### Block Matrix Multiplier (`rtl/scloudplus/`)

Configurable `b × b` block matrix multiplier for ternary Scloud+ matrices. Supports runtime configuration of block size, modulus width, and coefficient mode.

See [`rtl/scloudplus/README.md`](rtl/scloudplus/README.md) for details.

## Quick Start

### Run BW32 Demo Simulation

```bash
cd sim_build
vvp tb_scloud_msgfunc_bw32_demo.vvp
```

### Run BW32 Sequential Simulation

```bash
cd sim_build
vvp tb_scloud_msgfunc_bw32_seq.vvp
```

### Run Full MatM Regression

```bash
python tb/scripts/run_scloudplus_matm_sim.py --case all
```

## Key Parameters

All implementations use fixed `q=1024`, `TAU=2`, `Q_WIDTH=10`.

| Parameter | BW8 | BW16 | BW32 |
|-----------|-----|------|------|
| COMPLEX_N | 4 | 8 | 16 |
| Q-coordinates | 8 | 16 | 32 |
| Message width | 12 bits | 20 bits | 32 bits |
| Label width | 192 bits | 224 bits | 224 bits |

## Implementation Notes

- **Combinational ("demo")** variants use manually unrolled butterfly stages and explicit msg↔label bit assignments for clarity. They are fully functional but have high combinational depth.
- **Sequential** variants execute one butterfly stage per clock cycle, significantly reducing area and improving timing.
- **BDD recursive tree** in the combinational decoder has exponential instance count; the sequential BDD engines avoid this via hierarchical FSM reuse (BDD4 → BDD8 → BDD16 → BDD32).
- See [`doc/BDD_OPTIMIZATION_PROPOSAL.md`](doc/BDD_OPTIMIZATION_PROPOSAL.md) for optimization plans.
