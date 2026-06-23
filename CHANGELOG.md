# Changelog

## 2026-06-23 - 200 MHz constrained synthesis timing closure

### Measured result

- Vivado 2019.1 standalone synthesis for XC7A200T meets the 5.000 ns clock:
  WNS is +0.435 ns, TNS is 0, and there are zero failing setup endpoints.
- The remaining worst path is a registered four-term half-sum inside the
  BDD8 parallel distance engine. Its data-path delay is 4.187 ns with ten
  logic levels, safely below the constrained period at synthesis.
- Utilization is 8,618 LUT, 8,211 FF, and 40 DSP48 blocks. Compared with the
  pre-sum-pipeline run, LUT decreases by 50 and FF increases by 387.
- DRC still reports 40 MREG recommendations and standalone-top I/O warnings.
  The MREG warnings are no longer timing blockers and should not trigger more
  fabric pipeline stages without implementation evidence.
- Power is 0.659 W total and 0.526 W dynamic at Low confidence. Standalone
  external I/O and missing activity prevent sign-off use of these values.

### Decision

- Stop adding standalone RTL pipeline stages now that the real 200 MHz clock
  constraint is met at synthesis.
- Next closure step is integrated RCE subsystem implementation with real
  DPRAM/internal wiring, placement, routing, clocking, and switching activity.
- Reopen RTL pipelining only if integrated post-route timing fails on an
  identified internal path.

## 2026-06-23 - Two-stage distance sum reduction

### Constrained synthesis trigger

- Ready-chain decoupling recovered slice storage and reduced the design to
  8,668 LUT and 7,824 FF at 40 DSP48 blocks.
- WNS improved from -1.966 ns to -1.326 ns, TNS improved from -560.686 ns to
  -60.878 ns, and failing endpoints fell from 513 to 72.
- The worst 6.192 ns path is now the eight-term squared-distance sum tree from
  registered products to `sum_a_r`: 13 logic levels including ten CARRY4s.
  QoR reports 138 paths with this structure.

### Changed

- Split each parallel candidate distance sum into two half-width term groups.
  The two half sums are registered, then combined by one 32-bit addition in
  the following cycle.
- Applied the same two-stage reduction to the shared eight-lane sequential
  distance engine.
- Preserved exact 32-bit sums, candidate comparison, DSP count, and all
  interfaces. Each local distance transaction and each shared chunk gains one
  fixed cycle.

### Verification

- Parallel and sequential distance tests each pass 200 random cases plus two
  ties.
- RCE two/four-block fused and non-fused regressions pass.
- Timing, FF cost, and remaining failing endpoints require a new synthesis.

## 2026-06-23 - BDD ready-chain decoupling and MREG rollback

### Constrained synthesis result

- The chunk snapshot plus third product-register synthesis produced 8,704
  LUT, 8,867 FF, and 40 DSP48 blocks. WNS improved from -2.663 ns to
  -1.966 ns, TNS improved from -1382.924 ns to -560.686 ns, and failing
  endpoints fell from 899 to 513.
- The additional product registers were not absorbed into DSP MREG: all 40
  MREG warnings remain, while slice FF increased by about 1,224.
- The worst 6.584 ns path is now a seven-LUT, cross-hierarchy ready/start
  control chain ending at a BDD4 target-register clock enable. Route delay is
  77.5 percent. QoR also flags combined LUTs on this control path.

### Changed

- Decoupled BDD4/BDD8/BDD16 external `start_ready` from child and local
  distance readiness. Each node now reports readiness from its own IDLE state;
  BDD32 additionally requires both target halves loaded.
- This is safe because node `done` is emitted only after local distance and
  child transactions complete, and explicit one-cycle launch states prevent
  ready/done overlap from retriggering work.
- Removed the unabsorbed third product-register stage. The effective chunk
  snapshot and two product stages remain, recovering about 1K intended slice
  FF without changing arithmetic or interfaces.

### Verification

- Parallel and sequential distance tests each pass 200 random cases plus two
  ties.
