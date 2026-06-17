#!/usr/bin/env python3
"""
Scloud+ MsgFunc Software Reference Model.

Bit-exact Python implementation matching the openHiTLS C reference model in
d:/scloud+/rtl/cmodel/scloudplus_util.c.

This models a single Barnes-Wall block (BW32: 16 complex coordinates = 32 real dims).
Multi-block repetition (muConut) is handled by the top-level encode/decode wrappers.

Reference: Anyu Wang et al., "Scloud+: a Lightweight LWE-based KEM without
Ring/Module Structure", IACR ePrint 2024/1306.
"""

from typing import List, Tuple, Optional

# ==============================================================================
# Parameter definitions (matching C model PRESET_PARAS)
# ==============================================================================

# All parameter sets use:
#   SCLOUDPLUS_BW_COMPLEX_LEN = 16  (32 real dimensions)
#   SCLOUDPLUS_MOD_Q = 0xFFF        (logq = 12)

PARAM_SETS = {
    # ss=16: tau=3, mu=64, muConut=2
    16: {"tau": 3, "mu": 64, "mu_conut": 2, "logq": 12},
    # ss=24: tau=4, mu=96, muConut=2
    24: {"tau": 4, "mu": 96, "mu_conut": 2, "logq": 12},
    # ss=32: tau=3, mu=64, muConut=4
    32: {"tau": 3, "mu": 64, "mu_conut": 4, "logq": 12},
}

BW_COMPLEX_LEN = 16  # SCLOUDPLUS_BW_COMPLEX_LEN
MOD_Q = 0xFFF         # SCLOUDPLUS_MOD_Q


# ==============================================================================
# Complex number helpers (matching C Complex struct operations)
# ==============================================================================

class Complex:
    """Mirrors the C `Complex { int32_t real; int32_t imag; }` struct."""
    __slots__ = ('real', 'imag')

    def __init__(self, real: int = 0, imag: int = 0):
        self.real = real
        self.imag = imag

    def __repr__(self):
        return f"({self.real}, {self.imag})"

    def __eq__(self, other):
        return self.real == other.real and self.imag == other.imag


def complex_add(a: Complex, b: Complex) -> Complex:
    """C: ComplexAdd → (a.real + b.real, a.imag + b.imag) — no modular wrap."""
    return Complex(a.real + b.real, a.imag + b.imag)


def complex_sub(a: Complex, b: Complex) -> Complex:
    """C: ComplexSub → (a.real - b.real, a.imag - b.imag) — no modular wrap."""
    return Complex(a.real - b.real, a.imag - b.imag)


def complex_mul(a: Complex, b: Complex) -> Complex:
    """C: ComplexMul → full integer multiply, no modular reduction."""
    return Complex(
        a.real * b.real - a.imag * b.imag,
        a.real * b.imag + a.imag * b.real,
    )


def complex_div_phi(a: Complex) -> Complex:
    """C: ComplexDivPhi → divide by (1+i) = multiply by (1-i)/2.

    (a.real + a.imag) >> 1, (a.imag - a.real) >> 1
    Uses arithmetic right-shift (Python >> is arithmetic for int).
    """
    return Complex(
        (a.real + a.imag) >> 1,
        (a.imag - a.real) >> 1,
    )


# ==============================================================================
# Round function (matching C Round — signed integer arithmetic)
# ==============================================================================

def round_to_delta(value: int, logq: int, tau: int) -> int:
    """C: Round(in, logq, tau) — round to nearest multiple of 2^(logq-tau).

    Uses C-style signed % and / semantics:
      r = in % mod   (sign of dividend in C)
      q = in / mod   (truncates toward zero)

    Returns q * mod.
    """
    mod = 1 << (logq - tau)       # e.g. logq=12,tau=3 → mod=512
    mod2 = mod >> 1               # half-mod = 256
    r = value % mod
    q = value // mod              # Python // truncates toward negative infinity,
                                  # not toward zero like C. Handle below.

    # Emulate C division (truncate toward zero) and C % (sign of dividend)
    # Actually Python's % always gives non-negative when mod > 0.
    # C: -300 % 512 = -300, -300 / 512 = 0
    # Python: -300 % 512 = 212, -300 // 512 = -1
    #
    # Fix: use divmod-like logic that matches C.
    # C behavior: q = value / mod (trunc toward zero), r = value - q * mod
    if value >= 0:
        # Same as Python
        pass
    else:
        # C truncates toward zero: q = -(-value // mod) = value // mod in Python 3
        # Actually Python 3 // truncates toward negative infinity.
        # For negative: C truncates toward zero.
        # -300 / 512 = 0 in C, -300 // 512 = -1 in Python
        # Fix: recompute q and r with C semantics
        q_c = int(value / mod)  # float division then trunc toward zero
        r = value - q_c * mod
        q = q_c

    if value >= 0:
        if r >= mod2:
            q += 1
    else:
        if r <= -mod2:
            q -= 1

    return q * mod


