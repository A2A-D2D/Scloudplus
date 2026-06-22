# AGENTS.md - Scloud+ RCE Project Guide

## Scope And Authority

This file is the primary onboarding guide for AI agents working in this
repository. It describes the active implementation as of 2026-06-22.

- Treat live RTL, tests, and current synthesis reports as the final authority.
- `CLAUDE.md` describes an older fixed-tau layout and is not authoritative for
  the current RCE implementation.
- Do not restore archived files into the active build unless explicitly asked.
- The worktree may contain user changes. Never revert, overwrite, archive, or
  commit unrelated changes.

## Project Goal

This repository implements Scloud+ post-quantum KEM hardware building blocks,
with emphasis on integrating the Barnes-Wall MsgEnc/MsgDec accelerator into
SPUV3 RCE with good power, performance, and area.

The active design uses a dedicated DPRAM-side accelerator. It does not force
the 384-bit BW32 payload through the 320-bit VPU register path and does not
reuse the RSA arithmetic datapath.

## Unique RCE Top

The only MsgFunc algorithm top that should be instantiated in `spu_subsystem`
or selected as the synthesis top is:

```verilog
scloud_msgfunc_rce_accel
```

Source:

```text
rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v
```

`spuv3_cfg_sfr_scloud` is an optional SFR extension beside the accelerator. It
is not the algorithm top. BDD, MsgEnc, phi, and label modules are internal.

Use this filelist:

```text
rtl/msgfunc/rce/scloud_msgfunc_rce.f
```

## Current Architecture

```text
scloud_msgfunc_rce_accel
  |-- scloud_msgenc_param, tau=3
  |-- scloud_msgenc_param, tau=4
  |-- scloud_bdd32_seq_rt
  |     |-- one scloud_bdd16_seq_rt child, reused for YL/YR/ZA/ZB
  |     |     `-- one resident scloud_bdd8_seq_rt
  |     |           `-- two parallel scloud_bdd4_seq_rt children
  |     `-- one 8-lane exact sequential distance engine shared by BDD32/BDD16
  |-- tau3 q_to_label / phi_decode / label_to_msg
  `-- tau4 q_to_label / phi_decode / label_to_msg
```

The BDD follows the Fast Scloud+ unfold-factor-8 area/latency trade-off:

- One runtime-tau datapath serves tau3 and tau4.
- BDD32 and BDD16 each serialize four child calls: YL, YR, ZA, and ZB.
- A resident BDD8 kernel is called 16 times per BDD32 operation.
- BDD32 and BDD16 share one exact 8-lane sequential distance engine. BDD16
  requests are zero-extended into its 32-coordinate input.
- BDD8 and BDD4 retain parallel distance logic to avoid excessive latency.
- Distance arithmetic remains 12-bit squared difference with 32-bit sum.
- Candidate selection must remain strict `<`; a tie selects candidate B.
- The paper's 4-bit square optimization is disabled until range and
  equivalence proofs exist.

## RCE Operations And Dataflow

The wrapper supports four operations:

```text
0 MSGENC
1 MSGDEC
2 MSGENC_ADD
3 SUB_MSGDEC
```

Payload moves through 256-bit DPRAM words. One BW32 Q block contains 32
12-bit coordinates and occupies two DPRAM words. Control comes from decoded
SFR fields: op, tau, block count, base addresses, start, and `dec_write_q`.

Fused operations are part of the PPA design:

- `MSGENC_ADD` avoids writing and rereading an intermediate encoded matrix.
- `SUB_MSGDEC` avoids writing and rereading the Decaps difference matrix.
- `dec_write_q=0` skips rounded-Q writeback when only the message is needed.

## Parameters

| Security set | tau | mu | Blocks | Message/block | Total message |
| --- | ---: | ---: | ---: | ---: | ---: |
| ss16 | 3 | 64 | 2 | 8 bytes | 16 bytes |
| ss24 | 4 | 96 | 2 | 12 bytes | 24 bytes |
| ss32 | 3 | 64 | 4 | 8 bytes | 32 bytes |

