# CLAUDE.md — Scloud+ Project Context for AI Agents

## What This Project Is

Scloud+ post-quantum KEM hardware implementation (Verilog-2001 RTL).
Aligned with the openHiTLS C reference model in `rtl/cmodel/`.

## Current Implementation State (2026-06-17)

### Active RTL (PRIMARY — C-model aligned, tau=3/4, Q_WIDTH=12)

| Module | File | Description |
|--------|------|-------------|
| `scloud_msgfunc_param` | `rtl/msgfunc/param/scloud_msgfunc_param.v` | **Top-level** single BW block (32 Q coords, 64/96-bit msg) |
| `scloud_msgfunc_cfg_reg` | `rtl/msgfunc/param/scloud_msgfunc_cfg_reg.v` | Register-configurable wrapper (BW8/BW16/BW32) |
| `scloud_bdd32_seq` | `rtl/msgfunc/bdd/scloud_bdd32_seq.v` | **Sequential BDD** — 2× bdd16, FSM: IDLE→WAIT_Y→INV_PHI→START_Z→WAIT_Z→SELECT→DONE |
| `scloud_bdd16_seq` | `rtl/msgfunc/bdd/scloud_bdd16_seq.v` | 2× bdd8 children |
| `scloud_bdd8_seq` | `rtl/msgfunc/bdd/scloud_bdd8_seq.v` | 2× bdd4 children |
| `scloud_bdd4_seq` | `rtl/msgfunc/bdd/scloud_bdd4_seq.v` | **Leaf** — direct `scloud_bdd_round_coord_q` (no children) |
| `scloud_bdd_recursive` | `rtl/msgfunc/bdd/scloud_bdd_recursive.v` | Combinational recursive BDD (legacy reference) |

### Key Design Decisions

- **BDD distance**: L2 (Euclidean squared) — `scloud_bdd_sq_diff_q` computes `diff_ext * diff_ext`
- **BDD tie-breaking**: strict `<` — `(dist_a < dist_b) ? cand_a : cand_b` matches C model's `if (d1 < d2)`
- **msg→label mapping**: hardcoded tau=3/tau=4 bit-packing blocks matching C model's `LabelingComputeV`/`DelabelingComputeU`, with generic popcount-based fallback for other parameter combos
- **label→msg reduction**: hardcoded `DelabelingReduceW` logic per coordinate index
- **Label width**: `LABEL_WIDTH = TAU + LOG_COMPLEX_N` (7 for tau=3, 8 for tau=4)
- **Msg width**: `MSG_WIDTH = (COMPLEX_N*(2*TAU)) - ((COMPLEX_N*LOG_COMPLEX_N)/2)` (64 for tau=3, 96 for tau=4)

### C Model Reference (THE AUTHORITY)

- `rtl/cmodel/scloudplus_util.c` — `LabelingComputeV`, `LabelingComputeW`, `DelabelingRecoverW`, `DelabelingReduceW`, `DelabelingComputeU`, `BDDForBWn`, `Round`, `EuclideanDistanceNoSqrt`
- `rtl/cmodel/scloudplus.c` — top-level KEM
- `rtl/cmodel/scloudplus_local.h` — `SCLOUDPLUS_MOD_Q = 0xFFF`, `SCLOUDPLUS_BW_COMPLEX_LEN = 16`

### Python Scripts (`tb/scripts/`)

Only 3 key scripts — the rest are support tools:

| Script | Role | Run |
|--------|------|-----|
| `scloud_msgfunc_sw_ref.py` | **Core library** — bit-exact C model SW reference | `python tb/scripts/scloud_msgfunc_sw_ref.py` (self-test) |
| `scloud_msgfunc_vector_gen.py` | Generate .mem test vectors + diverse message cases | `python tb/scripts/scloud_msgfunc_vector_gen.py --ss 16 --num 256` |
| `scloud_msgfunc_gen_result.py` | Generate organized verification result files in `tb/vectors/verify_result/` | `python tb/scripts/scloud_msgfunc_gen_result.py --ss all` |

Dependency chain: `vector_gen.py` → `sw_ref.py`, `gen_result.py` → `sw_ref.py` + `vector_gen.py`

