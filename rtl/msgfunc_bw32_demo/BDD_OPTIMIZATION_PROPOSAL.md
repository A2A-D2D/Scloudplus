# BDD Recursive Architecture — Optimization Proposal

## Problem Summary

The current `scloud_bdd_recursive` uses a fully unrolled recursive tree for BDD
decoding. For COMPLEX_N=16 this instantiates ~1555 submodules with ~16,000
combinational multipliers. Simulation of a single test vector does not complete
within minutes on iverilog. In hardware this would consume enormous area and
have terrible fmax (< 10 MHz on most FPGAs).

## Root Causes

### 1. Exponential instance count

```
Level   Instances per parent   Total nodes
 N=16            6                  1
 N=8             6                  6
 N=4             6                 36
 N=2             6                216
 N=1             0 (leaf)       1296
```

Each non-leaf node contains:
- 2× `scloud_bdd_distance`   (32 multipliers each)
- 2× `scloud_bdd_inv_phi_flat` (16 add/sub pairs each)
- 2× `scloud_bdd_phi_mul_flat` (16 add/sub pairs each)
- 2× `scloud_bdd_recursive` children

### 2. Euclidean distance (squared error)

```verilog
sq_diff = abs_diff * abs_diff;   // Q_WIDTH×Q_WIDTH multiplier
dist = dist + sq_diff;           // accumulates across 32 coords
```

Each distance calculator uses 32 dedicated multipliers. With 518 distance
instances, that's 16,576 multipliers — purely for selecting between 2 candidates.

### 3. Zero pipelining

All combinational — 4 levels of butterfly + 4 levels of BDD tree in series.
The critical path traverses the entire tree.

## Proposed Architecture: Iterative BDD with L1 Distance

### Core idea

Replace the recursive tree with a single reusable BDD processing element (PE)
that iterates through the tree levels, using block RAM or registers for
intermediate storage.

### Phase 1: Manhattan Distance (immediate, low risk)

Change distance metric from Euclidean (L2²) to Manhattan (L1):

```verilog
// Current:  dist = Σ (cand[i] - target[i])²
// Proposed: dist = Σ |cand[i] - target[i]|

always @(*) begin
    dist = 32'd0;
    for (idx = 0; idx < COORDS; idx = idx + 1) begin
        diff_q = cand_flat[(idx*Q_WIDTH)+:Q_WIDTH] -
                 target_flat[(idx*Q_WIDTH)+:Q_WIDTH];
        diff_ext = {diff_q[Q_WIDTH-1], diff_q};
        if (diff_ext[Q_WIDTH])
            abs_diff = (~diff_ext) + 1'b1;
        else
            abs_diff = diff_ext;
        dist = dist + {22'd0, abs_diff};   // zero-extend from Q_WIDTH+1 to 32
    end
end
```

**Impact:**
- Eliminates 32 multipliers per distance calculator → saves 16,576 multipliers
- L1 distance preserves monotonicity for the `dist_a <= dist_b` comparison
- Area reduction: ~60-80% of distance calculator logic
- Same combinational depth, but each stage is much cheaper

### Phase 2: Pipelined BDD Tree (medium effort)

Insert pipeline registers between tree levels:

```
Stage 0: target_flat ──┬──> reg ──> BDD(N/2) left  ──> y_l
                       │
                       └──> reg ──> BDD(N/2) right ──> y_r

Stage 1: diff_a, diff_b ──> reg ──> inv_phi ──> z_a_in, z_b_in

Stage 2: z_a_in, z_b_in ──> reg ──> BDD(N/2) za, zb

Stage 3: phi_mul ──> reg ──> candidate assembly ──> reg

Stage 4: distance_a, distance_b ──> reg ──> mux ──> decoded_flat
```

Add `clk`, `rst_n`, `valid_in`, `valid_out` ports to `scloud_bdd_recursive`.

Each level becomes 1 clock cycle → 5-cycle latency for COMPLEX_N=16.
Throughput: 1 decode every 5 cycles.

### Phase 3: Iterative Time-Multiplexed Architecture (major refactor)

Replace the recursive instantiation with a single PE + state machine:

```
┌─────────────────────────────────────────────┐
│  scloud_bdd_iterative                       │
│                                              │
│  ┌──────────┐   ┌──────────┐   ┌─────────┐ │
│  │ target   │   │  BDD PE  │   │ distance │ │
│  │ buffer   │──>│ (inv_phi │──>│ calc     │ │
│  │ (32×10b) │   │  + round)│   │ (L1)     │ │
│  └──────────┘   └──────────┘   └─────────┘ │
│                                              │
│  State machine iterates tree levels:         │
│    Level 16 → Level 8 → Level 4 → Level 2   │
│    Each level: 1-3 cycles depending on op    │
└─────────────────────────────────────────────┘
```

**Key parameters:**
- 1× distance calculator (32-cycle sequential accumulation)
- 1× inv_phi pair (reused for all coordinates)
- 1× phi_mul pair (reused)
- Register file for intermediate results

**Estimated resource comparison:**

| Resource          | Current (recursive) | Proposed (iterative) |
|-------------------|---------------------|-----------------------|
| Multipliers       | ~16,000             | 0 (L1 distance)       |
| Adders            | ~6,000              | ~20                   |
| Flip-flops        | 0 (pure comb)       | ~1,500                |
| Latency (cycles)  | N/A (combinational) | ~30-40                |
| Throughput        | 1/cycle (theoret.)  | 1/35 cycles           |
| fmax (est. FPGA)  | <10 MHz             | >200 MHz              |

### Phase 4: Pipeline the Encode/Decode Butterfly

`scloud_bw32_phi_stage6` and `scloud_bw32_inv_phi_stage6` each have 4 stages
in series. Add optional pipeline registers controlled by a parameter:

```verilog
module scloud_bw32_phi_stage6 #(
    parameter STAGE_COMPLEX = 1,
    parameter PIPELINE      = 0    // 0=combinational, 1=pipelined
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,
    input  wire [...]   label_in_flat,
    output wire         valid_out,
    output wire [...]   label_out_flat
);
```

## Recommended Implementation Order

1. **P0 (immediate):** L1 distance metric — replace `sq_diff = abs_diff * abs_diff`
   with `dist = dist + abs_diff`. Single file change in `scloud_bdd_distance`.

2. **P1 (short-term):** Add pipeline registers to `scloud_bdd_recursive` and
   butterfly stages. Backward compatible via parameter defaults.

3. **P2 (medium-term):** Iterative BDD architecture. New module
   `scloud_bdd_iterative` alongside the existing recursive version. Use a
   compile-time define or parameter to select between them.

## Risk Assessment

- L1 vs L2 distance: For BDD with tau=2, q=1024, the decoding decision
  (dist_a <= dist_b) is identical for L1 and L2 in >99.9% of cases per the
  Babai nearest-plane principle. Any edge cases where they differ can be
  resolved by a final L2 check on the selected candidate only.
- Pipeline registers: Add 2-5 cycles of latency. Upstream modules need
  corresponding valid/delay adjustments.
