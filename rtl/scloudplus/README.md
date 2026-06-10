# Scloud+ Block Matrix Multiplier

This directory contains a Verilog-2001 reproduction of the matrix-multiplication core described in Section 3.2 of `fast-scloud+.pdf`. The compute datapath uses Verilog `generate` blocks for regular PE and lane replication, while avoiding Verilog `function`/`task` definitions in synthesizable RTL.

Scope note: this is the Scloud+ MatM submodule only. It does not implement the full Scloud+ PKE/KEM flow, MsgEnc/MsgDec, BW32 labeling/delabeling, BDD, sampling, or ciphertext packing.

## Paper Mapping

The paper computes matrix products such as `A * S`, `S' * A`, `S' * B`, and `C1' * S` with square `b x b` blocks. Because `S` and `S'` are ternary matrices, each processing element avoids a general multiplier:

- `s = 00` or `11`: select `0`
- `s = 01`: select `+A`
- `s = 10`: select `-A mod 2^q`

The selected terms are summed and the low `q` bits are kept, giving reduction modulo `2^q`. The right-multiplication case `S' * A` can be scheduled as `(S' * A)^T = A^T * S'^T`, so the same block multiplier datapath can be reused by transposing block addresses/data externally.

## Files

- `scloudplus_bmm_pe.v`: one parameterized PE for a ternary dot product.
- `scloudplus_bmm_block.v`: parameterized `b x b` block multiply with `b^2` generated PEs.
- `scloudplus_block_add.v`: generated element-wise block accumulation modulo `2^q`.
- `scloudplus_matmul_serial.v`: block scheduler using one block multiplier over `(row, inner, col)` block indices. Incoming `a_block` and `s_block` are latched when `blk_in_valid` is accepted in `ST_WAIT`, so the upstream source may assert `blk_in_valid` for one cycle and change the block buses afterward.

## Runtime Configuration

The main configurable ports are:

- `cfg_b_active`: active block edge length, up to the synthesis parameter `B`.
- `cfg_q_active`: active modulus width, up to the synthesis parameter `Q_WIDTH`; results are reduced modulo `2^cfg_q_active`.
- `cfg_coeff_mode`: coefficient interpretation for the right matrix.
  - `0`: ternary Scloud+ mode, `00/11 = 0`, `01 = +1`, `10 = -1`.
  - `1`: binary mode, `s[0] = 1` selects `+A`.
  - `2`: 2-bit signed mode, `00 = 0`, `01 = +1`, `10 = -2`, `11 = -1`.
- `cfg_row_blocks`, `cfg_inner_blocks`, `cfg_col_blocks`: runtime matrix block-grid dimensions for `scloudplus_matmul_serial`.

## Integration Notes

The RTL uses packed Verilog-2001 buses rather than unpacked array ports. Element `(row, col)` of a packed `b x b` block is stored at bit slice `(row*B+col)*WIDTH +: WIDTH`.

For the Scloud+ paper default, synthesize with `B=8` and `Q_WIDTH=12`, then set `cfg_b_active=8`, `cfg_q_active=12`, and `cfg_coeff_mode=0`. For a larger reusable instance, increase `B` or `Q_WIDTH` at synthesis time and run smaller tasks by lowering the active configuration.

`ACC_WIDTH` defaults to `Q_WIDTH + 4`, which covers the default `B=8` dot product and gives one extra bit of margin for the `SIGNED2` coefficient mode. For larger synthesis-time `B`, keep:

```text
ACC_WIDTH >= Q_WIDTH + ceil(log2(B)) + 1
```

The current `scloudplus_bmm_block` is a high-parallelism functional prototype: it instantiates `B*B` PEs and each PE has a generated dot-product accumulation chain. For high-frequency targets, consider a tree/pipelined PE; for low-area targets, reuse fewer PEs serially.

The request interface intentionally accepts a request one cycle after `blk_req_valid` first rises because the valid register is asserted inside `ST_REQ`. Testbenches should therefore wait for `blk_req_valid && blk_req_ready`, then return one cycle of `blk_in_valid` data.
