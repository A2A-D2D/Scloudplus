# Scloud+ 硬件实现

Scloud+ 后量子密码方案的 Verilog-2001 RTL 实现，包含 Barnes-Wall 消息函数（MsgEnc/MsgDec）和分块矩阵乘法器（MatM）子模块。

> **参考文献**  
> Anyu Wang, Zhongxiang Zheng, Chunhuan Zhao, Guang Zeng, Ye Yuan, Zhiyuan Qiu, Changchun Mu, Xiaoyun Wang.  
> *Scloud+: a Lightweight LWE-based KEM without Ring/Module Structure.*  
> IACR Cryptology ePrint Archive, Report 2024/1306, 2024.  
> [https://eprint.iacr.org/2024/1306](https://eprint.iacr.org/2024/1306)

## 目录结构

```
scloud+
├── rtl/
│   ├── msgfunc/                  # Barnes-Wall 消息函数
│   │   ├── bw8/                  # BW8  组合逻辑（12-bit 消息,  8 个 q 坐标）
│   │   ├── bw16/                 # BW16 组合逻辑（20-bit 消息, 16 个 q 坐标）
│   │   ├── bw32_combo/           # BW32 组合逻辑（32-bit 消息, 32 个 q 坐标）
│   │   ├── bw32_seq/             # BW32 时序逻辑（FSM 流水线）
│   │   ├── bdd/                  # 共享 BDD 译码器（递归树 + seq4/8/16/32）
│   │   └── param/                # 参数化版本（编译期可配 BW8/BW16/BW32）
│   └── scloudplus/               # 分块矩阵乘法器（MatM）
├── tb/
│   ├── bw8/                      # BW8 测试平台
│   ├── bw16/                     # BW16 测试平台
│   ├── bw32_combo/               # BW32 组合逻辑测试平台
│   ├── bw32_seq/                 # BW32 时序逻辑测试平台（单元 + 压力）
│   ├── bdd/                      # BDD 译码器测试平台
│   ├── param/                    # 参数化 MsgFunc 测试平台
│   ├── matmul/                   # 矩阵乘法器测试平台
│   ├── scripts/                  # Python/C 构建与向量生成脚本
│   └── vectors/                  # 黄金测试向量（.mem）
├── sim_build/                    # 编译产物（.vvp）
├── doc/                          # 设计文档
│   ├── fast-scloud+.pdf
│   └── BDD_OPTIMIZATION_PROPOSAL.md
└── README.md
```

## 模块概览

### Barnes-Wall 消息函数（`rtl/msgfunc/`）

通过 Barnes-Wall 格坐标编码/解码消息，含噪声加法。

| 变体 | Q 坐标数 | 消息位宽 | 实现风格 | 目录 |
|---------|----------|----------|-------|-----------|
| BW8 | 8 | 12 | 组合逻辑 | [`rtl/msgfunc/bw8/`](rtl/msgfunc/bw8/) |
| BW16 | 16 | 20 | 组合逻辑 | [`rtl/msgfunc/bw16/`](rtl/msgfunc/bw16/) |
| BW32 | 32 | 32 | 组合逻辑 | [`rtl/msgfunc/bw32_combo/`](rtl/msgfunc/bw32_combo/) |
| BW32 | 32 | 32 | 时序逻辑（FSM） | [`rtl/msgfunc/bw32_seq/`](rtl/msgfunc/bw32_seq/) |
| BW8/16/32 | — | — | 参数化 | [`rtl/msgfunc/param/`](rtl/msgfunc/param/) |

所有变体共享 [`rtl/msgfunc/bdd/`](rtl/msgfunc/bdd/) 中的 BDD 译码器。

### 分块矩阵乘法器（`rtl/scloudplus/`）

可配置的 `b × b` 分块矩阵乘法器，支持三元 Scloud+ 矩阵运算。运行时可通过 `cfg_*` 端口配置块大小、模数位宽和系数模式。

详见 [`rtl/scloudplus/README.md`](rtl/scloudplus/README.md)。

## 快速开始

### 运行 BW32 组合逻辑仿真

```bash
cd sim_build
vvp tb_scloud_msgfunc_bw32_demo.vvp
```

### 运行 BW32 时序逻辑仿真

```bash
cd sim_build
vvp tb_scloud_msgfunc_bw32_seq.vvp
```

### 运行完整 MatM 回归测试

```bash
python tb/scripts/run_scloudplus_matm_sim.py --case all
```

## 关键参数

所有实现均使用固定参数 `q=1024`, `TAU=2`, `Q_WIDTH=10`。

| 参数 | BW8 | BW16 | BW32 |
|-----------|-----|------|------|
| COMPLEX_N | 4 | 8 | 16 |
| Q 坐标数 | 8 | 16 | 32 |
| 消息位宽 | 12 bits | 20 bits | 32 bits |
| 标签位宽 | 192 bits | 224 bits | 224 bits |

## 实现说明

- **组合逻辑（"demo"）** 变体采用手动展开的蝴蝶级和显式消息↔标签位分配，编码过程清晰可见。功能完整，但组合深度较高。
- **时序逻辑** 变体每时钟周期执行一级蝴蝶变换，显著降低面积并改善时序收敛。
- **BDD 递归树** 在组合译码器中实例数呈指数增长；时序 BDD 引擎通过层次化 FSM 复用（BDD4 → BDD8 → BDD16 → BDD32）避免了此问题。
- 详见 [`doc/BDD_OPTIMIZATION_PROPOSAL.md`](doc/BDD_OPTIMIZATION_PROPOSAL.md)。

## 许可证

本项目基于 Scloud+ 论文 [ePrint 2024/1306](https://eprint.iacr.org/2024/1306) 中描述的算法进行硬件实现。