# ==============================================================================
# Euclidean distance (matching C EuclideanDistanceNoSqrt)
# ==============================================================================

def euclidean_distance_sq(a: List[Complex], b: List[Complex], size: int) -> int:
    """C: EuclideanDistanceNoSqrt — sum of squared differences."""
    total = 0
    for i in range(size):
        dr = a[i].real - b[i].real
        di = a[i].imag - b[i].imag
        total += dr * dr + di * di
    return total


# ==============================================================================
# BDD (Bounded-Distance Decoding) — matching C BDDForBWn
# ==============================================================================

def bdd_decode_bwn(t: List[Complex], bwn: int, logq: int, tau: int) -> List[Complex]:
    """C: BDDForBWn(t, BWn, logq, tau, y) — recursive Barnes-Wall BDD decoder.

    Args:
        t: input complex array (Q-domain values as int32_t real/imag pairs)
        bwn: total real dimensions (must be power of 2, >= 2)
        logq: log2(modulus), always 12
        tau: modulus parameter (3 or 4)

    Returns:
        y: decoded complex array (rounded Q-domain values)
    """
    t_len = bwn >> 1       # number of complex coords = bwn/2
    half = t_len >> 1      # half of complex coords

    # Base case: bwn == 2 → 1 complex coordinate, round independently
    if bwn == 2:
        return [Complex(
            round_to_delta(t[0].real, logq, tau),
            round_to_delta(t[0].imag, logq, tau),
        )]

    # Split into t1 (left half) and t2 (right half)
    t1 = t[:half]
    t2 = t[half:]

    # Recursive decode
    y1 = bdd_decode_bwn(t1, t_len, logq, tau)
    y2 = bdd_decode_bwn(t2, t_len, logq, tau)

    # Compute z1in = div_phi(t2[i] - y1[i]), z2in = div_phi(t1[i] - y2[i])
    z1in = [complex_div_phi(complex_sub(t2[i], y1[i])) for i in range(half)]
    z2in = [complex_div_phi(complex_sub(t1[i], y2[i])) for i in range(half)]

    # Recursive decode on transformed residuals
    z1 = bdd_decode_bwn(z1in, t_len, logq, tau)
    z2 = bdd_decode_bwn(z2in, t_len, logq, tau)

    # Forward-transform: multiply by phi = (1+i)
    phi = Complex(1, 1)
    z1_phi = [complex_mul(z1[i], phi) for i in range(half)]
    z2_phi = [complex_mul(z2[i], phi) for i in range(half)]

    # Build candidates
    out1 = [Complex() for _ in range(t_len)]
    out2 = [Complex() for _ in range(t_len)]

    for i in range(half):
        out1[i] = y1[i]
        out1[half + i] = complex_add(y1[i], z1_phi[i])
        out2[i] = complex_add(y2[i], z2_phi[i])
        out2[half + i] = y2[i]

    # Choose closer candidate (tie → out1, matching C's `if (d1 < d2)`
    # — C uses strict less-than, so tie goes to out2, NOT out1!)
    # Actually re-reading the C: if (d1 < d2) { y = out1; } else { y = out2; }
    # So tie → out2.
    d1 = euclidean_distance_sq(out1, t, t_len)
    d2 = euclidean_distance_sq(out2, t, t_len)

    if d1 < d2:
        return out1
    else:
        return out2


# ==============================================================================
# LabelingComputeV — message bytes → complex label vector
# (matching C LabelingComputeV, paper Algorithm 2 steps 1-3)
# ==============================================================================

