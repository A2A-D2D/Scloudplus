# Scloud+ Parameterized MsgFunc (C-Model Aligned)

This directory contains the **primary** compile-time parameterized MsgEnc/MsgDec data path for the Scloud+ Barnes-Wall message function. The implementation is bit-exact aligned with the openHiTLS C reference model in [`../../cmodel/`](../../cmodel/).

## Parameters

| Parameter | Description | tau=3 (ss=16/32) | tau=4 (ss=24) |
|-----------|-------------|-------------------|----------------|
| `COMPLEX_N` | complex coordinates (= BW32) | 16 | 16 |
| `LOG_COMPLEX_N` | log2(COMPLEX_N) | 4 | 4 |
| `Q_WIDTH` | Q-domain element width | **12** | **12** |
| `TAU` | label bit-width before reduction | **3** | **4** |
| `LABEL_WIDTH` | internal label arithmetic width (= TAU + LOG_COMPLEX_N) | 7 | 8 |
| `MSG_WIDTH` | message bits per block (= (CN\*2TAU) - (CN\*logCN)/2) | **64** | **96** |

Contrast with the **legacy** fixed-size paths (bw8/bw16/bw32_combo/bw32_seq) which use simplified parameters `TAU=2, Q_WIDTH=10` and do NOT match the C model.

## Key Design Changes (vs Legacy)

| Aspect | Legacy (bw32_*) | Parameterized (param) |
|--------|-----------------|----------------------|
| Parameters | tau=2, Q_WIDTH=10 | tau=3/4, Q_WIDTH=12 |
| msg->label mapping | generic popcount-based (MSB-first sequential) | hardcoded C-model bit-packing (tau=3 & tau=4 blocks) |
| label->msg reduction | generic WH-based | hardcoded C-model DelabelingReduceW + DelabelingComputeU |
| BDD distance | L1 (Manhattan) | **L2 (Euclidean)** matching C model |
| BDD tie-breaking | dist_a <= dist_b | **dist_a < dist_b** matching C model |
| phi arithmetic | modular unsigned with sign-extension | same sign-extended arithmetic |
| Round function | (x + Delta/2) & ROUND_MASK | same (equivalent to C signed Round for unsigned Q-domain inputs) |

The `msg_to_label` and `label_to_msg` modules contain **hardcoded** tau=3 and tau=4 implementations matching the C model's `LabelingComputeV`/`DelabelingComputeU` bit-by-bit. A generic popcount-based fallback (`gen_generic`) is preserved for non-standard parameter combinations.

## Module Hierarchy

```
scloud_msgfunc_cfg_reg          -- register-configurable wrapper
  └── scloud_msgfunc_param      -- BW32 single-block MsgFunc

scloud_msgfunc_param
  ├── scloud_msgenc_param
  │     ├── scloud_msgfunc_msg_to_label    -- msg bits -> 32 label lanes
  │     ├── scloud_msgfunc_phi_encode      -- 4-stage Barnes-Wall butterfly
  │     └── scloud_msgfunc_label_to_q      -- labels -> Q-domain (shift by Q_WIDTH-TAU)
  └── scloud_msgdec_param
        ├── scloud_bdd_recursive           -- bounded-distance decoder (Euclidean L2)
        ├── scloud_msgfunc_q_to_label      -- Q-domain -> labels
        ├── scloud_msgfunc_phi_decode      -- inverse butterfly
        └── scloud_msgfunc_label_to_msg    -- labels -> msg bits (with DelabelingReduceW)

scloud_bdd_recursive
  ├── scloud_bdd_round_coord_q    -- (x + Delta/2) & ROUND_MASK
  ├── scloud_bdd_phi_mul_pair_q   -- (1+i) multiply: y_re = b_re - b_im, y_im = b_re + b_im
  ├── scloud_bdd_inv_phi_pair_q   -- (1-i)/2 divide: sign-extended (d_re+d_im)>>1, (d_im-d_re)>>1
  ├── scloud_bdd_sq_diff_q        -- squared diff: (cand - target)^2 (signed multiply)
  └── scloud_bdd_distance_tree    -- sum tree: 32 terms of 26-bit -> 32-bit L2 distance
```

## Testbench

[`tb/param/tb_scloud_msgfunc_param.v`](../../../tb/param/tb_scloud_msgfunc_param.v) instantiates **two** MsgFunc cores:
- `dut_tau3`: TAU=3, MSG_WIDTH=64
- `dut_tau4`: TAU=4, MSG_WIDTH=96

Both use Q_WIDTH=12. The testbench verifies zero-noise and small-noise roundtrip correctness.

[`tb/param/tb_scloud_msgfunc_cfg_reg.v`](../../../tb/param/tb_scloud_msgfunc_cfg_reg.v) tests the register-configurable wrapper which supports runtime `cfg_bw_mode` selection.

## Verification

Python SW reference bit-exact match verified across 2000+ test vectors (zero failures). See top-level [`README.md`](../../../README.md) for complete verification results.

```bash
# Self-test
python tb/scripts/scloud_msgfunc_sw_ref.py

# Full pipeline comparison vectors
python tb/scripts/scloud_msgfunc_cmp_result.py

# Generate .mem test vectors
python tb/scripts/scloud_msgfunc_vector_gen.py --ss 16 --num 256
```

## Related Directories

| Directory | Description |
|-----------|-------------|
| [`../../cmodel/`](../../cmodel/) | openHiTLS C reference model |
| [`../bdd/`](../bdd/) | Shared BDD decoder engine |
| [`../bw8/`](../bw8/), [`../bw16/`](../bw16/), [`../bw32_combo/`](../bw32_combo/), [`../bw32_seq/`](../bw32_seq/) | Legacy fixed-parameter implementations (tau=2, Q_WIDTH=10) |
| [`../../../tb/scripts/`](../../../tb/scripts/) | Python SW reference & verification scripts |
| [`../../scloudplus/`](../../scloudplus/) | Scloud+ blocked matrix multiplier |

> **Reference**
> Anyu Wang, Zhongxiang Zheng, Chunhuan Zhao, Guang Zeng, Ye Yuan, Zhiyuan Qiu, Changchun Mu, Xiaoyun Wang.
> *Scloud+: a Lightweight LWE-based KEM without Ring/Module Structure.*
> IACR Cryptology ePrint Archive, Report 2024/1306, 2024.
> [https://eprint.iacr.org/2024/1306](https://eprint.iacr.org/2024/1306)
