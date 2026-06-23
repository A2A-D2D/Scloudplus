# Scloud+ Optimized Hardware Working Set

This repository keeps the active optimized Scloud+ MsgFunc/RCE work, the matrix-multiplication implementation, and the C/software reference chain required for bit-exact verification. Superseded RTL, duplicate snapshots, generated outputs, and obsolete tests are preserved under `archive/`.

## Current RCE Baseline

The active MsgFunc design uses one runtime-tau BDD32, Fast Scloud+
unfold-factor-8 recursion reuse, and one exact 8-lane sequential distance
engine shared by BDD32/BDD16. BDD8/BDD4 retain parallel distance logic to
bound latency.

The shared 8-lane engine and the low-level parallel distance trees pipeline
difference, multiply, reduction, and comparison stages. Explicit hierarchical
launch states prevent child-start control from spanning multiple BDD levels.

BDD32 now accepts its 384-bit target as two 192-bit beats. The RCE wrapper
streams Q halves directly from DPRAM and retains only one 192-bit scratch half
for fused add/sub operations instead of two full 384-bit Q caches.

Vivado 2019.1 synthesis for XC7A200T, top `scloud_msgfunc_rce_accel`:

| LUT | FF | DSP48 | BDD LUT | BDD FF |
| ---: | ---: | ---: | ---: | ---: |
| 8,680 | 7,274 | 40 | 7,189 | 5,860 |

With a 5.000 ns clock constraint, standalone synthesis reports WNS +0.020 ns,
TNS 0, and no failing setup endpoints. This is synthesis closure, not timing
sign-off: the 20 ps margin is too small to assume routed subsystem closure.

Relative to the initial fully parallel BDD, LUT is down 55.5% and DSP48 is
down 84.4%; FF is up 3.2% because of timing pipelines. Estimated power is
0.578 W at Low confidence. Final timing and power require implementation in
the real RCE subsystem with internal DPRAM wiring and representative activity.

## Active RTL

```text
rtl/
  cmodel/                            # official C implementation reference
    scloudplus.c
    scloudplus_util.c
    scloudplus.h
    scloudplus_local.h
  msgfunc/
    bdd/
      scloud_bdd_recursive.v       # shared phi/distance helpers
      scloud_bdd_seq_rt.v          # one runtime-tau sequential BDD
    param/
      scloud_msgfunc_param.v       # active encode and label/message helpers
    rce/
      scloud_msgfunc_rce_accel.v   # DPRAM-side RCE accelerator
      spuv3_cfg_sfr_scloud.v       # SFR extension for RCE integration
      scloud_msgfunc_rce.f         # filelist; top=scloud_msgfunc_rce_accel
  scloudplus/
    scloudplus_matmul_serial.v
    scloudplus_bmm_block.v
    scloudplus_bmm_pe.v
    scloudplus_block_add.v
constraints/
  scloud_msgfunc_rce.xdc           # 200 MHz standalone Vivado constraint
```

## Active Verification

```text
tb/rce/                            # optimized MsgFunc and SFR tests
tb/matmul/                         # matrix-multiplication tests
tb/vectors/msgfunc_sw/             # active MsgFunc golden vectors
tb/vectors/scloudplus*/            # matrix vectors
tb/scripts/scloud_msgfunc_*         # software reference/vector tools
tb/scripts/*matm*                   # matrix-vector and simulation scripts
```

## C/Software Reference

The RTL roundtrip test proves internal consistency. Bit-exact validation must also use the active C/software reference chain:

```text
rtl/cmodel/
tb/scripts/scloud_msgfunc_sw_ref.py
tb/scripts/scloud_msgfunc_vector_gen.py
tb/scripts/scloud_msgfunc_gen_result.py
tb/vectors/msgfunc_sw/
```

Run the software reference self-test with:

```powershell
python tb/scripts/scloud_msgfunc_sw_ref.py
```

Expected result:

```text
=== ALL SELF-TESTS PASSED ===
```

## Documentation

```text
doc/SCLOUD_MSGFUNC_RCE_TECHNICAL_DESIGN.md
doc/SCLOUD_MSGFUNC_SPUV3_RCE_PPA_INTEGRATION_REPORT.md
doc/SPU_SUBSYSTEM_SCLOUD_TOP_INTEGRATION.md
doc/SCLOUD_HW_SW_KAT_VERIFICATION.md
```

## HW/SW KAT Verification

The DS-assisted verification chain parses nine openHiTLS KAT vectors covering
ss16, ss24, and ss32. Confirmed results include 9/9 KAT-derived SW MsgFunc
roundtrips and an RTL/SW MsgFunc cosim result of 2/2 PASS.

This is not yet a complete byte-exact openHiTLS KAT closure: the local model
uses simplified A generation/sampling, and pk/sk/ciphertext/shared-secret
comparison is incomplete. See
[`doc/SCLOUD_HW_SW_KAT_VERIFICATION.md`](doc/SCLOUD_HW_SW_KAT_VERIFICATION.md)
for evidence and remaining work.

## RCE MsgFunc Test

```powershell
$tmp = Join-Path $env:TEMP "scloud_rce_test"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

iverilog -g2001 -Wall -s tb_scloud_msgfunc_rce_accel `
  -o "$tmp/tb_rce.vvp" `
  rtl/msgfunc/bdd/scloud_bdd_recursive.v `
  rtl/msgfunc/bdd/scloud_bdd_seq_rt.v `
  rtl/msgfunc/param/scloud_msgfunc_param.v `
  rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v `
  tb/rce/tb_scloud_msgfunc_rce_accel.v

Push-Location $tmp
vvp ./tb_rce.vvp
Pop-Location
```

Expected result:

```text
TB_PASS scloud_msgfunc_rce_accel
```

## SFR Test

```powershell
iverilog -g2001 -Wall -s tb_spuv3_cfg_sfr_scloud `
  -o "$tmp/tb_sfr.vvp" `
  rtl/msgfunc/rce/spuv3_cfg_sfr_scloud.v `
  tb/rce/tb_spuv3_cfg_sfr_scloud.v

Push-Location $tmp
vvp ./tb_sfr.vvp
Pop-Location
```

Expected result:

```text
TB_PASS spuv3_cfg_sfr_scloud
```

## Archive

The cleanup performed on 2026-06-22 is recorded in:

```text
archive/repo_cleanup_20260622/ARCHIVE_MANIFEST.md
```