Common constants:

```text
Q_WIDTH = 12
modulus representation = modulo 2^12 / 12-bit wrap in MsgFunc datapaths
BW complex coordinates = 16
BW real coordinates = 32
```

Do not mix these with archived tau=2, Q_WIDTH=10 examples.

## Active Files

Core RTL:

```text
rtl/msgfunc/bdd/scloud_bdd_recursive.v
rtl/msgfunc/bdd/scloud_bdd_seq_rt.v
rtl/msgfunc/param/scloud_msgfunc_param.v
rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v
rtl/msgfunc/rce/spuv3_cfg_sfr_scloud.v
rtl/msgfunc/rce/scloud_msgfunc_rce.f
```

Matrix RTL:

```text
rtl/scloudplus/scloudplus_matmul_serial.v
rtl/scloudplus/scloudplus_bmm_block.v
rtl/scloudplus/scloudplus_bmm_pe.v
rtl/scloudplus/scloudplus_block_add.v
```

Reference and verification:

```text
rtl/cmodel/
tb/rce/
tb/matmul/
tb/scripts/scloud_msgfunc_sw_ref.py
tb/scripts/scloud_msgfunc_vector_gen.py
tb/scripts/scloud_msgfunc_gen_result.py
tb/scripts/run_verify.sh
tb/vectors/
```

## Current Synthesis Baseline

Vivado 2019.1, XC7A200T, synthesis top `scloud_msgfunc_rce_accel`:

| Metric | Current | Initial fully parallel | Change |
| --- | ---: | ---: | ---: |
| Total LUT | 9,271 | 19,515 | -52.5% |
| FF | 4,471 | 7,050 | -36.6% |
| DSP48 | 48 | 256 | -81.25% |
| BDD LUT | 7,351 | 15,760 | -53.4% |
| BDD FF | 3,394 | 5,967 | -43.1% |

The last measured 48-DSP baseline used 8 at BDD32, 8 at BDD16, and 32 in the
resident BDD8 hierarchy. The active shared-engine RTL removes the BDD16 copy,
so about 40 DSP48s are expected; this remains an estimate until Vivado is rerun.

The reported 213.135 W power is Low confidence and not sign-off data. The
standalone design has no user clock constraint or switching activity and
treats wide internal DPRAM buses as external I/O. Timing has no valid WNS/TNS.
Add the real RCE clock and run integrated implementation before making Fmax or
absolute-power claims.

## Verification Commands

Run the unified suite from the repository root when Bash tools are available:

```bash
bash tb/scripts/run_verify.sh --full
```

Run the software reference self-test:

```bash
python tb/scripts/scloud_msgfunc_sw_ref.py
```

Elaborate and run the RCE test:

```bash
iverilog -g2001 -Wall -o build/tb_rce_accel.vvp \
  rtl/msgfunc/bdd/scloud_bdd_recursive.v \
  rtl/msgfunc/bdd/scloud_bdd_seq_rt.v \
  rtl/msgfunc/param/scloud_msgfunc_param.v \
  rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v \
  tb/rce/tb_scloud_msgfunc_rce_accel.v
vvp build/tb_rce_accel.vvp
```

Run exact distance equivalence:

```bash
iverilog -g2001 -Wall -o build/tb_bdd_dist.vvp \
  rtl/msgfunc/bdd/scloud_bdd_recursive.v \
  rtl/msgfunc/bdd/scloud_bdd_seq_rt.v \
  tb/rce/tb_scloud_bdd_distance_seq.v
vvp build/tb_bdd_dist.vvp
```

Run shared BDD32 hierarchy equivalence:

```bash
iverilog -g2001 -Wall -o build/tb_bdd32_rt.vvp \
  rtl/msgfunc/bdd/scloud_bdd_recursive.v \
  rtl/msgfunc/bdd/scloud_bdd_seq_rt.v \
  tb/rce/tb_scloud_bdd32_seq_rt.v
vvp build/tb_bdd32_rt.vvp
```

Expected primary markers:

