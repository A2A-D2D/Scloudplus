# Changelog

## 2026-06-22 - Four-stage MsgDec phi pipeline

### Constrained synthesis trigger

- The BDD4 pipeline synthesis produced 8,850 LUT, 5,546 FF, and 40 DSP48
  blocks. WNS improved from -11.392 ns to -6.627 ns and TNS improved from
  -3006.201 ns to -2671.024 ns.
- The worst 11.476 ns path left the BDD distance hierarchy and moved to
  MsgDec post-processing. It crossed Q-to-label extraction, all four recursive
  tau4 inverse-phi levels, label reduction, and `msg_result_r` capture in one
  cycle.

### Changed

- Added `scloud_msgfunc_phi_decode_layer` and
  `scloud_msgfunc_phi_decode_seq`. The four recursive inverse-phi levels now
  have explicit register boundaries.
- Added post-processing start/wait states to the RCE wrapper. Only the
  selected tau3 or tau4 pipeline runs for each block; the unselected path
  remains idle.
- Kept Q/label packing, fixed-width wrap behavior, message mapping, DPRAM
  format, and the external accelerator interface unchanged.

### Latency and verification

- The post-processing pipeline adds about five fixed cycles per decoded BW32
  block.
- Sequential tau3/tau4 phi decoding matched the original recursive
  combinational implementation for 200 random label vectors.
- RCE tau3/tau4 two-block fused and non-fused operations and tau3 four-block
  decode/writeback pass.
- Post-change timing and utilization require a new constrained synthesis.

## 2026-06-22 - BDD4 final distance-chain pipeline

### Constrained synthesis trigger

- The BDD8 pipeline synthesis produced 8,877 LUT, 5,008 FF, and 40 DSP48
  blocks. WNS improved to -11.392 ns, but TNS remained -3006.201 ns across
  1,281 failing endpoints.
- The worst 16.240 ns path moved into `scloud_bdd4_seq_rt` and still crossed
  phi/candidate arithmetic, one unregistered DSP square, the distance sum
  tree, strict A/B comparison, and decoded output selection in one cycle.
- All remaining 32 DPIP warnings and 16 PREG warnings belong to the two BDD4
  children. This confirms the BDD8 register boundary is effective and the
  last unpipelined distance trees are now the limiting paths.

### Changed

- Replaced each BDD4 candidate A/B combinational distance pair with the
  existing `scloud_bdd_distance_pair_pipe` configured for four coordinates.
- Preserved the total 40-DSP architecture, 12-bit modular subtraction,
  32-bit exact distance, and strict `<` tie-to-B behavior.
- Added explicit distance start/wait states at BDD4. BDD8 and its parents
  naturally observe the added fixed latency through the existing handshake.

### Verification boundary

- Exact parallel-pair and shared-distance unit regressions pass 200 random
  cases plus two explicit ties each.
- The pipelined BDD4 matched the recursive tau3/tau4 reference for 100 random
  targets.
- RCE tau3/tau4 two-block fused and non-fused operations and tau3 four-block
  decode/writeback pass with the BDD4 pipeline enabled.
- Timing, DRC, utilization, and full BDD32 latency must be refreshed after a
  new Vivado synthesis and uncongested BDD32 reference run.

## 2026-06-22 - BDD8 parallel distance pipeline

### Constrained synthesis trigger

- After pipelining the shared BDD32/BDD16 engine, the 5.000 ns standalone
  synthesis improved WNS from -17.908 ns to -13.357 ns, while TNS changed
  from -3086.235 ns to -3459.357 ns.
- The worst 18.205 ns path moved into the resident BDD8 kernel and crossed
  candidate phi logic, a parallel distance DSP, the sum tree, and final
  candidate selection.
- DSP input/PREG warnings fell to 64/32, identifying the 16 BDD8 parallel
  distance DSPs as the next targeted pipeline boundary. BDD4 remains
  unchanged.

### Changed

- Added `scloud_bdd_distance_pair_pipe`, retaining two fully parallel exact
  8-coordinate distance paths while separating modular difference, multiply,
  product register, sum, and strict comparison stages.
- Replaced only BDD8's two combinational distance trees with the pipelined
  pair. The 40-DSP architecture, 12-bit modular difference, 32-bit distance,
  and strict `<` tie-to-B behavior are unchanged.
- Kept pipeline data registers free of asynchronous reset so Vivado can map
  them into DSP48 pipeline stages; reset remains on control and outputs.

### Latency and verification

- BDD32 completes in 634 cycles in the randomized tau3/tau4 regression.
- The new BDD8 pair matched the combinational reference for 200 random cases
  plus two explicit ties. BDD32 matched recursive tau3/tau4 references for
  20 random cases, and the RCE two/four-block regression passed.
- Updated post-synthesis timing, utilization, and DRC results are pending a
  Vivado rerun with `constraints/scloud_msgfunc_rce.xdc`.

## 2026-06-22 - Shared distance DSP pipeline

### Constrained synthesis trigger

- Vivado 2019.1 standalone synthesis with the 5.000 ns XDC produced
  8,995 LUT, 4,219 FF, and 40 DSP48 blocks.
- Timing failed with WNS=-17.908 ns, TNS=-3086.235 ns, and 671 failing setup
  endpoints. The worst 22.756 ns path crossed candidate/phi logic, one DSP48,
  the lane sum, accumulation, and final comparison in `u_dist_seq`.
- DRC reported all 40 DSPs without input, MREG, or PREG pipelining. This met
  the documented condition for adding a targeted DSP pipeline.

