# Scloud+ 硬件实现

本仓库提供 Scloud+ 后量子密钥封装机制（KEM）的 Verilog-2001 RTL 实现，当前重点包括 Barnes-Wall 消息函数（MsgEnc / MsgDec）和分块矩阵乘法器（MatM）两个核心子模块。实现以 `rtl/cmodel/` 中的 openHiTLS C 参考模型为对齐基准，便于从 C 模型、Python 参考模型到 RTL 仿真的逐级验证。

> **参考论文**  
> Anyu Wang, Zhongxiang Zheng, Chunhuan Zhao, Guang Zeng, Ye Yuan, Zhiyuan Qiu, Changchun Mu, Xiaoyun Wang.  
> *Scloud+: a Lightweight LWE-based KEM without Ring/Module Structure.*  
> IACR Cryptology ePrint Archive, Report 2024/1306, 2024.  
> <https://eprint.iacr.org/2024/1306>

## 项目特点

- 使用 **Verilog-2001** 编写 RTL，便于兼容传统 ASIC / FPGA 仿真综合流程。
- 提供与 openHiTLS C 模型对齐的参数化 Barnes-Wall MsgEnc / MsgDec 实现。
- 支持 Scloud+128 / Scloud+192 / Scloud+256 三组安全等级参数。
- 提供 Python bit-exact 软件参考模型、测试向量生成脚本和统一仿真入口。
- 保留早期 BW8 / BW16 / BW32 legacy demo，用于回归和结构参考，但这些路径不再作为主实现。

## 目录结构

```text
scloud+
├── rtl/
│   ├── cmodel/                       # openHiTLS C 参考模型
│   │   ├── scloudplus.c              #   顶层 KEM 流程：keygen / encaps / decaps
│   │   ├── scloudplus_util.c         #   MsgEncode/Decode、BDD、采样、打包等工具函数
│   │   └── scloudplus_local.h        #   参数结构体、常量、函数声明
│   ├── msgfunc/                      # Barnes-Wall 消息函数
│   │   ├── param/                    #   参数化实现，C-model aligned，当前主路径
│   │   │   ├── scloud_msgfunc_param.v    # MsgEnc / MsgDec 数据通路，tau=3/4，Q=12
│   │   │   └── scloud_msgfunc_cfg_reg.v  # 寄存器可配置 wrapper
│   │   ├── bdd/                      #   共享 BDD 解码器，递归树 + seq4/8/16/32
│   │   ├── bw32_combo/               #   BW32 组合逻辑 demo，tau=2，Q=10，legacy
│   │   ├── bw32_seq/                 #   BW32 顺序 FSM demo，legacy
│   │   ├── bw8/                      #   BW8 组合逻辑 demo，legacy
│   │   └── bw16/                     #   BW16 组合逻辑 demo，legacy
│   └── scloudplus/                   # 分块矩阵乘法器 MatM
├── tb/
│   ├── param/                        # 参数化 MsgFunc testbench，C-model aligned
│   ├── bdd/                          # BDD 解码器 testbench
│   ├── bw8/                          # BW8 legacy testbench
│   ├── bw16/                         # BW16 legacy testbench
│   ├── bw32_combo/                   # BW32 组合逻辑 legacy testbench
│   ├── bw32_seq/                     # BW32 顺序 FSM legacy testbench
│   ├── matmul/                       # 矩阵乘法器 testbench
│   ├── scripts/                      # Python 参考模型与验证脚本
│   │   ├── scloud_msgfunc_sw_ref.py      # bit-exact C-model 软件参考模型
│   │   ├── scloud_msgfunc_cmp_result.py  # 综合对比向量生成器
│   │   ├── scloud_msgfunc_vector_gen.py  # .mem 测试向量生成器
│   │   ├── scloud_msgfunc_verify.py      # 详细流水级 dump 工具
│   │   └── run_all_sim.py                # 统一仿真入口
│   └── vectors/                      # golden 测试向量
│       ├── msgfunc_sw/               #   软件生成向量
│       └── verify_result/            #   对比结果文件
├── sim_build/                        # 仿真编译产物，例如 .vvp
└── README.md
```

## 模块概览

### 1. Barnes-Wall 消息函数（`rtl/msgfunc/`）

Barnes-Wall 消息函数用于将消息映射到 Barnes-Wall 格点坐标，并在解码侧通过 BDD（bounded-distance decoding）完成纠错恢复。当前推荐使用 `rtl/msgfunc/param/` 下的参数化实现。

