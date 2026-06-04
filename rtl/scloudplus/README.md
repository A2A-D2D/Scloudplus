# Scloud+ Block Matrix Multiplier

This directory contains a Verilog-2001 reproduction of the matrix-multiplication core described in Section 3.2 of `fast-scloud+.pdf`. The compute datapath is explicitly expanded for the Scloud+ paper block size `b=8`, and smaller active task shapes are supported by runtime lane masks.

## Paper Mapping

The paper computes matrix products such as `A * S`, `S' * A`, `S' * B`, and `C1' * S` with square `b x b` blocks. Because `S` and `S'` are ternary matrices, each processing element avoids a general multiplier:

- `s = 00` or `11`: select `0`
- `s = 01`: select `+A`
- `s = 10`: select `-A mod 2^q`

The selected terms are summed and the low `q` bits are kept, giving reduction modulo `2^q`. The right-multiplication case `S' * A` can be scheduled as `(S' * A)^T = A^T * S'^T`, so the same block multiplier datapath can be reused by transposing block addresses/data externally.

## Files

- `scloudplus_bmm_pe.v`: one fixed 8-lane PE for a ternary dot product.
- `scloudplus_bmm_block.v`: fixed 8x8 block multiply with 64 explicit PEs.
- `scloudplus_block_add.v`: fixed 8x8 element-wise block accumulation modulo `2^q`.
- `scloudplus_matmul_serial.v`: block scheduler using one block multiplier over `(row, inner, col)` block indices.

## Runtime Configuration

The main configurable ports are:

- `cfg_b_active`: active block edge length from 1 to 8.
- `cfg_q_active`: active modulus width, up to the synthesis parameter `Q_WIDTH`; results are reduced modulo `2^cfg_q_active`.
- `cfg_coeff_mode`: coefficient interpretation for the right matrix.
  - `0`: ternary Scloud+ mode, `00/11 = 0`, `01 = +1`, `10 = -1`.
  - `1`: binary mode, `s[0] = 1` selects `+A`.
  - `2`: 2-bit signed mode, `00 = 0`, `01 = +1`, `10 = -2`, `11 = -1`.
- `cfg_row_blocks`, `cfg_inner_blocks`, `cfg_col_blocks`: runtime matrix block-grid dimensions for `scloudplus_matmul_serial`.

## Integration Notes

The RTL uses packed Verilog-2001 buses rather than unpacked array ports. Element `(row, col)` of a packed `b x b` block is stored at bit slice `(row*B+col)*WIDTH +: WIDTH`.

For the Scloud+ paper default, synthesize with `B=8` and `Q_WIDTH=12`, then set `cfg_b_active=8`, `cfg_q_active=12`, and `cfg_coeff_mode=0`. The RTL intentionally avoids Verilog `generate` blocks and Verilog `function` definitions in the synthesizable datapath; keep `B=8` when instantiating this version.
