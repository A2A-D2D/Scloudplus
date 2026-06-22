# Scloud+ RCE Integration RTL

## Final RCE Accelerator Top

The only MsgFunc algorithm top intended for instantiation in `spu_subsystem` is:

```verilog
scloud_msgfunc_rce_accel
```

Recommended subsystem instance:

```verilog
scloud_msgfunc_rce_accel #(
    .DPRAM_ADDR_WIDTH(32),
    .Q_WIDTH         (12)
) u_scloud_msgfunc_rce_accel (...);
```

## Optional SFR Module

```verilog
spuv3_cfg_sfr_scloud
```

This is an optional replacement/extension for the existing `spuv3_cfg_sfr`.
It is instantiated beside the accelerator by `spu_subsystem`; it is not a
MsgFunc computation top.

## Internal Hierarchy

```text
scloud_msgfunc_rce_accel                  <- final algorithm top
  |-- scloud_msgenc_param (tau=3)
  |-- scloud_msgenc_param (tau=4)
  |-- scloud_bdd32_seq_rt                 <- one shared runtime-tau BDD
  |    |-- scloud_bdd16_seq_rt            <- one child, reused four times
  |    |    |-- scloud_bdd8_seq_rt        <- unfold-factor-8 resident kernel
  |    |    |    `-- 2 x scloud_bdd4_seq_rt
  |    `-- phi/inv_phi/distance helpers
  |-- tau3 q_to_label/phi_decode/label_to_msg
  `-- tau4 q_to_label/phi_decode/label_to_msg
```

The following names are helper/internal modules and must not be selected as
the RCE synthesis top:

```text
scloud_bdd32_seq_rt
scloud_bdd16_seq_rt
scloud_bdd8_seq_rt
scloud_bdd4_seq_rt
scloud_msgenc_param
scloud_msgfunc_q_to_label
scloud_msgfunc_phi_decode
scloud_msgfunc_label_to_msg
```

Legacy `scloud_msgdec_param` and `scloud_msgfunc_param` are disabled by
default. They are compiled only when `SCLOUD_ENABLE_FIXED_TAU_MSGFUNC` is
explicitly defined for archived fixed-tau regression.

## BDD32 Area Configuration

The active BDD32 is the unfold-factor-8 implementation inspired by Table 4
and Figure 7 of *Fast Scloud+: A Fast Hardware Implementation for Scloud+*.
BDD16 and BDD32 each issue four sequential child operations: left, right,
candidate A, and candidate B. This leaves one physical BDD8 kernel in the
elaborated hierarchy and requires 16 BDD8 iterations per BDD32 operation.

The RCE-facing module name and handshake are unchanged. This revision shares
the recursive kernels but intentionally retains exact 12-bit squared-distance
arithmetic. The paper's 4-bit square optimization remains gated on a formal
range/equivalence proof for the local fixed-point representation.

BDD32 loads one target through two 192-bit beats with `valid/ready`, a half
select, and a two-bit loaded mask. The wrapper converts each 256-bit DPRAM word
to one packed half and does not keep full Q-input or Q-auxiliary copies.
`SUB_MSGDEC` visits Q0/AUX0/Q1/AUX1 and uses one 192-bit scratch register;
`MSGENC_ADD` adds and writes Q0 and Q1 independently.

BDD16 and BDD32 share one 8-lane `scloud_bdd_distance_seq`. Their distance
phases are mutually exclusive in the resident hierarchy. BDD16 requests are
zero-extended to the shared 32-coordinate engine; the extra coordinates add
zero to both candidates. The lanes scan candidate A and candidate B in chunks
through registered difference, multiply, lane-sum, and accumulation stages,
then compare the same 32-bit squared distances as the parallel trees. BDD8
and BDD4 keep their parallel distance trees to limit the latency increase.
The last measured Vivado baseline had 48 DSPs. The shared-engine RTL removes
one 8-lane copy, so about 40 DSP48s are expected, but that figure is not yet a
new synthesis measurement.

## Filelist

Use:

```text
rtl/msgfunc/rce/scloud_msgfunc_rce.f
```

For standalone elaboration or synthesis, explicitly select:

```text
top = scloud_msgfunc_rce_accel
```