| 版本 | tau | Q_WIDTH | MSG_WIDTH | Q 坐标数 | 实现形式 | 目录 | 状态 |
|------|-----|---------|-----------|----------|----------|------|------|
| **param，C 对齐** | 3 / 4 | 12 | 64 / 96 | 32 | 参数化 | [`rtl/msgfunc/param/`](rtl/msgfunc/param/) | **主实现** |
| BW8 | 2 | 10 | 12 | 8 | 组合逻辑 | [`rtl/msgfunc/bw8/`](rtl/msgfunc/bw8/) | legacy |
| BW16 | 2 | 10 | 20 | 16 | 组合逻辑 | [`rtl/msgfunc/bw16/`](rtl/msgfunc/bw16/) | legacy |
| BW32 combo | 2 | 10 | 32 | 32 | 组合逻辑 | [`rtl/msgfunc/bw32_combo/`](rtl/msgfunc/bw32_combo/) | legacy |
| BW32 seq | 2 | 10 | 32 | 32 | 顺序 FSM | [`rtl/msgfunc/bw32_seq/`](rtl/msgfunc/bw32_seq/) | legacy |

当前主实现相对早期 demo 的关键变化如下：

- `tau = 3` 对应 `ss = 16 / 32`，`tau = 4` 对应 `ss = 24`。
- `Q_WIDTH = 12`，即 `Q = 4096`，与 C 模型中的 `SCLOUDPLUS_MOD_Q = 0xFFF` 对齐。
- `LABEL_WIDTH = TAU + LOG_COMPLEX_N`，其中 `tau=3` 时为 7，`tau=4` 时为 8。
- `MSG_WIDTH = (COMPLEX_N * (2 * TAU)) - ((COMPLEX_N * LOG_COMPLEX_N) / 2)`，其中 `tau=3` 时为 64，`tau=4` 时为 96。
- BDD 距离度量使用 **欧氏距离平方（L2 distance）**，与 C 模型 `EuclideanDistanceNoSqrt` 对齐。
- `msg_to_label` / `label_to_msg` 采用与 C 模型 `LabelingComputeV` / `DelabelingComputeU` 一致的硬编码 bit-packing。

> 注意：`bw8/`、`bw16/`、`bw32_combo/`、`bw32_seq/` 是早期 legacy demo，使用 `tau=2`、`Q_WIDTH=10` 和简化的 popcount 标签映射，不与当前 C 参考模型完全一致，仅保留用于结构参考和回归测试。

### 2. C 参考模型（`rtl/cmodel/`）

`rtl/cmodel/` 中的 openHiTLS C 代码是当前 RTL 对齐的权威参考。核心文件如下：

| 文件 | 作用 |
|------|------|
| [`scloudplus_util.c`](rtl/cmodel/scloudplus_util.c) | `LabelingComputeV`、`LabelingComputeW`、`DelabelingRecoverW`、`DelabelingReduceW`、`DelabelingComputeU`、`BDDForBWn`、采样、打包等 |
| [`scloudplus.c`](rtl/cmodel/scloudplus.c) | 顶层 KEM 流程，包括 `PKEKeygen`、`PKEEncrypt`、`PKEDecrypt`、`Encaps`、`Decaps` |
| [`scloudplus_local.h`](rtl/cmodel/scloudplus_local.h) | 参数结构体、常量定义，例如 `MOD_Q=0xFFF`、`BW_COMPLEX_LEN=16` |

### 3. Python 软件参考模型（`tb/scripts/scloud_msgfunc_sw_ref.py`）

Python 参考模型用于生成 RTL 测试向量和 pipeline 级对比结果，目标是与 C 模型 bit-exact 对齐。示例用法如下：

```python
from scloud_msgfunc_sw_ref import *

# 单个 BW block：tau=3，8 字节消息 -> 32 个 Q-domain 坐标
q_codeword = msgfunc_encode_block(msg_bytes, tau=3, logq=12)
rounded_q, recovered_msg = msgfunc_decode_block(noisy_q, tau=3, logq=12)

# 多 block：完整消息
q = msgfunc_encode(msg, ss_level=16)   # 16 字节消息 -> 64 个 Q 坐标
_, msg_out = msgfunc_decode(q, ss_level=16)
```

## 安全等级参数

当前参数与 C 模型 `PRESET_PARAS` 对齐：

| 安全等级 | ss | tau | mu | muConut | logq | 单 block 消息字节 | 总消息字节 | 总 Q 坐标数 |
|----------|----|-----|----|---------|------|------------------|------------|-------------|
| Scloud+128 | 16 | 3 | 64 | 2 | 12 | 8 | 16 | 64 |
| Scloud+192 | 24 | 4 | 96 | 2 | 12 | 12 | 24 | 64 |
| Scloud+256 | 32 | 3 | 64 | 4 | 12 | 8 | 32 | 128 |

### tau=3、COMPLEX_N=16 时的坐标 bit 分配