### Changed

- Split each shared distance chunk into difference-input, multiply stage 1,
  multiply stage 2, lane-sum, and accumulation states.
- Moved the strict candidate A/B comparison into its own state.
- Kept DSP data registers in a no-reset clocked block so Vivado can absorb
  them into DSP48 AREG/MREG/PREG. The reset FSM guarantees every pipeline
  value is overwritten before use.
- Kept the low-level BDD8/BDD4 parallel distance trees unchanged until the
  next constrained synthesis identifies their actual timing impact.

### Latency and verification

- The pipeline adds 33 observed cycles per shared distance transaction and
  165 cycles per BDD32 operation because the engine is invoked five times.
- Exact distance comparison passed 200 random cases plus two explicit ties;
  ties still select candidate B.
- Random BDD32 tau3/tau4 equivalence and all RCE two/four-block fused and
  non-fused regressions passed.
- New timing and DSP-register DRC results are pending a Vivado rerun.

## 2026-06-22 - Two-beat BDD target and half-streamed Q datapath

### Changed

- Replaced the standalone `.sdc` file with the Vivado-native
  `constraints/scloud_msgfunc_rce.xdc` 200 MHz clock constraint.
- Replaced the flat 384-bit BDD32 target input with two independently selected
  192-bit valid/ready target-half beats. BDD32 keeps the only required full
  target copy internally and will not accept `start` until both halves arrive.
- Removed the wrapper's 384-bit `q_in_flat_r` and `q_aux_flat_r` registers.
  One 192-bit `q_half_r` now serves per-half `MSGENC_ADD` and `SUB_MSGDEC`.
- Changed `SUB_MSGDEC` scheduling to Q0/AUX0/Q1/AUX1 so each subtracted half
  is loaded directly into BDD32 before the scratch register is reused.
- Changed `MSGENC_ADD` to read, add, and write each half independently rather
  than constructing a 384-bit add result.
- Preserved 12-bit lane wrap, C-model/DPRAM packing, and all external RCE
  accelerator ports.

### Expected PPA effect

- Removes 768 wrapper Q-cache bits and adds one 192-bit scratch half, for a
  net reduction of 576 state bits before synthesis cleanup. This is an RTL
  estimate, not a new FF utilization report.

### Verified

- Two-beat BDD32 matched the fully parallel tau3/tau4 references on 20 random
  targets, including alternating low-first and high-first load order.
- Tau3 two-block and four-block MsgEnc/MsgDec passed.
- Tau4 two-block MsgEncAdd/SubMsgDec passed with per-half modular add/sub
  relation checks.
- `dec_write_q=1` rounded-Q writeback matched encoded Q over four blocks.

## 2026-06-22 - Hierarchical distance-engine sharing

### Changed

- Shared one exact 8-lane sequential distance engine between BDD32 and its
  resident BDD16 child. These two levels are active at disjoint times, so the
  former per-level engines were unnecessary duplication.
- Zero-extended BDD16's 16-coordinate distance requests into the shared
  32-coordinate engine. The added coordinates are all zero on candidate and
  target inputs, so they contribute exactly zero to both 32-bit distances.
- Preserved 12-bit squared differences, 32-bit accumulation, and strict `<`
  candidate selection. The external `scloud_bdd32_seq_rt` and RCE interfaces
  are unchanged.

### Expected PPA effect

- Removes one physical 8-lane square engine from the active hierarchy. Based
  on the previous 48-DSP distribution, the expected standalone count is about
  40 DSP48s; this estimate must be replaced by a new Vivado report before it
  is treated as measured data.
- Adds four distance scan cycles to each BDD16 invocation because the shared
  engine has the BDD32 32-coordinate depth. A BDD32 operation invokes BDD16
  four times, for a fixed 16-cycle latency increase.

### Verification

- Verilog-2001 elaboration passed with `iverilog -g2001 -Wall`.
- RCE tau3 roundtrip and tau4 fused-operation roundtrip passed.
- Exact sequential-versus-parallel distance comparison passed 200/200 cases.
- Shared BDD32 hierarchy matched the fully parallel recursive tau3/tau4
  references bit-for-bit on 20 randomized targets.
- SFR, all four matrix RTL suites, SW reference, C HAL 8/8, KAT-derived
  MsgFunc 9/9, and generated 192-vector stress report passed.
- The four-block RCE regression duration increased from 14.525 us to 15.165
  us at the testbench's 100 MHz clock, exactly matching 64 added cycles.

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

### DS-assisted HW/SW verification update

- Added a nine-vector openHiTLS KAT parser and KAT-derived SW verification
  chain for ss16, ss24, and ss32.
- Confirmed 9/9 KAT-message MsgFunc roundtrips and 2/2 RTL/SW MsgFunc cosim.
- Recorded the exact closure boundary: simplified A generation/sampling,
  incomplete pk/sk/ct/ss expected-value comparison, and an ss24 Encaps heap
  corruption mean that complete official KAT equivalence is not yet closed.
- Added `doc/SCLOUD_HW_SW_KAT_VERIFICATION.md` as the verification record.

### Documentation baseline refresh

- Promoted the factor-8 plus exact 8-lane architecture to the current design
  baseline throughout the technical and RCE integration documents.
- Marked the 256-DSP and 128-DSP sections as historical optimization stages.
- Replaced resource expectations with measured final results:
  9,271 LUT, 4,471 FF, 48 DSP48, 7,351 BDD LUT, and 3,394 BDD FF.