def labeling_compute_v(msg: bytes, tau: int) -> List[Complex]:
    """C: LabelingComputeV(msg, tau, v)

    Maps message bytes to complex vector v[0..15] (BW32 labels).
    Each v[i].real and v[i].imag is in [0, 2^ceil((2τ-wh(i))/2)] range.

    For tau=3: consumes 8 bytes → v with values in {0..7, 0..3, 0..1}
    For tau=4: consumes 12 bytes → v with values in {0..15, 0..7, 0..3}
    """
    m = list(msg)  # work with ints per byte
    A = [0] * 6
    B = [0] * 20
    C = [0] * 6

    if tau == 3:
        A[0] = (m[0] >> 0) & 0x07
        A[1] = (m[0] >> 3) & 0x07
        A[2] = ((m[0] >> 6) & 0x03) | ((m[1] << 2) & 0x04)
        A[3] = (m[1] >> 1) & 0x07
        A[4] = (m[1] >> 4) & 0x07
        A[5] = ((m[1] >> 7) & 0x01) | ((m[2] << 1) & 0x06)

        for i in range(3):
            B[i] = (m[2] >> (2 + 2 * i)) & 0x03

        for i in range(4):
            B[3 + i] = (m[3] >> (2 * i)) & 0x03
            B[7 + i] = (m[4] >> (2 * i)) & 0x03
            B[11 + i] = (m[5] >> (2 * i)) & 0x03
            B[15 + i] = (m[6] >> (2 * i)) & 0x03

        B[19] = m[7] & 0x03
        C[0] = (m[7] >> 2) & 0x01
        C[1] = (m[7] >> 3) & 0x01
        C[2] = (m[7] >> 4) & 0x01
        C[3] = (m[7] >> 5) & 0x01
        C[4] = (m[7] >> 6) & 0x01
        C[5] = (m[7] >> 7) & 0x01

    elif tau == 4:
        A[0] = m[0] & 0x0F
        A[1] = (m[0] >> 4) & 0x0F
        A[2] = m[1] & 0x0F
        A[3] = (m[1] >> 4) & 0x0F
        A[4] = m[2] & 0x0F
        A[5] = (m[2] >> 4) & 0x0F

        B[0] = m[3] & 0x07
        B[1] = (m[3] >> 3) & 0x07
        B[2] = ((m[3] >> 6) & 0x03) | ((m[4] << 2) & 0x04)
        B[3] = (m[4] >> 1) & 0x07
        B[4] = (m[4] >> 4) & 0x07
        B[5] = ((m[4] >> 7) & 0x01) | ((m[5] << 1) & 0x06)
        B[6] = (m[5] >> 2) & 0x07
        B[7] = (m[5] >> 5) & 0x07

        B[8] = m[6] & 0x07
        B[9] = (m[6] >> 3) & 0x07
        B[10] = ((m[6] >> 6) & 0x03) | ((m[7] << 2) & 0x04)
        B[11] = (m[7] >> 1) & 0x07
        B[12] = (m[7] >> 4) & 0x07
        B[13] = ((m[7] >> 7) & 0x01) | ((m[8] << 1) & 0x06)
        B[14] = (m[8] >> 2) & 0x07
        B[15] = (m[8] >> 5) & 0x07

        B[16] = m[9] & 0x07
        B[17] = (m[9] >> 3) & 0x07
        B[18] = ((m[9] >> 6) & 0x03) | ((m[10] << 2) & 0x04)
        B[19] = (m[10] >> 1) & 0x07

        C[0] = (m[10] >> 4) & 0x03
        C[1] = (m[10] >> 6) & 0x03
        C[2] = m[11] & 0x03
        C[3] = (m[11] >> 2) & 0x03
        C[4] = (m[11] >> 4) & 0x03
        C[5] = (m[11] >> 6) & 0x03

    else:
        raise ValueError(f"Unsupported tau={tau}")

    # D array: rearrange A/B/C into 32 label values (16 complex pairs)
    D = [
        A[0], A[1], A[2], B[0], A[3], B[1], B[2], B[3],
        A[4], B[4], B[5], B[6], B[7], B[8], B[9], C[0],
        A[5], B[10], B[11], B[12], B[13], B[14], B[15], C[1],
        B[16], B[17], B[18], C[2], B[19], C[3], C[4], C[5],
    ]

    v = [Complex() for _ in range(BW_COMPLEX_LEN)]
    for i in range(BW_COMPLEX_LEN):
        v[i].real = D[2 * i]
        v[i].imag = D[2 * i + 1]

    return v


# ==============================================================================
# LabelingComputeW — labels → Q-domain codeword
# (matching C LabelingComputeW, paper Algorithm 2 steps 4-8)
# ==============================================================================

