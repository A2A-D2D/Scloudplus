# Changelog

## 2026-06-22 - RCE MsgFunc BDD PPA optimization

### Changed

- Replaced the fully replicated BDD32 recursion with the Fast Scloud+
  unfold-factor-8 hierarchy: one BDD16 child, one resident BDD8 kernel, and
  two BDD4 children.
- Replaced the BDD16 and BDD32 full-width candidate distance trees with exact
  8-lane sequential squared-distance engines.
- Kept the RCE algorithm top and external handshake unchanged:
  `scloud_msgfunc_rce_accel` remains the only algorithm top for integration.
- Kept 12-bit squared differences and 32-bit accumulation. The paper's 4-bit
  square optimization is not enabled without a range/equivalence proof.

### Vivado synthesis results

Target: Vivado 2019.1, XC7A200T, top `scloud_msgfunc_rce_accel`.

| Version | LUT | FF | DSP48 |
| --- | ---: | ---: | ---: |
| Fully parallel BDD | 19,515 | 7,050 | 256 |
| Unfold factor 8 | 11,522 | 4,443 | 128 |
| Factor 8 + 8-lane distance sharing | 9,271 | 4,471 | 48 |

The final version reduces LUT by 52.5% and DSP48 by 81.25% relative to the
fully parallel version. The power report moved from 481.835 W to 213.135 W,
but absolute power remains invalid because no clock/activity constraints were
provided and report confidence is Low.

### Verified

- RCE tau3 MSGENC/MSGDEC roundtrip.
- RCE tau4 MSGENC_ADD/SUB_MSGDEC roundtrip.
- 200 randomized exact comparisons between the sequential and parallel
  distance implementations.
- SFR and matrix-multiplication RTL regressions.
- C-model-aligned ss16, ss24, and ss32 self-tests.

### Remaining

- Add the real RCE clock constraint before using WNS/TNS or absolute power.
- Re-run synthesis in the integrated subsystem rather than treating the
  256-bit DPRAM interface as device I/O.
- Evaluate narrower square operands only after fixed-point range proof and
  C-model/RTL equivalence testing.