```text
TB_PASS scloud_msgfunc_rce_accel
TB_PASS scloud_bdd_distance_seq cases=200
TB_PASS scloud_bdd32_seq_rt cases=20
TB_PASS spuv3_cfg_sfr_scloud
TB_PASS scloudplus_bmm
=== ALL SELF-TESTS PASSED ===
```

## HW/SW And KAT Status

The DS-assisted chain parses nine openHiTLS KAT vectors: three each for ss16,
ss24, and ss32.

Confirmed:

- KAT-derived SW MsgFunc roundtrip: 9/9 PASS.
- Local SHAKE256 repeatability: 9/9 PASS.
- RTL MsgEncode/MsgDecode HW/SW cosim: 2/2 PASS.
- C HAL functional suite: 8/8 PASS.
- Sequential distance versus parallel distance: 200/200 PASS.

Do not claim complete official KAT closure. The local KEM uses simplified A
generation/sampling, does not yet compare every pk/sk/ciphertext/shared-secret
field byte-for-byte, and a local rerun encountered heap corruption during
ss24 Encaps. See `doc/SCLOUD_HW_SW_KAT_VERIFICATION.md`.

## Coding Rules

- Active RTL is pure synthesizable Verilog-2001. Do not introduce `logic`,
  `always_ff`, `always_comb`, packages, interfaces, classes, or UVM.
- Preserve fixed-width wrap behavior. Do not replace modular arithmetic with
  saturation or host-language signed arithmetic without proof.
- Preserve C-model bit packing and strict BDD tie-breaking.
- Keep changes scoped. Avoid unrelated formatting or refactors.
- Use structural parsers/APIs for generated data where practical.
- Add tests in proportion to the changed datapath and PPA risk.

## Git And Generated Artifacts

- Inspect `git status` before editing and before committing.
- Assume unknown modifications belong to the user; work with them.
- Stage and commit only files belonging to the requested change.
- Do not commit `build/`, VCD/VVP files, Python cache files, generated binaries,
  or external Vivado report directories unless explicitly requested.
- Keep architecture and measured PPA changes in `CHANGELOG.md`.
- Use descriptive commit messages; avoid generic messages such as
  `update rtl code`.

## Integration Checklist

Before claiming top-level RCE integration complete, verify:

1. `scloud_msgfunc_rce_accel` is instantiated in `spu_subsystem`.
2. Opcode, tau, block count, base addresses, and `dec_write_q` are connected.
3. DPRAM Port A arbitration prevents simultaneous RSA/Scloud/core ownership.
4. Host access is blocked or defined while Scloud owns the DPRAM.
5. `busy/done/error/interrupt` join the existing RCE status path.
6. SFR addresses use one consistent byte-versus-word convention.
7. A real clock constraint is present in subsystem synthesis.
8. Tau3 two-block, tau4 two-block, and tau3 four-block tests pass.

## Documentation Map

```text
README.md
  Project entry point and commands

doc/SCLOUD_MSGFUNC_RCE_TECHNICAL_DESIGN.md
  Detailed architecture, FSM/dataflow, PPA evolution, and implementation

doc/SCLOUD_MSGFUNC_SPUV3_RCE_PPA_INTEGRATION_REPORT.md
  RCE integration boundary, interfaces, opcodes, and subsystem guidance

doc/SPU_SUBSYSTEM_SCLOUD_TOP_INTEGRATION.md
  Concrete top-level wiring guidance

doc/SCLOUD_HW_SW_KAT_VERIFICATION.md
  KAT-derived evidence, HW/SW cosim status, and closure boundary

CHANGELOG.md
  Versioned architecture and synthesis record
```

## Definition Of Done

For RTL changes, do not stop after editing. A complete change normally needs:

1. Verilog elaboration without errors or width warnings.
2. Relevant self-checking RTL regression.
3. C-model or parallel-reference comparison when algorithm behavior changes.
4. Updated architecture/PPA documentation when hierarchy or resources change.
5. A scoped Git commit that does not include unrelated user work.
