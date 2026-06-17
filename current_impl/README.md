# Scloud+ Current Implementation Snapshot

This directory collects the current primary implementation files for quick
inspection. These are copies of the active files from `rtl/` and `tb/`.

Do not treat this directory as the source of truth for development. Edit the
original files under `rtl/`, `tb/`, and `rtl/cmodel/`, then refresh this snapshot
if needed.

## Layout

| Directory | Purpose |
|-----------|---------|
| `rtl_msgfunc_param/` | Current top-level message-function RTL and config wrapper |
| `rtl_msgfunc_bdd/` | Current BDD decoder RTL chain and legacy combinational reference |
| `cmodel_reference/` | openHiTLS-aligned C model reference files |
| `tb_reference/` | Python bit-exact reference, vector scripts, and key testbenches |

## Primary RTL Files

| Snapshot file | Original file | Notes |
|---------------|---------------|-------|
| `rtl_msgfunc_param/scloud_msgfunc_param.v` | `rtl/msgfunc/param/scloud_msgfunc_param.v` | Main single-BW top module |
| `rtl_msgfunc_param/scloud_msgfunc_cfg_reg.v` | `rtl/msgfunc/param/scloud_msgfunc_cfg_reg.v` | Register-configurable wrapper |
| `rtl_msgfunc_bdd/scloud_bdd32_seq.v` | `rtl/msgfunc/bdd/scloud_bdd32_seq.v` | Sequential BW32 BDD |
| `rtl_msgfunc_bdd/scloud_bdd16_seq.v` | `rtl/msgfunc/bdd/scloud_bdd16_seq.v` | Sequential BW16 BDD |
| `rtl_msgfunc_bdd/scloud_bdd8_seq.v` | `rtl/msgfunc/bdd/scloud_bdd8_seq.v` | Sequential BW8 BDD |
| `rtl_msgfunc_bdd/scloud_bdd4_seq.v` | `rtl/msgfunc/bdd/scloud_bdd4_seq.v` | Leaf BDD rounder |
| `rtl_msgfunc_bdd/scloud_bdd_recursive.v` | `rtl/msgfunc/bdd/scloud_bdd_recursive.v` | Combinational legacy/reference BDD |

## Reference And Verification Files

| Snapshot file | Original file | Notes |
|---------------|---------------|-------|
| `cmodel_reference/scloudplus_util.c` | `rtl/cmodel/scloudplus_util.c` | C model message-function authority |
| `cmodel_reference/scloudplus.c` | `rtl/cmodel/scloudplus.c` | C model KEM top-level |
| `cmodel_reference/scloudplus_local.h` | `rtl/cmodel/scloudplus_local.h` | C model local parameters |
| `tb_reference/scloud_msgfunc_sw_ref.py` | `tb/scripts/scloud_msgfunc_sw_ref.py` | Python bit-exact reference |
| `tb_reference/scloud_msgfunc_vector_gen.py` | `tb/scripts/scloud_msgfunc_vector_gen.py` | Vector generation |
| `tb_reference/scloud_msgfunc_cmp_result.py` | `tb/scripts/scloud_msgfunc_cmp_result.py` | Pipeline comparison dump |
| `tb_reference/tb_scloud_msgfunc_param.v` | `tb/param/tb_scloud_msgfunc_param.v` | Main RTL testbench |
| `tb_reference/tb_scloud_msgfunc_cfg_reg.v` | `tb/param/tb_scloud_msgfunc_cfg_reg.v` | Config wrapper testbench |

## Current Simulation Command

Run from the repository root:

```bash
iverilog -g2001 -Wall -o sim_build/tb_param.vvp \
    rtl/msgfunc/param/*.v rtl/msgfunc/bdd/*.v \
    tb/param/tb_scloud_msgfunc_param.v
vvp sim_build/tb_param.vvp
```

## Refresh Snapshot

After editing the original files, refresh the snapshot by copying the same files
back into this directory.