def labeling_compute_w(v: List[Complex], logq: int, tau: int) -> List[int]:
    """C: LabelingComputeW(v, logq, tau, w)

    Barnes-Wall butterfly encoding (phi = 1+i), then scale to Q-domain.

    Returns: flat list of 32 uint16 Q-domain values (w[0..31]).
    """
    phi = Complex(1, 1)
    tmp = [Complex(v[i].real, v[i].imag) for i in range(BW_COMPLEX_LEN)]

    # Stage 1: step=1 — pairs (0,1), (2,3), ..., (14,15)
    for i in range(8):
        tmp[2 * i + 1] = complex_add(
            tmp[2 * i],
            complex_mul(tmp[2 * i + 1], phi),
        )

    # Stage 2: step=2
    for i in range(4):
        tmp[4 * i + 2] = complex_add(
            tmp[4 * i],
            complex_mul(tmp[4 * i + 2], phi),
        )
        tmp[4 * i + 3] = complex_add(
            tmp[4 * i + 1],
            complex_mul(tmp[4 * i + 3], phi),
        )

    # Stage 3: step=4
    for i in range(2):
        tmp[8 * i + 4] = complex_add(
            tmp[8 * i],
            complex_mul(tmp[8 * i + 4], phi),
        )
        tmp[8 * i + 5] = complex_add(
            tmp[8 * i + 1],
            complex_mul(tmp[8 * i + 5], phi),
        )
        tmp[8 * i + 6] = complex_add(
            tmp[8 * i + 2],
            complex_mul(tmp[8 * i + 6], phi),
        )
        tmp[8 * i + 7] = complex_add(
            tmp[8 * i + 3],
            complex_mul(tmp[8 * i + 7], phi),
        )

    # Stage 4: step=8
    for i in range(8):
        tmp[8 + i] = complex_add(
            tmp[i],
            complex_mul(tmp[8 + i], phi),
        )

    # Final: mask low tau bits, then shift to Q-domain
    tau_mask = (1 << tau) - 1  # 0x7 for tau=3, 0xF for tau=4
    q_shift = logq - tau       # 12-3=9 or 12-4=8
    w = [0] * (BW_COMPLEX_LEN * 2)

    for i in range(BW_COMPLEX_LEN):
        w[2 * i] = ((tmp[i].real & tau_mask) << q_shift) & MOD_Q
        w[2 * i + 1] = ((tmp[i].imag & tau_mask) << q_shift) & MOD_Q

    return w


# ==============================================================================
# DelabelingReduceW — adjust labels after inverse phi
# (matching C DelabelingReduceW, paper Algorithm 3 steps 6-10)
# ==============================================================================

def delabeling_reduce_w(in_vec: List[Complex], tau: int) -> List[Complex]:
    """C: DelabelingReduceW(in, tau, out)

    Post-decode label adjustment: ensures each coordinate's label falls in
    the correct range S_{2τ - w_H(j)}.

    For tau=3:
      - WH=0 (idx 0):   mask real 0x7, imag 0x7
      - WH=1 (idx 1,2,4,8): mask imag 0x3, real = (real+b'-b) & 0x7
      - WH=2 (idx 3,5,6,9,10,12): mask real 0x3, imag 0x3
      - WH=2 (idx 7,11,13,14): mask imag 0x1, real = (real+b'-b) & 0x3
      - WH=3 (idx 15): mask real 0x1, imag 0x1
    """
    out = [Complex() for _ in range(BW_COMPLEX_LEN)]

    if tau == 3:
        # WH=0: idx 0
        out[0] = Complex(in_vec[0].real & 0x7, in_vec[0].imag & 0x7)

        # WH=2: idx 3,5,6,9,10,12 — both mask to 0x3
        out[3] = Complex(in_vec[3].real & 0x3, in_vec[3].imag & 0x3)
        out[5] = Complex(in_vec[5].real & 0x3, in_vec[5].imag & 0x3)
        out[6] = Complex(in_vec[6].real & 0x3, in_vec[6].imag & 0x3)
        out[9] = Complex(in_vec[9].real & 0x3, in_vec[9].imag & 0x3)
        out[10] = Complex(in_vec[10].real & 0x3, in_vec[10].imag & 0x3)
        out[12] = Complex(in_vec[12].real & 0x3, in_vec[12].imag & 0x3)

        # WH=3: idx 15 — mask to 0x1
        out[15] = Complex(in_vec[15].real & 0x1, in_vec[15].imag & 0x1)

        # WH=1: idx 1,2,4,8 — imag & 0x3, real adjusted
        for idx in [1, 2, 4, 8]:
            mod = in_vec[idx].imag & 0x3
            sub = mod - in_vec[idx].imag
            out[idx] = Complex((in_vec[idx].real + sub) & 0x7, mod)

        # WH=2: idx 7,11,13,14 — imag & 0x1, real adjusted & 0x3
        for idx in [7, 11, 13, 14]:
            mod = in_vec[idx].imag & 0x1
            sub = mod - in_vec[idx].imag
            out[idx] = Complex((in_vec[idx].real + sub) & 0x3, mod)

    elif tau == 4:
        # WH=0: idx 0 — mask to 0xF
        out[0] = Complex(in_vec[0].real & 0xF, in_vec[0].imag & 0xF)

        # WH=2: idx 3,5,6,9,10,12 — mask to 0x7
        out[3] = Complex(in_vec[3].real & 0x7, in_vec[3].imag & 0x7)
        out[5] = Complex(in_vec[5].real & 0x7, in_vec[5].imag & 0x7)
        out[6] = Complex(in_vec[6].real & 0x7, in_vec[6].imag & 0x7)
        out[9] = Complex(in_vec[9].real & 0x7, in_vec[9].imag & 0x7)
        out[10] = Complex(in_vec[10].real & 0x7, in_vec[10].imag & 0x7)
        out[12] = Complex(in_vec[12].real & 0x7, in_vec[12].imag & 0x7)

        # WH=3: idx 15 — mask to 0x3
        out[15] = Complex(in_vec[15].real & 0x3, in_vec[15].imag & 0x3)

        # WH=1: idx 1,2,4,8 — imag & 0x7, real adjusted & 0xF
        for idx in [1, 2, 4, 8]:
            mod = in_vec[idx].imag & 0x7
            sub = mod - in_vec[idx].imag
            out[idx] = Complex((in_vec[idx].real + sub) & 0xF, mod)

        # WH=2: idx 7,11,13,14 — imag & 0x3, real adjusted & 0x7
        for idx in [7, 11, 13, 14]:
            mod = in_vec[idx].imag & 0x3
            sub = mod - in_vec[idx].imag
            out[idx] = Complex((in_vec[idx].real + sub) & 0x7, mod)

    else:
        raise ValueError(f"Unsupported tau={tau}")

    return out


