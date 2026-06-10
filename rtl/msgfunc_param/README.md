# Scloud+ Parameterized MsgFunc

This directory contains a compile-time parameterized MsgEnc/MsgDec datapath for the Scloud+ Barnes-Wall message function.

It replaces the fixed `BW32/tau=2` wiring style with reusable parameters:

- `COMPLEX_N`: number of complex coordinates, e.g. `4`, `8`, `16` for BW8/BW16/BW32 q-domain coordinate counts of `8/16/32`.
- `LOG_COMPLEX_N`: `log2(COMPLEX_N)`.
- `Q_WIDTH`: q-domain element width.
- `TAU`: label width before Barnes-Wall delabeling reduction.
- `LABEL_WIDTH`: internal label arithmetic width. A practical default is `TAU + LOG_COMPLEX_N`.
- `MSG_WIDTH`: message bits in one MsgFunc block.

For the common `TAU=2` demo modes:

```text
BW8:   COMPLEX_N=4,  LOG_COMPLEX_N=2, MSG_WIDTH=12
BW16:  COMPLEX_N=8,  LOG_COMPLEX_N=3, MSG_WIDTH=20
BW32:  COMPLEX_N=16, LOG_COMPLEX_N=4, MSG_WIDTH=32
```

The module hierarchy is:

```text
scloud_msgfunc_param
  scloud_msgenc_param
    scloud_msgfunc_msg_to_label
    scloud_msgfunc_phi_encode
    scloud_msgfunc_label_to_q
  scloud_msgdec_param
    scloud_bdd_recursive
    scloud_msgfunc_q_to_label
    scloud_msgfunc_phi_decode
    scloud_msgfunc_label_to_msg
```

`scloud_msgfunc_param` is still a compile-time parameterized RTL block. It is not a runtime `tau_sel` multi-mode wrapper. That choice keeps the synthesized datapath smaller and easier to time. If runtime switching is required, instantiate several parameterized cores or add a wrapper with explicit muxing.

Flat q-domain buses are LSB-first:

```text
coord0.re, coord0.im, coord1.re, coord1.im, ...
```

The testbench `tb_scloud_msgfunc_param.v` instantiates BW8, BW16, and BW32 configurations and checks zero-noise plus small-noise round trips.
