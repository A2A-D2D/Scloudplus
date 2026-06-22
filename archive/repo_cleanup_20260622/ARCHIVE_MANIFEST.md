# Repository Cleanup Archive - 2026-06-22

This directory contains files moved out of the active Scloud+ working set. No archived source was deleted.

## Active Working Set Kept

- Optimized RCE MsgFunc wrapper and SFR extension
- Runtime-tau BDD and shared BDD helper modules
- Active parameterized MsgEnc and label/message helper RTL
- Matrix-multiplication RTL
- RCE and matrix-multiplication testbenches
- Matrix vectors and matrix-related scripts
- Matrix software HAL/model
- Current RCE integration and technical documents
- Official C model, MsgFunc software reference scripts, and golden vectors

## Archived Groups

- Previous `current_impl` snapshot
- Fixed-tau BDD RTL and its tests
- Previous configurable BW8/BW16/BW32 MsgFunc wrapper
- Previous parameterized/fixed-tau MsgFunc tests and vector scripts
- KEM software flow and duplicate software snapshots
- Generated simulation/build outputs
- Previous optimization/reference documents and PDFs

## Restore

Files preserve their original paths below this directory. To restore an item, move it from:

```text
archive/repo_cleanup_20260622/<original-relative-path>
```

back to:

```text
<original-relative-path>
```

Do not restore fixed-tau BDD files into the optimized RCE filelist unless `SCLOUD_ENABLE_FIXED_TAU_MSGFUNC` is also intentionally enabled.