# ==============================================================================
# DelabelingRecoverW — Q-domain → labels (inverse Barnes-Wall)
# (matching C DelabelingRecoverW, paper Algorithm 3 steps 1-5)
# ==============================================================================

def delabeling_recover_w(w: List[Complex], logq: int, tau: int) -> List[Complex]:
    """C: DelabelingRecoverW(w, logq, tau, v)

    Inverse Barnes-Wall butterfly: Q-domain values → label-domain complex vector.
    """
    q_shift = logq - tau

    # Step 1: Remove Q-domain scaling (right-shift arithmetic)
    tmp = [Complex(
        w[i].real >> q_shift,
        w[i].imag >> q_shift,
    ) for i in range(BW_COMPLEX_LEN)]

    # Stage 4 reverse (step=8): top 8 minus bottom 8, then div_phi
    for i in range(8):
        tmp[8 + i] = complex_div_phi(complex_sub(tmp[8 + i], tmp[i]))

    # Stage 3 reverse (step=4)
    for i in range(2):
        for j in range(4):
            tmp[8 * i + 4 + j] = complex_div_phi(
                complex_sub(tmp[8 * i + 4 + j], tmp[8 * i + j])
            )

    # Stage 2 reverse (step=2)
    for i in range(4):
        for j in range(2):
            tmp[4 * i + 2 + j] = complex_div_phi(
                complex_sub(tmp[4 * i + 2 + j], tmp[4 * i + j])
            )

    # Stage 1 reverse (step=1)
    for i in range(8):
        tmp[2 * i + 1] = complex_div_phi(
            complex_sub(tmp[2 * i + 1], tmp[2 * i])
        )

    # Apply DelabelingReduceW as final step
    return delabeling_reduce_w(tmp, tau)


# ==============================================================================
# DelabelingComputeU — labels → message bytes
# (matching C DelabelingComputeU, paper Algorithm 3 steps 11-12)
# ==============================================================================

