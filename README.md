# Scloudplus

Verilog-2001 RTL prototype for the Scloud+ matrix-multiplication datapath.

This repository focuses on the block matrix multiplication kernel used in Scloud+ hardware exploration.  The current RTL implements a reusable block-matrix multiplier for operations with ternary, binary, and 2-bit signed coefficients under a power-of-two modulus.  It is intended for research, study, and early hardware evaluation rather than production cryptographic deployment.

## Background

Scloud+ is a post-quantum key encapsulation mechanism (KEM) based on unstructured LWE.  Unlike ring/module lattice schemes such as Kyber/ML-KEM, Scloud+ does not rely on NTT-friendly algebraic structure.  Its dominant hardware workload is therefore matrix/vector or matrix/matrix arithmetic rather than polynomial NTT.

This repository implements the matrix arithmetic core only.  It is not a complete Scloud+ KEM implementation.

## Current status

- Language: Verilog-2001 RTL with Python vector-generation scripts.
- Main target: block matrix multiplication for Scloud+ style ternary-secret arithmetic.
- Modulus form: reduction modulo `2^q` by keeping the low `q` bits.
- Verification: simulation testbenches with generated and checked memory vectors.
- Security status: not side-channel hardened, not constant-time audited, and not intended for production use.

## Repository layout

```text
.
├── README.md
├── rtl/
│   └── scloudplus/
│       ├── README.md
│       ├── scloudplus_bmm_pe.v
│       ├── scloudplus_bmm_block.v
│       ├── scloudplus_block_add.v
│       └── scloudplus_matmul_serial.v
└── tb/
    ├── scloudplus_matm_vector_gen.py
    ├── scloudplus128_matm_vector_gen.py
    ├── tb_scloudplus_bmm.v
    ├── tb_scloudplus_matm_vectors.v
    ├── tb_scloudplus128_matm_vectors.v
    ├── vectors_scloudplus/
    └── vectors_scloudplus128/
```

## RTL modules

| Module | Description |
|---|---|
| `scloudplus_bmm_pe.v` | Processing element for one ternary/binary/signed-2 dot product. It computes `sum_j A[i,j] * S[j,k] mod 2^q`. |
| `scloudplus_bmm_block.v` | One-cycle `B x B` block multiplier built from `B^2` processing elements. |
| `scloudplus_block_add.v` | Element-wise block accumulation modulo `2^q`. |
| `scloudplus_matmul_serial.v` | Serial block scheduler that reuses one block multiplier over `(row, inner, col)` block indices. |

## Coefficient modes

The datapath is controlled by `cfg_coeff_mode`:

| `cfg_coeff_mode` | Mode | Encoding |
|---:|---|---|
| `0` | Ternary Scloud+ mode | `00/11 = 0`, `01 = +1`, `10 = -1` |
| `1` | Binary mode | `s[0] = 1` selects `+A` |
| `2` | 2-bit signed mode | `00 = 0`, `01 = +1`, `10 = -2`, `11 = -1` |

The active block size and modulus width are runtime-configurable through:

- `cfg_b_active`: active block edge length, up to synthesis parameter `B`.
- `cfg_q_active`: active modulus width, up to synthesis parameter `Q_WIDTH`.
- `cfg_row_blocks`, `cfg_inner_blocks`, `cfg_col_blocks`: matrix block-grid dimensions for the serial scheduler.

For the Scloud+ default-style block configuration, synthesize with `B=8` and `Q_WIDTH=12`, then set:

```text
cfg_b_active  = 8
cfg_q_active  = 12
cfg_coeff_mode = 0
```

## Quick simulation

Run the commands from the repository root.  The testbenches use relative paths such as `tb/vectors_scloudplus128/...`, so running from another directory may cause `$readmemh` path errors.

### 1. Small block test

```bash
iverilog -g2001 -o sim_scloudplus_bmm \
  tb/tb_scloudplus_bmm.v \
  rtl/scloudplus/scloudplus_bmm_pe.v \
  rtl/scloudplus/scloudplus_bmm_block.v \
  rtl/scloudplus/scloudplus_block_add.v \
  rtl/scloudplus/scloudplus_matmul_serial.v

vvp sim_scloudplus_bmm
```

### 2. Generic matrix-vector test vectors

```bash
python3 tb/scloudplus_matm_vector_gen.py

iverilog -g2001 -o sim_scloudplus_matm_vectors \
  tb/tb_scloudplus_matm_vectors.v \
  rtl/scloudplus/scloudplus_bmm_pe.v \
  rtl/scloudplus/scloudplus_bmm_block.v \
  rtl/scloudplus/scloudplus_block_add.v \
  rtl/scloudplus/scloudplus_matmul_serial.v

vvp sim_scloudplus_matm_vectors
```

### 3. Scloud+128-sized matrix test vectors

```bash
python3 tb/scloudplus128_matm_vector_gen.py

iverilog -g2001 -o sim_scloudplus128_matm_vectors \
  tb/tb_scloudplus128_matm_vectors.v \
  rtl/scloudplus/scloudplus_bmm_pe.v \
  rtl/scloudplus/scloudplus_bmm_block.v \
  rtl/scloudplus/scloudplus_block_add.v \
  rtl/scloudplus/scloudplus_matmul_serial.v

vvp sim_scloudplus128_matm_vectors
```

A successful run should print a `TB_PASS` message from the corresponding testbench.

## Interface notes

`scloudplus_matmul_serial` uses a simple request/response block interface:

- `start`, `start_ready`, `busy`, `done`: top-level transaction control.
- `blk_req_valid`, `blk_req_ready`: request handshake for the next pair of input blocks.
- `a_row_blk`, `a_col_blk`, `s_col_blk`: block indices requested by the scheduler.
- `blk_in_valid`, `a_block`, `s_block`: input block payload.
- `c_block_valid`, `c_block_ready`, `c_row_blk`, `c_col_blk`, `c_block`: output block payload.

Packed block layout:

```text
block[row][col] -> block[(row * B + col) * WIDTH +: WIDTH]
```

where `WIDTH = Q_WIDTH` for matrix `A/C` elements and `WIDTH = 2` for the encoded coefficient matrix `S`.

## Design notes

- The PE avoids general-purpose multiplication in ternary mode.  Each coefficient selects `0`, `+A`, or `-A mod 2^q`.
- Because the modulus is `2^q`, modular reduction is implemented by masking the low `q` bits.
- Right-multiplication forms such as `S' * A` can be mapped by external transpose scheduling, allowing the same `A * S` block datapath to be reused.
- The serial scheduler trades throughput for lower area by reusing one `B x B` block multiplier across matrix block indices.

## Suggested next steps

- Add a top-level wrapper with a memory-mapped register interface.
- Add synthesis scripts for FPGA and ASIC evaluation.
- Add waveform dumping options to the testbenches.
- Add CI simulation using Icarus Verilog.
- Add lint checks for Verilog-2001 compatibility.
- Add comparison against a full Scloud+ software reference implementation.

## References

- Anyu Wang et al., **Scloud+: a Lightweight LWE-based KEM without Ring/Module Structure**, IACR ePrint 2024/1306.
- `rtl/scloudplus/README.md` for the local paper-to-RTL mapping notes.

## Disclaimer

This project is a research RTL prototype.  It is not a complete cryptographic library, has not been formally verified, and has not been evaluated for side-channel resistance.
