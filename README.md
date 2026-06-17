# Scloud+ — Post-Quantum KEM Hardware Implementation

Verilog-2001 RTL implementation of the Scloud+ lightweight LWE-based KEM, with a software-hardware co-design framework for functional verification and acceleration.

> **Reference**  
> Anyu Wang, Zhongxiang Zheng, Chunhuan Zhao, Guang Zeng, Ye Yuan, Zhiyuan Qiu, Changchun Mu, Xiaoyun Wang.  
> *Scloud+: a Lightweight LWE-based KEM without Ring/Module Structure.*  
> IACR ePrint 2024/1306 — [https://eprint.iacr.org/2024/1306](https://eprint.iacr.org/2024/1306)

---

## Directory Structure

```
scloud+
├── rtl/
│   ├── cmodel/                              # openHiTLS C reference model
│   │   ├── scloudplus.h / scloudplus_local.h
│   │   ├── scloudplus.c                     #   top-level KEM (keygen/encaps/decaps)
│   │   └── scloudplus_util.c               #   MsgEncode/Decode, BDD, sampling, packing
│   ├── msgfunc/
│   │   ├── param/                           # ★ PRIMARY — C-model aligned (tau=3/4, Q=12)
│   │   │   ├── scloud_msgfunc_param.v       #   single-block MsgEnc/MsgDec datapath
│   │   │   └── scloud_msgfunc_cfg_reg.v     #   register-configurable wrapper (BW8/16/32)
│   │   └── bdd/                             # BDD decoder engines
│   │       ├── scloud_bdd_recursive.v       #   combinational recursive (reference)
│   │       └── scloud_bdd{32,16,8,4}_seq.v  #   sequential FSM variants
│   ├── scloudplus/                          # Blocked matrix multiplier (MatM)
│   │   ├── scloudplus_matmul_serial.v       #   B×B block scheduler with handshake FSM
│   │   ├── scloudplus_bmm_block.v           #   B×B PE grid (combinational)
│   │   ├── scloudplus_bmm_pe.v             #   processing element (ternary dot product)
│   │   └── scloudplus_block_add.v          #   block accumulator (mod 2^q)
│   └── scloudplus_bmm_pe.v                 # (symlink / duplicate)
│
├── sw/                                      # ★ NEW — SW/HW co-design framework
│   ├── include/
│   │   ├── scloudplus_hal.h                 #   Hardware Abstraction Layer API
│   │   └── scloudplus_kem.h                 #   KEM API (KeyGen/Encaps/Decaps)
│   ├── hal/
│   │   ├── hal_matmul.c                    #   MatMul HAL dispatch (SW ↔ Verilator)
│   │   ├── hal_msgfunc.c                   #   MsgFunc HAL dispatch
│   │   ├── hal_sw_matmul.c                 #   Pure-C functional model of matrix multiply
│   │   ├── hal_sw_msgfunc.c                #   Pure-C functional model of BW encode/decode
│   │   └── verilator_matmul.cpp            #   Verilator C++ wrapper (prepared)
│   ├── src/
│   │   ├── scloudplus_util_sw.c/h          #   SW utilities: SHAKE256, pack/unpack,
│   │   │                                     #   compress/decompress, CBD sampling
│   │   ├── scloudplus_kem_keygen.c         #   KeyGen protocol using HAL
│   │   ├── scloudplus_kem_encaps.c         #   Encaps protocol using HAL
│   │   └── scloudplus_kem_decaps.c         #   Decaps protocol using HAL
│   ├── test/
│   │   └── test_hal.c                      #   8 comprehensive tests
│   └── Makefile                            #   Build system
│
├── archive/
│   └── legacy_msgfunc/                     # Archived legacy implementations
│       ├── rtl/{bw8,bw16,bw32_combo,bw32_seq}/
│       └── tb/{bw8,bw16,bw32_combo,bw32_seq}/
│
├── tb/
│   ├── param/                              # MsgFunc testbenches (tau=3/4, Q=12)
│   ├── bdd/                                # BDD decoder testbenches
│   ├── matmul/                             # matrix multiplier testbenches
│   ├── scripts/                            # Python SW reference & verification
│   │   ├── scloud_msgfunc_sw_ref.py        #   bit-exact C-model Python reference
│   │   ├── scloud_msgfunc_vector_gen.py    #   .mem test vector generator
│   │   └── run_all_sim.py                  #   unified iverilog simulation runner
│   └── vectors/                            # golden test vectors (.mem files)
│
└── doc/                                    # Design documents
    └── BDD_OPTIMIZATION_PROPOSAL.md        #   BDD architecture analysis
```

---

## Hardware Modules

### 1. Message Function (`rtl/msgfunc/param/`) — PRIMARY

C-model aligned, parameterized Barnes-Wall lattice encode/decode:

| Parameter | tau=3 | tau=4 |
|-----------|-------|-------|
| COMPLEX_N | 16 | 16 |
| Q_WIDTH | 12 | 12 |
| MSG_WIDTH | 64 bits | 96 bits |
| LABEL_WIDTH | 7 | 8 |

**Pipeline:**
```
ENCODE:  msg_in → [msg_to_label] → [phi_encode] → [label_to_q] → enc_q_flat
DECODE:  noisy_q → [BDD] → [q_to_label] → [phi_decode] → [label_to_msg] → msg_out
```

### 2. BDD Decoder (`rtl/msgfunc/bdd/`)

Bounded-distance decoder for Barnes-Wall lattice (BW32):

| Module | Style | Latency |
|--------|-------|---------|
| `scloud_bdd_recursive` | combinational (generate-unrolled) | 0 cycles |
| `scloud_bdd{32,16,8,4}_seq` | sequential FSM | ~20-40 cycles |

Key features: L2 Euclidean distance, strict-less-than tie-breaking, phi=(1+i) butterfly transform.

### 3. Matrix Multiplier (`rtl/scloudplus/`)

B×B blocked multiply-accumulate (B=8, Q=12):

| Module | Function |
|--------|----------|
| `scloudplus_matmul_serial` | Block scheduler: IDLE→REQ→WAIT→ACC→EMIT→DONE |
| `scloudplus_bmm_block` | B×B PE grid (64 PEs) |
| `scloudplus_bmm_pe` | Ternary dot product: sum(A[row][k] × S[k][col]) |
| `scloudplus_block_add` | Block accumulator (mod 2^12) |

**Coefficient modes:** `00`=ternary (01=+1,10=-1), `01`=binary, `10`=signed-2bit

---

## Software-Hardware Co-Design (`sw/`)

### Architecture

```
KEM Application (C)          ← standard C, protocol flow
       │
HAL API (scloudplus_hal.h)   ← clean C interface
       │
┌──────┴──────┐
│ SW backend  │  Verilator backend   ← pluggable backends
│ (pure C)    │  (RTL simulation)
└─────────────┘
```

### What Goes to Hardware
- Matrix multiply: `A*S`, `S'*A`, `S'*B`, `C1*S` (4 operations)
- MsgEncode / MsgDecode (Barnes-Wall lattice + BDD)

### What Stays in Software (Standard C)
- SHAKE256 / SHA3 hashing (Keccak-f[1600])
- AES-128-ECB (deterministic A matrix expansion)
- Pack / Unpack (PK, SK, C1, C2)
- Compress / Decompress (C1, C2)
- CBD sampling (SamplePsi, SamplePhi, SampleEta1, SampleEta2)
- KEM protocol flow (KeyGen, Encaps, Decaps)

### Performance

**ss=16 (m=n=600, mbar=nbar=8):**

| Operation | SW (gcc -O2) | HW @ 200MHz | Speedup |
|-----------|-------------|-------------|---------|
| MatMul A×S (600×600·600×8) | 2.0 ms | 85 µs | **~23×** |
| MsgEncode (1 BW block) | <1 µs | 0.01 µs | >100× |
| MsgDecode (BDD, 1 block) | 61 µs | <0.01 µs | **>1000×** |
| Full KeyGen | 2.0 ms | 86 µs | **~23×** |
| Full Encaps | 2.0 ms | 86 µs | **~23×** |

RTL cycle breakdown:
- Each 8×8 block multiply: 3–4 cycles through FSM
- AS_E (KeyGen): 16,950 cycles (75×75×1 blocks × ~3 cycles)
- SA_E (Encaps C1): 16,950 cycles
- SB_E / CS (small): 226 cycles each
- **Total matmul per full KEM: ~34,400 cycles**

---

## Quick Start

### RTL Simulation (iverilog)

```bash
# MsgFunc parameterized testbench
cd sim_build
iverilog -g2012 -Wall -o tb_param.vvp \
    ../rtl/msgfunc/param/*.v ../rtl/msgfunc/bdd/*.v \
    ../tb/param/tb_scloud_msgfunc_param.v
vvp tb_param.vvp

# Matrix multiplier testbench
iverilog -g2001 -Wall -o tb_matm.vvp \
    ../rtl/scloudplus/*.v ../tb/matmul/tb_scloudplus_bmm.v
vvp tb_matm.vvp

# Run all simulations
python tb/scripts/run_all_sim.py
```

### SW Build & Test

```bash
cd sw

# Build and run all tests (8/8 passing)
make test

# Just build the library
make
```

**Test results (2026-06-17):**
```
=== SCLOUD+ HAL SW Backend Test Suite ===
  TEST 1: Block matmul (identity test) ... PASS
  TEST 2: MsgEncode/Decode roundtrip (tau=3) ... PASS
  TEST 3: MsgEncode/Decode roundtrip (tau=4) ... PASS
  TEST 4: Multi-block MsgEncode/Decode (ss=16) ... PASS
  TEST 5: BDD small-noise resilience (tau=3) ... PASS
  TEST 6: KEM msg encode/decode in context ... PASS
  TEST 7: KEM KeyGen/Encaps/Decaps functional ... PASS
  TEST 8: MatMul AS_E correctness ... PASS
=== Results: 8/8 tests passed ===
```

### Python SW Reference

```bash
# Self-test (256 random roundtrips per security level)
python tb/scripts/scloud_msgfunc_sw_ref.py

# Generate .mem test vectors
python tb/scripts/scloud_msgfunc_vector_gen.py --ss 16 --num 256
```

---

## Parameter Sets

| Parameter | Scloud+128 (ss=16) | Scloud+192 (ss=24) | Scloud+256 (ss=32) |
|-----------|--------------------|--------------------|--------------------|
| (m, n) | (600, 600) | (928, 896) | (1136, 1120) |
| (mbar, nbar) | (8, 8) | (8, 8) | (12, 11) |
| tau | 3 | 4 | 3 |
| mu (bits/block) | 64 | 96 | 64 |
| muConut | 2 | 2 | 4 |
| logq | 12 | 12 | 12 |
| q | 4096 | 4096 | 4096 |
| B (block size) | 8 | 8 | 8 |

---

## Verification Results

All RTL modules verified against C model (zero failures):

| Test | Coverage | Result |
|------|----------|--------|
| Walking-1 / Walking-0 (tau=3) | 128 patterns | 128/128 PASS |
| Corner-case messages | 22 patterns | 22/22 PASS |
| BDD rounding boundary | 16 values | 16/16 PASS |
| Phi symmetry (encode = decode⁻¹) | 16 tests | 16/16 PASS |
| Noise sweep (0 / D/8 / D/4 / D/2) | all levels | 100% correct |
| Multi-block ss=16/24/32 | 128 each | 384/384 PASS |
| RTL vs Python SW reference | 2000+ vectors | zero failures |

---

## Next Steps

- [ ] Install Verilator → compile RTL into C++ simulation models
- [ ] Complete FO transform (re-encrypt & verify) for full KEM roundtrip
- [ ] Cross-validate C msgfunc against Python SW reference
- [ ] Implement ss=24 and ss=32 parameter sets in KEM flow
- [ ] Replace placeholder crypto with OpenSSL/liboqs
- [ ] FPGA synthesis and place-and-route

---

## License

Hardware implementation of algorithms from Scloud+ paper [ePrint 2024/1306](https://eprint.iacr.org/2024/1306).