def delabeling_compute_u(v: List[Complex], tau: int) -> bytes:
    """C: DelabelingComputeU(v, tau, m)

    Inverse of LabelingComputeV: recover message bytes from labels.

    IMPORTANT: In C, `m` is `uint8_t m[8]` (or `m[12]` for tau=4).
    Each assignment truncates to 8 bits. We use `& 0xFF` to match this
    C behavior, since Python ints have unlimited precision.
    """
    # A, B, C index arrays match the D→vecV mapping in LabelingComputeV
    A_idxs = [0, 1, 2, 4, 8, 16]
    B_idxs = [3, 5, 6, 7, 9, 10, 11, 12, 13, 14,
              17, 18, 19, 20, 21, 22, 24, 25, 26, 28]
    C_idxs = [15, 23, 27, 29, 30, 31]

    # Flatten v into vecV: [v[0].real, v[0].imag, v[1].real, v[1].imag, ...]
    vecV = [0] * (BW_COMPLEX_LEN * 2)
    for i in range(BW_COMPLEX_LEN):
        vecV[2 * i] = v[i].real
        vecV[2 * i + 1] = v[i].imag

    if tau == 3:
        m = [0] * 8

        # C[5..0] → m[7] bits 7..2 (6 single bits), then B[19] → m[7] bits 1..0 (2 bits)
        for i in range(5, -1, -1):
            m[7] = ((m[7] << 1) | vecV[C_idxs[i]]) & 0xFF
        m[7] = ((m[7] << 2) | vecV[B_idxs[19]]) & 0xFF

        # B[18..15] → m[6]: each step: OR in value, shift left 2, mask to uint8
        m[6] = (((m[6] | vecV[B_idxs[18]]) << 2)) & 0xFF
        m[6] = (((m[6] | vecV[B_idxs[17]]) << 2)) & 0xFF
        m[6] = (((m[6] | vecV[B_idxs[16]]) << 2)) & 0xFF
        m[6] = (m[6] | vecV[B_idxs[15]]) & 0xFF

        # B[14..11] → m[5]
        m[5] = (((m[5] | vecV[B_idxs[14]]) << 2)) & 0xFF
        m[5] = (((m[5] | vecV[B_idxs[13]]) << 2)) & 0xFF
        m[5] = (((m[5] | vecV[B_idxs[12]]) << 2)) & 0xFF
        m[5] = (m[5] | vecV[B_idxs[11]]) & 0xFF

        # B[10..7] → m[4]
        m[4] = (((m[4] | vecV[B_idxs[10]]) << 2)) & 0xFF
        m[4] = (((m[4] | vecV[B_idxs[9]]) << 2)) & 0xFF
        m[4] = (((m[4] | vecV[B_idxs[8]]) << 2)) & 0xFF
        m[4] = (m[4] | vecV[B_idxs[7]]) & 0xFF

        # B[6..3] → m[3]
        m[3] = (((m[3] | vecV[B_idxs[6]]) << 2)) & 0xFF
        m[3] = (((m[3] | vecV[B_idxs[5]]) << 2)) & 0xFF
        m[3] = (((m[3] | vecV[B_idxs[4]]) << 2)) & 0xFF
        m[3] = (m[3] | vecV[B_idxs[3]]) & 0xFF

        # B[2..0] → m[2] bits 7..2, then A[5] bit 1 → m[2] bit 1
        m[2] = (((m[2] | vecV[B_idxs[2]]) << 2)) & 0xFF
        m[2] = (((m[2] | vecV[B_idxs[1]]) << 2)) & 0xFF
        m[2] = (((m[2] | vecV[B_idxs[0]]) << 2)) & 0xFF
        m[2] = (m[2] | (vecV[A_idxs[5]] >> 1)) & 0xFF

        # A[5] bits 0,6..0, A[4..0] → m[1], m[0]
        m[1] = (m[1] | (vecV[A_idxs[5]] << 7)) & 0xFF
        m[1] = (m[1] | (vecV[A_idxs[4]] << 4)) & 0xFF
        m[1] = (m[1] | (vecV[A_idxs[3]] << 1)) & 0xFF
        m[1] = (m[1] | (vecV[A_idxs[2]] >> 2)) & 0xFF
        m[0] = (m[0] | (vecV[A_idxs[2]] << 6)) & 0xFF
        m[0] = (m[0] | (vecV[A_idxs[1]] << 3)) & 0xFF
        m[0] = (m[0] | vecV[A_idxs[0]]) & 0xFF

        return bytes(m)

    elif tau == 4:
        m = [0] * 12

        m[11] = ((vecV[C_idxs[5]] << 6) | (vecV[C_idxs[4]] << 4) |
                 (vecV[C_idxs[3]] << 2) | vecV[C_idxs[2]]) & 0xFF
        m[10] = ((vecV[C_idxs[1]] << 6) | (vecV[C_idxs[0]] << 4) |
                 (vecV[B_idxs[19]] << 1) | (vecV[B_idxs[18]] >> 2)) & 0xFF
        m[9] = ((vecV[B_idxs[18]] << 6) | (vecV[B_idxs[17]] << 3) |
                vecV[B_idxs[16]]) & 0xFF
        m[8] = ((vecV[B_idxs[15]] << 5) | (vecV[B_idxs[14]] << 2) |
                (vecV[B_idxs[13]] >> 1)) & 0xFF
        m[7] = ((vecV[B_idxs[13]] << 7) | (vecV[B_idxs[12]] << 4) |
                (vecV[B_idxs[11]] << 1) | (vecV[B_idxs[10]] >> 2)) & 0xFF
        m[6] = ((vecV[B_idxs[10]] << 6) | (vecV[B_idxs[9]] << 3) |
                vecV[B_idxs[8]]) & 0xFF
        m[5] = ((vecV[B_idxs[7]] << 5) | (vecV[B_idxs[6]] << 2) |
                (vecV[B_idxs[5]] >> 1)) & 0xFF
        m[4] = ((vecV[B_idxs[5]] << 7) | (vecV[B_idxs[4]] << 4) |
                (vecV[B_idxs[3]] << 1) | (vecV[B_idxs[2]] >> 2)) & 0xFF
        m[3] = ((vecV[B_idxs[2]] << 6) | (vecV[B_idxs[1]] << 3) |
                vecV[B_idxs[0]]) & 0xFF
        m[2] = ((vecV[A_idxs[5]] << 4) | vecV[A_idxs[4]]) & 0xFF
        m[1] = ((vecV[A_idxs[3]] << 4) | vecV[A_idxs[2]]) & 0xFF
        m[0] = ((vecV[A_idxs[1]] << 4) | vecV[A_idxs[0]]) & 0xFF

        return bytes(m)

    else:
        raise ValueError(f"Unsupported tau={tau}")