| WH 类别 | 坐标 | re_bits | im_bits | 每坐标 bit 数 | 数量 | 小计 |
|---------|------|---------|---------|---------------|------|------|
| WH=0 | [0] | 3 | 3 | 6 | 1 | 6 |
| WH=1 | [1,2,4,8] | 3 | 2 | 5 | 4 | 20 |
| WH=2 | [3,5,6,9,10,12] | 2 | 2 | 4 | 6 | 24 |
| WH=3 | [7,11,13,14] | 2 | 1 | 3 | 4 | 12 |
| WH=4 | [15] | 1 | 1 | 2 | 1 | 2 |
| **总计** | 16 | | | | | **64** (= mu) |

## 数据通路与流水阶段

```text
ENCODE:
  msg (64/96 bits)
    -> [msg_to_label]   label_flat，32 lanes × LABEL_WIDTH
    -> [phi_encode]     enc_label_flat，4-stage Barnes-Wall butterfly
    -> [label_to_q]     enc_q_flat，32 coords × Q_WIDTH=12

DECODE:
  noisy_q_flat，32 coords × Q_WIDTH=12
    -> [BDD recursive]  rounded_q_flat，欧氏 L2 距离；tie 规则为 dist_a < dist_b
    -> [q_to_label]     quant_label_flat
    -> [phi_decode]     raw_label_flat，inverse butterfly + DelabelingReduceW
    -> [label_to_msg]   recovered msg，64/96 bits
```

## 验证方法

### Python 软件自测

```bash
python tb/scripts/scloud_msgfunc_sw_ref.py
```

该脚本会对三个安全等级分别执行随机 roundtrip 测试，并覆盖噪声恢复能力和边界条件。

### 生成综合对比向量

```bash
python tb/scripts/scloud_msgfunc_cmp_result.py > cmp_result.txt
```

该脚本会生成完整 pipeline dump，覆盖 corner case、walking-1/0、WH-class isolation、label boundary、random、noise injection、tau=4 等测试场景。输出结果可用于 RTL 波形逐坐标交叉检查。

### 当前已通过结果

| 测试项 | 结果 |
|--------|------|
| Walking-1，64 bits，tau=3 | 64/64 PASS |
| Walking-0，64 bits，tau=3 | 64/64 PASS |
| Corner-case messages，22 patterns | 22/22 PASS |
| WH-class isolation | 6/6 PASS |
| BDD rounding boundary，16 values | 16/16 PASS |
| Phi symmetry，encode = decode^-1 | 16/16 PASS |
| Noise sweep：zero / D/8 / D/4 / D/2 | 100% correct |
| Multi-block ss=16/24/32，128 msgs each | 384/384 PASS |

## 快速开始

### 运行 RTL 仿真：参数化 C-aligned 主路径

```bash
cd sim_build
iverilog -g2001 -Wall -o tb_scloud_msgfunc_param.vvp \
    ../rtl/msgfunc/param/*.v ../rtl/msgfunc/bdd/*.v \
    ../tb/param/tb_scloud_msgfunc_param.v
vvp tb_scloud_msgfunc_param.vvp
```

### 生成软件测试向量

```bash
# 生成用于 RTL testbench 的 .mem 文件
python tb/scripts/scloud_msgfunc_vector_gen.py --ss 16 --num 256

# 生成详细 pipeline 对比结果
python tb/scripts/scloud_msgfunc_cmp_result.py > cmp_result.txt
```

### 运行统一仿真脚本

```bash
# 仅运行软件参考模型验证
python tb/scripts/run_all_sim.py --cases param --sw-only

# 运行 RTL regression
python tb/scripts/run_all_sim.py --cases param,bdd,matmul
```

## 实现说明

- `rtl/msgfunc/param/` 是当前主实现路径，已按 openHiTLS C 模型进行参数、bit-packing 和 BDD 规则对齐。
- `msg_to_label` / `label_to_msg` 对 `tau=3` 和 `tau=4` 使用硬编码 bit-packing，对其他参数组合保留 generic popcount fallback。
- BDD 递归树使用欧氏距离平方，与 C 模型 `EuclideanDistanceNoSqrt` 一致；tie-breaking 使用严格小于号，即 `dist_a < dist_b`，对应 C 代码中的 `if (d1 < d2)`。
- legacy demo 路径使用简化参数和 L1 / Manhattan 距离，不建议作为 C-model aligned 实现使用。
- 顺序 BDD 通过分层 FSM（BDD4 -> BDD8 -> BDD16 -> BDD32）降低递归树带来的组合逻辑膨胀。
- 模块级说明可继续参考 [`rtl/msgfunc/param/README.md`](rtl/msgfunc/param/README.md) 和 [`rtl/scloudplus/README.md`](rtl/scloudplus/README.md)。

## License / 说明

本项目实现的是 Scloud+ 论文中相关算法的硬件结构，主要用于学习、研究和硬件原型验证。算法细节请参考 Scloud+ 原论文：<https://eprint.iacr.org/2024/1306>。
