# Scloud+ 分块矩阵乘法器

本目录包含 `fast-scloud+.pdf` 第 3.2 节所述矩阵乘法核心的 Verilog-2001 复现。计算数据通路采用 Verilog `generate` 块实现规整的 PE 和 Lane 复制，可综合 RTL 中避免使用 Verilog `function`/`task` 定义。

适用范围：仅 Scloud+ MatM 子模块。不含完整 Scloud+ PKE/KEM 流程、采样或密文打包。MsgEnc/MsgDec/BDD 见 [`../msgfunc/`](../msgfunc/)。

> **参考文献**  
> Anyu Wang, Zhongxiang Zheng, Chunhuan Zhao, Guang Zeng, Ye Yuan, Zhiyuan Qiu, Changchun Mu, Xiaoyun Wang.  
> *Scloud+: a Lightweight LWE-based KEM without Ring/Module Structure.*  
> IACR Cryptology ePrint Archive, Report 2024/1306, 2024.  
> [https://eprint.iacr.org/2024/1306](https://eprint.iacr.org/2024/1306)

## 论文映射

论文中计算 `A * S`、`S' * A`、`S' * B`、`C1' * S` 等矩阵乘积，使用方阵 `b x b` 分块。由于 `S` 和 `S'` 为三元矩阵，每个处理单元（PE）无需通用乘法器：

- `s = 00` 或 `11`：选择 `0`
- `s = 01`：选择 `+A`
- `s = 10`：选择 `-A mod 2^q`

累加选中项并保留低 `q` 位，即模 `2^q` 约化。右乘情形 `S' * A` 可调度为 `(S' * A)^T = A^T * S'^T`，因此可以通过外部转置分块地址/数据复用同一分块乘法器数据通路。

## 文件列表

- `scloudplus_bmm_pe.v`：参数化 PE，计算三元点积。
- `scloudplus_bmm_block.v`：参数化 `b x b` 分块乘法器，生成 `b^2` 个 PE。
- `scloudplus_block_add.v`：生成的逐元素分块累加器，模 `2^q`。
- `scloudplus_matmul_serial.v`：分块调度器，使用一个分块乘法器遍历 `(row, inner, col)` 分块索引。输入的 `a_block` 和 `s_block` 在 `ST_WAIT` 状态 `blk_in_valid && blk_in_ready` 握手成功时锁存，上游可在 `blk_in_valid` 有效一个周期后更改分块总线。

## 验证向量

MatM 回归测试将每个调度矩阵乘积与两套独立黄金向量源交叉验证：

- Python 向量位于 [`tb/vectors/scloudplus`](../../tb/vectors/scloudplus) 和 [`tb/vectors/scloudplus128`](../../tb/vectors/scloudplus128)。
- C 参考向量位于 [`tb/vectors/scloudplus_c`](../../tb/vectors/scloudplus_c) 和 [`tb/vectors/scloudplus128_c`](../../tb/vectors/scloudplus128_c)，由 [`tb/scripts/scloudplus_matm_vector_gen.c`](../../tb/scripts/scloudplus_matm_vector_gen.c) 生成。

C 参考覆盖与 RTL 调度器相同的 Scloud+ 矩阵乘法角色：

- `keygen_as`：`A * S`
- `enc_c1_transpose`：`A' * S'` 的转置调度
- `dec_c1s`：`C1 * S`
- `enc_sb_transpose`：openHiTLS `SCLOUDPLUS_SB_E` 乘积 `S * B` 的转置调度

`scloudplus128` 向量集使用论文风格的分块设置 `B=8`、`Q_WIDTH=12`，内维 `600` 系数，分为 `75` 个分块列，覆盖 Scloud+ 高维 MatM 调度。

[`tb/matmul/tb_scloudplus_official_params_vectors.v`](../../tb/matmul/tb_scloudplus_official_params_vectors.v) 额外覆盖 ePrint 2024/1306 Table 2 全部三组参数：

| 集合 | `(m, n)` | `(mbar, nbar)` | 覆盖 MatM 角色 |
| --- | --- | --- | --- |
| `Scloud+128` | `(600, 600)` | `(8, 8)` | `A*S`、`S*A` 转置调度、`C1*S`、`S*B` 转置调度 |
| `Scloud+192` | `(928, 896)` | `(8, 8)` | `A*S`、`S*A` 转置调度、`C1*S`、`S*B` 转置调度 |
| `Scloud+256` | `(1136, 1120)` | `(12, 11)` | `A*S`、`S*A` 转置调度、`C1*S`、`S*B` 转置调度 |

日常仿真速度优化：官方参数回归使用完整官方内维（`600`、`896`、`928`、`1120`、`1136`），但大矩阵乘积仅取 16 行输出切片；解密乘积使用完整 `(mbar, nbar)` 形状。这仍能验证长分块调度范围，以及 `Scloud+256` 中 `(12, 11)` 导致的非 8 对齐填充边界分块。

使用 `--regen-c-vectors` 时，运行脚本还会编译 [`tb/scripts/scloudplus_openhitls_matm_compare.c`](../../tb/scripts/scloudplus_openhitls_matm_compare.c)。该比较器镜像 openHiTLS/PQCP 中 `SCLOUDPLUS_AS_E`、`SCLOUDPLUS_SA_E`、`SCLOUDPLUS_CS`、`SCLOUDPLUS_SB_E` 的矩阵乘法循环，校验生成的 `.mem` 预期结果。通过时在 RTL 仿真前打印 `OPENHITLS_C_COMPARE_PASS`。

运行完整 MatM 回归测试：

```text
python tb/scripts/run_scloudplus_matm_sim.py --case all
```

仅运行官方参数覆盖：

```text
python tb/scripts/run_scloudplus_matm_sim.py --case official --regen-c-vectors --no-wave
```

仿真前重新生成 C 参考向量：

```text
python tb/scripts/run_scloudplus_matm_sim.py --case all --regen-c-vectors
```

## 运行时配置

主要可配置端口：

- `cfg_b_active`：活跃分块边长，最大为综合参数 `B`。
- `cfg_q_active`：活跃模数位宽，最大为综合参数 `Q_WIDTH`；结果模 `2^cfg_q_active` 约化。
- `cfg_coeff_mode`：右矩阵系数解释。
  - `0`：三元 Scloud+ 模式，`00/11 = 0`，`01 = +1`，`10 = -1`。
  - `1`：二元模式，`s[0] = 1` 选择 `+A`。
  - `2`：2-bit 有符号模式，`00 = 0`，`01 = +1`，`10 = -2`，`11 = -1`。
- `cfg_row_blocks`、`cfg_inner_blocks`、`cfg_col_blocks`：`scloudplus_matmul_serial` 的运行时矩阵分块网格维度。

`scloudplus_matmul_serial` 在 `start && start_ready` 握手成功时锁存所有 `cfg_*` 输入。`busy=1` 期间配置输入的变化不影响正在进行的矩阵乘法。

## 集成说明

RTL 使用 packed Verilog-2001 总线，不使用 unpacked 数组端口。packed `b x b` 分块中元素 `(row, col)` 存储在位段 `(row*B+col)*WIDTH +: WIDTH`。

对于 Scloud+ 论文默认参数，综合时设置 `B=8`、`Q_WIDTH=12`，然后设置 `cfg_b_active=8`、`cfg_q_active=12`、`cfg_coeff_mode=0`。若需更大可复用实例，综合时增大 `B` 或 `Q_WIDTH`，运行时降低活跃配置即可运行更小任务。

`ACC_WIDTH` 默认为 `Q_WIDTH`。数据通路通过保留低 `Q_WIDTH` 位实现模 `2^q` 约化，高位累加溢出不影响数学结果，只要：

```text
ACC_WIDTH >= Q_WIDTH
```

仅当需要观测未约化点积和（调试/统计），或数据通路后续改为非 2 的幂模数时，才需要更宽的 `ACC_WIDTH`。

`cfg_b_active=0` 禁用所有活跃行列，PE 输出全零。`cfg_q_active=0` 构建全零掩码，模输出全零。正常 Scloud+ 运行应使用非零活跃值。

当前 `scloudplus_bmm_block` 为高并行度功能原型：实例化 `B*B` 个 PE，每个 PE 具有生成的点积累加链。面向高频目标，建议采用树形/流水线 PE；面向低面积目标，建议串行复用更少 PE。