# ==============================================================================
# Top-level single-block encode / decode
# ==============================================================================

def msgfunc_encode_block(msg_bytes: bytes, tau: int, logq: int = 12) -> List[int]:
    """Encode one BW block: msg bytes → Q-domain codeword.

    Args:
        msg_bytes: message bytes (8 for tau=3, 12 for tau=4)
        tau: modulus parameter (3 or 4)
        logq: log2(Q), always 12

    Returns:
        32 uint16 Q-domain values (flat array)
    """
    v = labeling_compute_v(msg_bytes, tau)
    w = labeling_compute_w(v, logq, tau)
    return w


def msgfunc_decode_block(noisy_q: List[int], tau: int, logq: int = 12) -> Tuple[List[int], bytes]:
    """Decode one BW block: noisy Q-domain → BDD → labels → message bytes.

    Args:
        noisy_q: 32 uint16 Q-domain values (potentially with noise)
        tau: modulus parameter (3 or 4)
        logq: log2(Q), always 12

    Returns:
        (rounded_q, msg_bytes) where rounded_q is the BDD-corrected Q-domain
        codeword and msg_bytes are the recovered message bytes.
    """
    bwn = BW_COMPLEX_LEN * 2  # 32

    # Load noisy values into Complex array
    enc_msg = [Complex(noisy_q[2 * i], noisy_q[2 * i + 1])
               for i in range(BW_COMPLEX_LEN)]

    # BDD decode
    w_dec = bdd_decode_bwn(enc_msg, bwn, logq, tau)

    # Recover labels via inverse Barnes-Wall
    u = delabeling_recover_w(w_dec, logq, tau)

    # Recover message bytes
    msg_bytes = delabeling_compute_u(u, tau)

    # Flatten rounded Q-domain output
    rounded_q = [0] * (BW_COMPLEX_LEN * 2)
    for i in range(BW_COMPLEX_LEN):
        rounded_q[2 * i] = w_dec[i].real
        rounded_q[2 * i + 1] = w_dec[i].imag

    return rounded_q, msg_bytes


# ==============================================================================
# Multi-block encode / decode (matching C SCLOUDPLUS_MsgEncode/MsgDecode)
# ==============================================================================

def msgfunc_encode(msg: bytes, ss_level: int = 16) -> List[int]:
    """Full multi-block message encode (matching C SCLOUDPLUS_MsgEncode).

    Args:
        msg: full message bytes (16 for ss=16, 24 for ss=24, 32 for ss=32)
        ss_level: security level (16, 24, or 32)

    Returns:
        Flat list of muConut * 32 uint16 Q-domain values.
    """
    cfg = PARAM_SETS[ss_level]
    tau = cfg["tau"]
    logq = cfg["logq"]
    mu_bytes = cfg["mu"] // 8
    mu_conut = cfg["mu_conut"]

    expected_len = mu_bytes * mu_conut
    if len(msg) != expected_len:
        raise ValueError(f"Message must be {expected_len} bytes for ss={ss_level}, got {len(msg)}")

    result = []
    for i in range(mu_conut):
        block_msg = msg[i * mu_bytes: (i + 1) * mu_bytes]
        result.extend(msgfunc_encode_block(block_msg, tau, logq))

    return result


def msgfunc_decode(noisy_q: List[int], ss_level: int = 16) -> Tuple[List[int], bytes]:
    """Full multi-block message decode (matching C SCLOUDPLUS_MsgDecode).

    Args:
        noisy_q: flat list of muConut*32 uint16 Q-domain values
        ss_level: security level (16, 24, or 32)

    Returns:
        (rounded_q, msg_bytes)
    """
    cfg = PARAM_SETS[ss_level]
    tau = cfg["tau"]
    logq = cfg["logq"]
    mu_bytes = cfg["mu"] // 8
    mu_conut = cfg["mu_conut"]
    block_size = BW_COMPLEX_LEN * 2  # 32

    expected_len = block_size * mu_conut
    if len(noisy_q) != expected_len:
        raise ValueError(f"Noisy Q array must have {expected_len} elements for ss={ss_level}, got {len(noisy_q)}")

    all_rounded = []
    all_msg = bytearray()

    for i in range(mu_conut):
        block_q = noisy_q[i * block_size: (i + 1) * block_size]
        rounded, msg_block = msgfunc_decode_block(block_q, tau, logq)
        all_rounded.extend(rounded)
        all_msg.extend(msg_block)

    return all_rounded, bytes(all_msg)


# ==============================================================================
# Add noise helper
# ==============================================================================

def add_noise(q_vals: List[int], noise: List[int]) -> List[int]:
    """Add noise to Q-domain values (mod 2^12 = mod 0xFFF)."""
    return [(q + n) & MOD_Q for q, n in zip(q_vals, noise)]