Key SW ref functions: `labeling_compute_v()`, `labeling_compute_w()`, `bdd_decode_bwn()`, `delabeling_recover_w()`, `delabeling_compute_u()`, `msgfunc_encode_block()`, `msgfunc_decode_block()`, `msgfunc_encode()`, `msgfunc_decode()`

Parameter sets: `PARAM_SETS[16/24/32]` matching C model `PRESET_PARAS`

### Verification

#### RTL Simulation (clocked BDD chain)
```bash
iverilog -g2001 -Wall -o sim_build/tb_param.vvp \
    rtl/msgfunc/param/*.v rtl/msgfunc/bdd/*.v \
    tb/param/tb_scloud_msgfunc_param.v
vvp sim_build/tb_param.vvp
```
**Last result: TB_PASS cases=33** (all zero-noise + noise roundtrips, tau=3 and tau=4)

#### Python Verification
```bash
python tb/scripts/scloud_msgfunc_sw_ref.py                          # self-test
python tb/scripts/scloud_msgfunc_vector_gen.py --ss 16 --num 256    # .mem vectors
python tb/scripts/scloud_msgfunc_gen_result.py --ss all             # organized result files
```

#### Verified Results (stored in `tb/vectors/verify_result/`)
| Test | Result |
|------|--------|
| Walking-1 (64 bits, tau=3) | 64/64 PASS |
| BDD rounding boundary (16 values) | 16/16 PASS |
| Phi symmetry | 16/16 PASS |
| Noise sweep zero/D8/D4/D2 | 100% correct |
| Multi-block ss=16/24/32 | 384/384 PASS |
| RTL simulation (clocked BDD) | 33/33 PASS |

### Archived (Legacy — tau=2, Q_WIDTH=10, do NOT use for new work)

- `archive/legacy_msgfunc/rtl/{bw8,bw16,bw32_combo,bw32_seq}/`
- `archive/legacy_msgfunc/tb/{bw8,bw16,bw32_combo,bw32_seq}/`
- These use L1 (Manhattan) distance and generic popcount label mapping — NOT C-model aligned

### Common Pitfalls

1. **Don't confuse parameter sets**: C model uses tau=3/4, Q=12. Legacy paths use tau=2, Q=10
2. **BDD module instantiation**: `scloud_msgdec_param` uses generate to select `scloud_bdd32_seq`/`bdd16_seq`/`bdd8_seq` based on COMPLEX_N. Don't instantiate `scloud_bdd_recursive` for the primary path
3. **Handshake timing**: BDD seq modules need `start` held high for >= 1 full clock cycle. `@(posedge clk); start<=1; @(posedge clk); start<=0;` is the correct pattern
4. **start_ready is combinational**: `assign start_ready = (state == ST_IDLE) && child_ready`. Don't wait for it in a while loop before asserting start; just assert start after a @(posedge clk) and hold for one cycle
5. **C model tie-breaking**: `if (d1 < d2) out1 else out2` — strict less-than, tie goes to out2. RTL matches
6. **C model distance**: Euclidean squared (`sum += dr*dr + di*di`), NOT Manhattan
7. **msg_to_label bit packing**: tau=3 uses A/B/C/D array rearrangement per C model, not sequential MSB-first

### Parameter Quick Reference

| Security | tau | mu | muConut | Msg/block | Total Msg | Q Coords |
|----------|-----|----|---------|-----------|-----------|----------|
| 128 (ss=16) | 3 | 64 | 2 | 8 bytes | 16 bytes | 64 |
| 192 (ss=24) | 4 | 96 | 2 | 12 bytes | 24 bytes | 64 |
| 256 (ss=32) | 3 | 64 | 4 | 8 bytes | 32 bytes | 128 |

### Coordinate Bit Allocation (tau=3)

| WH | Coords | re_bits | im_bits | Count | Subtotal |
|----|--------|---------|---------|-------|----------|
| 0 | [0] | 3 | 3 | 1 | 6 |
| 1 | [1,2,4,8] | 3 | 2 | 4 | 20 |
| 2 | [3,5,6,9,10,12] | 2 | 2 | 6 | 24 |
| 3 | [7,11,13,14] | 2 | 1 | 4 | 12 |
| 4 | [15] | 1 | 1 | 1 | 2 |
| **Total** | 16 | | | | **64** |