- BDD4 recursive-reference comparison passes 100 tau3/tau4 random targets.
- RCE two/four-block fused and non-fused regressions pass.
- Timing, FF recovery, and control-route improvement require a new synthesis.

## 2026-06-23 - DSP multiplier register inference stage

### Trigger

- After candidate snapshots, DRC contains only 40 DSP MREG warnings plus the
  standalone-top I/O warnings. All DSP input and PREG warnings are gone.
- Vivado 2019.1 explicitly recommends an additional registered product stage
  for inferred multipliers when both MREG and PREG should be used.

### Changed

- Added a third consecutive registered square-product stage to both the
  parallel candidate-pair engine and the shared sequential distance engine.
- The distance sum trees now consume the third product register. Arithmetic,
  accumulation order, strict comparison, DSP count, and interfaces are
  unchanged.
- Local distance transactions gain one cycle; the shared engine gains one
  cycle per 8-lane chunk. If Vivado absorbs the registers as intended, the
  added storage maps primarily into DSP48 MREG/PREG rather than slice FFs.

### Verification

- Parallel pair and shared sequential distance tests each pass 200 random
  cases plus two ties.
- RCE tau3/tau4 two-block and tau3 four-block regressions pass.
- MREG absorption, timing, slice FF impact, and power require a new synthesis.

## 2026-06-23 - Shared distance chunk snapshot

### Constrained synthesis trigger

- The hierarchical candidate snapshot synthesis produced 8,923 LUT, 7,643
  FF, and 40 DSP48 blocks. WNS improved from -3.380 ns to -2.663 ns, TNS
  improved from -2169.470 ns to -1382.924 ns, and failing setup endpoints
  fell from 1,386 to 899.
- The worst 6.854 ns path is now inside `scloud_bdd_distance_seq`: the
  candidate phase and chunk index drive a wide candidate/target mux and shift,
  followed by modular subtraction into a DSP input register.
- DRC is reduced to 40 DSP MREG warnings plus standalone-top I/O warnings.
  DPIP and PREG warnings are eliminated. Power remains low-confidence at
  0.618 W because the synthesized standalone top lacks real switching data.

### Changed

- Added an 8-lane candidate/target chunk snapshot stage before modular
  subtraction in the shared sequential distance engine.
- Separated phase/chunk wide-bus selection from the difference and DSP input
  stage without changing distance arithmetic, DSP count, or interfaces.
- Each candidate chunk gains one fixed cycle; only 192 data bits are added to
  the shared engine rather than another full-width candidate copy.

### Verification

- Exact shared distance comparison passes 200 random cases plus two ties.
- BDD4 tau3/tau4 recursive-reference comparison passes 100 random targets.
- RCE two/four-block fused and non-fused regressions pass.
- Post-change timing and utilization require a new constrained synthesis.

## 2026-06-22 - Hierarchical candidate snapshot pipeline

### Constrained synthesis trigger

- The four-stage MsgDec phi pipeline synthesis produced 8,605 LUT, 6,449 FF,
  and 40 DSP48 blocks. WNS improved from -6.627 ns to -3.380 ns and TNS
  improved from -2671.024 ns to -2169.470 ns.
- The worst 7.568 ns path moved back into BDD32 candidate preparation. It
  crossed phi multiplication, candidate modular addition, distance modular
  subtraction, and the DSP input register in one cycle.

### Changed

- Added candidate A/B snapshot registers at BDD4, BDD8, BDD16, and BDD32.
  Distance engines now consume registered candidates, separating candidate
  construction from candidate-to-target subtraction.
- Added explicit one-cycle distance-launch states. This prevents a ready/done
  overlap from retriggering the BDD4/BDD8 local distance pipeline and keeps
  parent/child handshakes lossless.
- Preserved all distance widths, strict tie behavior, DSP count, and external
  interfaces. Each BDD node invocation gains one fixed preparation cycle.

### Verification

- BDD4 matched the tau3/tau4 recursive reference for 100 random targets.
- The RCE tau3/tau4 two-block fused and non-fused operations and tau3
  four-block decode/writeback regressions pass.
- Post-change timing and utilization require a new constrained synthesis.

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