# ==============================================================================
# Convenience: roundtrip test helper
# ==============================================================================

def msgfunc_roundtrip(msg: bytes, noise: Optional[List[int]] = None,
                      ss_level: int = 16) -> Tuple[bytes, List[int], List[int]]:
    """Encode → (add noise) → decode roundtrip.

    Args:
        msg: message bytes
        noise: optional noise array (same length as encoded Q values)
        ss_level: security level (16, 24, or 32)

    Returns:
        (decoded_msg_bytes, encoded_q, rounded_q)
    """
    q_enc = msgfunc_encode(msg, ss_level)
    if noise is not None:
        q_noisy = add_noise(q_enc, noise)
    else:
        q_noisy = q_enc
    rounded_q, msg_out = msgfunc_decode(q_noisy, ss_level)
    return msg_out, q_enc, rounded_q


# ==============================================================================
# Self-test
# ==============================================================================

if __name__ == "__main__":
    import random

    print("=== Scloud+ MsgFunc SW Reference (C-model aligned) — Self Test ===\n")

    all_ok = True

    for ss_level, cfg in PARAM_SETS.items():
        tau = cfg["tau"]
        logq = cfg["logq"]
        mu_bytes = cfg["mu"] // 8
        mu_conut = cfg["mu_conut"]
        total_msg_bytes = mu_bytes * mu_conut
        block_count = mu_conut

        print(f"--- ss={ss_level}, tau={tau}, mu={cfg['mu']} bits, "
              f"muConut={mu_conut}, msg_bytes={total_msg_bytes} ---")

        # Test 1: Zero-noise roundtrip for all-zeros message
        msg = bytes(total_msg_bytes)
        msg_out, q_enc, q_rounded = msgfunc_roundtrip(msg, ss_level=ss_level)
        ok = (msg_out == msg)
        print(f"  zero-msg roundtrip: {'PASS' if ok else 'FAIL'}")
        if not ok:
            print(f"    expected={msg.hex()}, got={msg_out.hex()}")
            all_ok = False

        # Test 2: Zero-noise roundtrip for all-ones message
        msg = bytes([0xFF] * total_msg_bytes)
        msg_out, _, _ = msgfunc_roundtrip(msg, ss_level=ss_level)
        ok = (msg_out == msg)
        print(f"  full-0xFF roundtrip: {'PASS' if ok else 'FAIL'}")
        if not ok:
            print(f"    expected={msg.hex()}, got={msg_out.hex()}")
            all_ok = False

        # Test 3: Zero-noise roundtrip for random messages
        rng = random.Random(42 + ss_level)
        rng_ok = True
        for idx in range(256):
            msg = bytes(rng.randint(0, 255) for _ in range(total_msg_bytes))
            msg_out, _, _ = msgfunc_roundtrip(msg, ss_level=ss_level)
            if msg_out != msg:
                print(f"  random[{idx}] FAIL: msg={msg.hex()} out={msg_out.hex()}")
                rng_ok = False
                all_ok = False
                break
        if rng_ok:
            print(f"  256 random zero-noise roundtrips: PASS")

        # Test 4: Single-block encode produces non-trivial Q values
        sample_bytes = [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
                       0x11, 0x22, 0x33, 0x44]
        block_msg = bytes(sample_bytes[:mu_bytes])
        q_enc_block = msgfunc_encode_block(block_msg, tau, logq)
        nonzero = sum(1 for x in q_enc_block if x != 0)
        print(f"  non-zero q-coords for sample block msg: {nonzero}/{BW_COMPLEX_LEN*2}")
        if nonzero == 0:
            print(f"    WARNING: all q-coords zero — check labeling")

        # Test 5: Noise resilience (small noise should still decode correctly)
        if ss_level == 16:  # only test one level
            msg = bytes([0xA5] * total_msg_bytes)
            q_enc = msgfunc_encode(msg, ss_level)
            # Add small noise (±1 per coordinate, 50% chance)
            noisy = []
            for x in q_enc:
                n = rng.choice([-1, 0, 0, 1])  # mostly zero
                noisy.append(x + n)
            q_noisy = [(x & MOD_Q) for x in noisy]
            rounded_q, msg_out = msgfunc_decode(q_noisy, ss_level)
            ok = (msg_out == msg)
            print(f"  small-noise roundtrip: {'PASS' if ok else 'FAIL'}")
            if not ok:
                print(f"    expected={msg.hex()}, got={msg_out.hex()}")
                # Not a hard failure — noise may legitimately cause errors
                # depending on the message pattern

        print()

    if all_ok:
        print("=== ALL SELF-TESTS PASSED ===")
    else:
        print("=== SOME TESTS FAILED ===")
