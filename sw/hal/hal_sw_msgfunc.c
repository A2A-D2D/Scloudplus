/*
 * hal_sw_msgfunc.c — Pure-C functional model of the SCLOUD+ message function
 * (Barnes-Wall lattice encode/decode). Bit-exact with the openHiTLS C
 * reference and the RTL (scloud_msgfunc_param + scloud_bdd_recursive).
 *
 * Reference: Anyu Wang et al., "Scloud+: a Lightweight LWE-based KEM without
 * Ring/Module Structure", IACR ePrint 2024/1306.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../include/scloudplus_hal.h"

/* =========================================================================
 * Complex number helpers (matching C struct Complex { int32_t real, imag; })
 * ========================================================================= */

typedef struct {
    int32_t real;
    int32_t imag;
} Complex;

static inline Complex cpx_add(Complex a, Complex b) {
    return (Complex){a.real + b.real, a.imag + b.imag};
}

static inline Complex cpx_sub(Complex a, Complex b) {
    return (Complex){a.real - b.real, a.imag - b.imag};
}

static inline Complex cpx_mul(Complex a, Complex b) {
    return (Complex){
        a.real * b.real - a.imag * b.imag,
        a.real * b.imag + a.imag * b.real
    };
}

/* Divide by (1+i): multiply by (1-i)/2 = (a+b)/2 + i*(b-a)/2
 * Uses arithmetic right-shift (C does this for signed ints). */
static inline Complex cpx_div_phi(Complex a) {
    return (Complex){
        (a.real + a.imag) >> 1,
        (a.imag - a.real) >> 1
    };
}

/* =========================================================================
 * Round function (matching C Round(in, logq, tau))
 *
 * Rounds 'value' to the nearest multiple of 2^(logq-tau).
 * Uses C-style signed division (truncation toward zero) semantics.
 * ========================================================================= */

static int32_t round_to_delta(int32_t value, int logq, int tau) {
    int32_t mod  = 1 << (logq - tau);  /* e.g. logq=12,tau=3 → 512 */
    int32_t mod2 = mod >> 1;           /* 256 */
    int32_t r, q;

    if (value >= 0) {
        q = value / mod;               /* truncate toward zero */
        r = value - q * mod;
        if (r >= mod2) q += 1;
    } else {
        /* C truncates toward zero for negative division */
        q = value / mod;               /* e.g. -300/512 = 0 in C */
        r = value - q * mod;           /* e.g. -300 - 0 = -300 */
        if (r <= -mod2) q -= 1;
    }

    return q * mod;
}

/* =========================================================================
 * Euclidean distance (squared, matching C EuclideanDistanceNoSqrt)
 * ========================================================================= */

static int32_t euclidean_distance_sq(const Complex *a, const Complex *b, int len) {
    int32_t sum = 0;
    for (int i = 0; i < len; i++) {
        int32_t dr = a[i].real - b[i].real;
        int32_t di = a[i].imag - b[i].imag;
        sum += dr * dr + di * di;
    }
    return sum;
}

/* =========================================================================
 * BDD (Bounded-Distance Decoding) — recursive Barnes-Wall decoder
 * Matching C BDDForBWn AND RTL scloud_bdd_recursive.
 *
 * bwn: total real dimensions (2, 4, 8, ..., 32), must be power of 2.
 * t: input complex array of bwn/2 elements (Q-domain values).
 * logq, tau: parameters.
 * Returns dynamically allocated Complex array of bwn/2 elements (caller frees).
 * ========================================================================= */

static Complex *bdd_decode_bwn(const Complex *t, int bwn, int logq, int tau) {
    int t_len = bwn >> 1;       /* number of complex coords */
    int half  = t_len >> 1;

    Complex *result = (Complex *)malloc(t_len * sizeof(Complex));
    if (!result) return NULL;

    /* Base case: bwn == 2 → 1 complex coord, round independently */
    if (bwn == 2) {
        result[0].real = round_to_delta(t[0].real, logq, tau);
        result[0].imag = round_to_delta(t[0].imag, logq, tau);
        return result;
    }

    /* Split: t1 = left half, t2 = right half */
    const Complex *t1 = t;
    const Complex *t2 = t + half;

    /* Recursive decode */
    Complex *y1 = bdd_decode_bwn(t1, t_len, logq, tau);
    Complex *y2 = bdd_decode_bwn(t2, t_len, logq, tau);
    if (!y1 || !y2) { free(y1); free(y2); free(result); return NULL; }

    /* Compute z1in = div_phi(t2[i] - y1[i]), z2in = div_phi(t1[i] - y2[i]) */
    Complex *z1in = (Complex *)malloc(half * sizeof(Complex));
    Complex *z2in = (Complex *)malloc(half * sizeof(Complex));
    if (!z1in || !z2in) {
        free(y1); free(y2); free(z1in); free(z2in); free(result);
        return NULL;
    }

    for (int i = 0; i < half; i++) {
        z1in[i] = cpx_div_phi(cpx_sub(t2[i], y1[i]));
        z2in[i] = cpx_div_phi(cpx_sub(t1[i], y2[i]));
    }

    /* Recursive decode residuals */
    Complex *z1 = bdd_decode_bwn(z1in, t_len, logq, tau);
    Complex *z2 = bdd_decode_bwn(z2in, t_len, logq, tau);
    free(z1in); free(z2in);
    if (!z1 || !z2) {
        free(y1); free(y2); free(z1); free(z2); free(result);
        return NULL;
    }

    /* Forward transform: multiply by phi = (1+i) */
    Complex phi = {1, 1};
    Complex *z1_phi = (Complex *)malloc(half * sizeof(Complex));
    Complex *z2_phi = (Complex *)malloc(half * sizeof(Complex));
    if (!z1_phi || !z2_phi) {
        free(y1); free(y2); free(z1); free(z2); free(z1_phi); free(z2_phi);
        free(result); return NULL;
    }

    for (int i = 0; i < half; i++) {
        z1_phi[i] = cpx_mul(z1[i], phi);
        z2_phi[i] = cpx_mul(z2[i], phi);
    }

    /* Build candidates */
    Complex *out1 = (Complex *)malloc(t_len * sizeof(Complex));
    Complex *out2 = (Complex *)malloc(t_len * sizeof(Complex));
    if (!out1 || !out2) {
        free(y1); free(y2); free(z1); free(z2); free(z1_phi); free(z2_phi);
        free(out1); free(out2); free(result); return NULL;
    }

    for (int i = 0; i < half; i++) {
        out1[i]          = y1[i];
        out1[half + i]   = cpx_add(y1[i], z1_phi[i]);
        out2[i]          = cpx_add(y2[i], z2_phi[i]);
        out2[half + i]   = y2[i];
    }

    /* Choose closer candidate (strict less-than: d1 < d2 → out1, else out2) */
    int32_t d1 = euclidean_distance_sq(out1, t, t_len);
    int32_t d2 = euclidean_distance_sq(out2, t, t_len);

    if (d1 < d2) {
        memcpy(result, out1, t_len * sizeof(Complex));
    } else {
        memcpy(result, out2, t_len * sizeof(Complex));
    }

    /* Cleanup */
    free(y1); free(y2); free(z1); free(z2);
    free(z1_phi); free(z2_phi); free(out1); free(out2);
    return result;
}

/* =========================================================================
 * LabelingComputeV — message bytes → complex label vector
 * (matching C LabelingComputeV, paper Algorithm 2 steps 1-3)
 *
 * For tau=3: input 8 bytes → 16 complex labels (A[6], B[20], C[6])
 * For tau=4: input 12 bytes → 16 complex labels
 * ========================================================================= */

static int labeling_compute_v(const uint8_t *m, int tau, Complex v[SCLOUD_BW_COMPLEX]) {
    uint8_t A[6] = {0};
    uint8_t B[20] = {0};
    uint8_t C[6] = {0};

    if (tau == 3) {
        A[0] = (m[0] >> 0) & 0x07;
        A[1] = (m[0] >> 3) & 0x07;
        A[2] = ((m[0] >> 6) & 0x03) | ((m[1] << 2) & 0x04);
        A[3] = (m[1] >> 1) & 0x07;
        A[4] = (m[1] >> 4) & 0x07;
        A[5] = ((m[1] >> 7) & 0x01) | ((m[2] << 1) & 0x06);

        for (int i = 0; i < 3; i++)
            B[i] = (m[2] >> (2 + 2 * i)) & 0x03;

        for (int i = 0; i < 4; i++) {
            B[3 + i]  = (m[3] >> (2 * i)) & 0x03;
            B[7 + i]  = (m[4] >> (2 * i)) & 0x03;
            B[11 + i] = (m[5] >> (2 * i)) & 0x03;
            B[15 + i] = (m[6] >> (2 * i)) & 0x03;
        }

        B[19] = m[7] & 0x03;
        C[0] = (m[7] >> 2) & 0x01;
        C[1] = (m[7] >> 3) & 0x01;
        C[2] = (m[7] >> 4) & 0x01;
        C[3] = (m[7] >> 5) & 0x01;
        C[4] = (m[7] >> 6) & 0x01;
        C[5] = (m[7] >> 7) & 0x01;
    } else if (tau == 4) {
        A[0] = m[0] & 0x0F;
        A[1] = (m[0] >> 4) & 0x0F;
        A[2] = m[1] & 0x0F;
        A[3] = (m[1] >> 4) & 0x0F;
        A[4] = m[2] & 0x0F;
        A[5] = (m[2] >> 4) & 0x0F;

        B[0] = m[3] & 0x07;
        B[1] = (m[3] >> 3) & 0x07;
        B[2] = ((m[3] >> 6) & 0x03) | ((m[4] << 2) & 0x04);
        B[3] = (m[4] >> 1) & 0x07;
        B[4] = (m[4] >> 4) & 0x07;
        B[5] = ((m[4] >> 7) & 0x01) | ((m[5] << 1) & 0x06);
        B[6] = (m[5] >> 2) & 0x07;
        B[7] = (m[5] >> 5) & 0x07;
        B[8] = m[6] & 0x07;
        B[9] = (m[6] >> 3) & 0x07;
        B[10] = ((m[6] >> 6) & 0x03) | ((m[7] << 2) & 0x04);
        B[11] = (m[7] >> 1) & 0x07;
        B[12] = (m[7] >> 4) & 0x07;
        B[13] = ((m[7] >> 7) & 0x01) | ((m[8] << 1) & 0x06);
        B[14] = (m[8] >> 2) & 0x07;
        B[15] = (m[8] >> 5) & 0x07;
        B[16] = m[9] & 0x07;
        B[17] = (m[9] >> 3) & 0x07;
        B[18] = ((m[9] >> 6) & 0x03) | ((m[10] << 2) & 0x04);
        B[19] = (m[10] >> 1) & 0x07;
        C[0] = (m[10] >> 4) & 0x03;
        C[1] = (m[10] >> 6) & 0x03;
        C[2] = m[11] & 0x03;
        C[3] = (m[11] >> 2) & 0x03;
        C[4] = (m[11] >> 4) & 0x03;
        C[5] = (m[11] >> 6) & 0x03;
    } else {
        return -1;
    }

    /* D array: rearrange A/B/C into 32 label values in a fixed order
     * D = {A0,A1,A2,B0,A3,B1,B2,B3,A4,B4,B5,B6,B7,B8,B9,C0,
     *       A5,B10,B11,B12,B13,B14,B15,C1,B16,B17,B18,C2,B19,C3,C4,C5} */
    const int D_order[32] = {
        0, 1, 2, 3, 4, 5, 6, 7,
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23,
        24, 25, 26, 27, 28, 29, 30, 31
    };
    /* Source indices into A/B/C arrays */
    const int src_type[32] = {
        0,0,0,1, 0,1,1,1,   /* 0-7:   A[0],A[1],A[2],B[0],A[3],B[1],B[2],B[3] */
        0,1,1,1, 1,1,1,2,   /* 8-15:  A[4],B[4],B[5],B[6],B[7],B[8],B[9],C[0] */
        0,1,1,1, 1,1,1,2,   /* 16-23: A[5],B[10],B[11],B[12],B[13],B[14],B[15],C[1] */
        1,1,1,2, 1,2,2,2    /* 24-31: B[16],B[17],B[18],C[2],B[19],C[3],C[4],C[5] */
    };
    const int src_idx[32] = {
        0,1,2,0, 3,1,2,3,   /* A0,A1,A2,B0,A3,B1,B2,B3 */
        4,4,5,6, 7,8,9,0,   /* A4,B4,B5,B6,B7,B8,B9,C0 */
        5,10,11,12, 13,14,15,1, /* A5,B10,B11,B12,B13,B14,B15,C1 */
        16,17,18,2, 19,3,4,5    /* B16,B17,B18,C2,B19,C3,C4,C5 */
    };

    uint8_t D_vals[32];
    for (int i = 0; i < 32; i++) {
        if (src_type[i] == 0)       D_vals[i] = A[src_idx[i]];
        else if (src_type[i] == 1)  D_vals[i] = B[src_idx[i]];
        else                        D_vals[i] = C[src_idx[i]];
    }

    for (int i = 0; i < SCLOUD_BW_COMPLEX; i++) {
        v[i].real = D_vals[2 * i];
        v[i].imag = D_vals[2 * i + 1];
    }

    return 0;
}

/* =========================================================================
 * LabelingComputeW — labels → Q-domain codeword (Barnes-Wall butterfly)
 * (matching C LabelingComputeW, paper Algorithm 2 steps 4-8)
 * ========================================================================= */

static int labeling_compute_w(const Complex v[SCLOUD_BW_COMPLEX],
                               int logq, int tau,
                               uint16_t w[SCLOUD_BW_REAL]) {
    Complex phi = {1, 1};
    Complex tmp[SCLOUD_BW_COMPLEX];
    memcpy(tmp, v, sizeof(tmp));

    /* Barnes-Wall butterfly: 4 stages, step = 1, 2, 4, 8 */
    /* Stage 1: step=1 (pairs 0-1, 2-3, ..., 14-15) */
    for (int i = 0; i < 8; i++) {
        tmp[2 * i + 1] = cpx_add(tmp[2 * i], cpx_mul(tmp[2 * i + 1], phi));
    }

    /* Stage 2: step=2 */
    for (int i = 0; i < 4; i++) {
        tmp[4 * i + 2] = cpx_add(tmp[4 * i], cpx_mul(tmp[4 * i + 2], phi));
        tmp[4 * i + 3] = cpx_add(tmp[4 * i + 1], cpx_mul(tmp[4 * i + 3], phi));
    }

    /* Stage 3: step=4 */
    for (int i = 0; i < 2; i++) {
        tmp[8 * i + 4] = cpx_add(tmp[8 * i], cpx_mul(tmp[8 * i + 4], phi));
        tmp[8 * i + 5] = cpx_add(tmp[8 * i + 1], cpx_mul(tmp[8 * i + 5], phi));
        tmp[8 * i + 6] = cpx_add(tmp[8 * i + 2], cpx_mul(tmp[8 * i + 6], phi));
        tmp[8 * i + 7] = cpx_add(tmp[8 * i + 3], cpx_mul(tmp[8 * i + 7], phi));
    }

    /* Stage 4: step=8 */
    for (int i = 0; i < 8; i++) {
        tmp[8 + i] = cpx_add(tmp[i], cpx_mul(tmp[8 + i], phi));
    }

    /* Final: mask low tau bits, shift to Q-domain */
    int tau_mask  = (1 << tau) - 1;    /* 0x7 for tau=3, 0xF for tau=4 */
    int q_shift   = logq - tau;         /* 9 for tau=3, 8 for tau=4 */

    for (int i = 0; i < SCLOUD_BW_COMPLEX; i++) {
        w[2 * i]     = (uint16_t)(((tmp[i].real & tau_mask) << q_shift) & SCLOUD_MOD_Q);
        w[2 * i + 1] = (uint16_t)(((tmp[i].imag & tau_mask) << q_shift) & SCLOUD_MOD_Q);
    }

    return 0;
}

/* =========================================================================
 * DelabelingReduceW — adjust labels after inverse phi
 * (matching C DelabelingReduceW, paper Algorithm 3 steps 6-10)
 * ========================================================================= */

static int delabeling_reduce_w(const Complex in[SCLOUD_BW_COMPLEX],
                                int tau,
                                Complex out[SCLOUD_BW_COMPLEX]) {
    int mod_val, sub;

    if (tau == 3) {
        /* WH=0: idx 0 */
        out[0] = (Complex){in[0].real & 0x7, in[0].imag & 0x7};
        /* WH=2: idx 3,5,6,9,10,12 */
        out[3] = (Complex){in[3].real & 0x3, in[3].imag & 0x3};
        out[5] = (Complex){in[5].real & 0x3, in[5].imag & 0x3};
        out[6] = (Complex){in[6].real & 0x3, in[6].imag & 0x3};
        out[9] = (Complex){in[9].real & 0x3, in[9].imag & 0x3};
        out[10] = (Complex){in[10].real & 0x3, in[10].imag & 0x3};
        out[12] = (Complex){in[12].real & 0x3, in[12].imag & 0x3};
        /* WH=3: idx 15 */
        out[15] = (Complex){in[15].real & 0x1, in[15].imag & 0x1};

        /* WH=1: idx 1,2,4,8 — imag & 0x3, real adjusted & 0x7 */
        int wh1_idxs[] = {1, 2, 4, 8};
        for (int k = 0; k < 4; k++) {
            int idx = wh1_idxs[k];
            mod_val = in[idx].imag & 0x3;
            sub = mod_val - in[idx].imag;
            out[idx] = (Complex){(in[idx].real + sub) & 0x7, mod_val};
        }

        /* WH=2: idx 7,11,13,14 — imag & 0x1, real adjusted & 0x3 */
        int wh2_idxs[] = {7, 11, 13, 14};
        for (int k = 0; k < 4; k++) {
            int idx = wh2_idxs[k];
            mod_val = in[idx].imag & 0x1;
            sub = mod_val - in[idx].imag;
            out[idx] = (Complex){(in[idx].real + sub) & 0x3, mod_val};
        }
    } else if (tau == 4) {
        /* WH=0: idx 0 — mask to 0xF */
        out[0] = (Complex){in[0].real & 0xF, in[0].imag & 0xF};
        /* WH=2: idx 3,5,6,9,10,12 — mask to 0x7 */
        int wh2a_idxs[] = {3, 5, 6, 9, 10, 12};
        for (int k = 0; k < 6; k++) {
            int idx = wh2a_idxs[k];
            out[idx] = (Complex){in[idx].real & 0x7, in[idx].imag & 0x7};
        }
        /* WH=3: idx 15 — mask to 0x3 */
        out[15] = (Complex){in[15].real & 0x3, in[15].imag & 0x3};

        /* WH=1: idx 1,2,4,8 — imag & 0x7, real adjusted & 0xF */
        int wh1_idxs[] = {1, 2, 4, 8};
        for (int k = 0; k < 4; k++) {
            int idx = wh1_idxs[k];
            mod_val = in[idx].imag & 0x7;
            sub = mod_val - in[idx].imag;
            out[idx] = (Complex){(in[idx].real + sub) & 0xF, mod_val};
        }

        /* WH=2: idx 7,11,13,14 — imag & 0x3, real adjusted & 0x7 */
        int wh2b_idxs[] = {7, 11, 13, 14};
        for (int k = 0; k < 4; k++) {
            int idx = wh2b_idxs[k];
            mod_val = in[idx].imag & 0x3;
            sub = mod_val - in[idx].imag;
            out[idx] = (Complex){(in[idx].real + sub) & 0x7, mod_val};
        }
    } else {
        return -1;
    }

    return 0;
}

/* =========================================================================
 * DelabelingRecoverW — Q-domain → labels (inverse Barnes-Wall butterfly)
 * (matching C DelabelingRecoverW, paper Algorithm 3 steps 1-5)
 * ========================================================================= */

static int delabeling_recover_w(const Complex w[SCLOUD_BW_COMPLEX],
                                 int logq, int tau,
                                 Complex v[SCLOUD_BW_COMPLEX]) {
    int q_shift = logq - tau;
    Complex tmp[SCLOUD_BW_COMPLEX];

    /* Step 1: remove Q-domain scaling (arithmetic right-shift) */
    for (int i = 0; i < SCLOUD_BW_COMPLEX; i++) {
        tmp[i].real = w[i].real >> q_shift;
        tmp[i].imag = w[i].imag >> q_shift;
    }

    /* Reverse stages: step 8, 4, 2, 1 */
    /* Stage 4 reverse: step=8 */
    for (int i = 0; i < 8; i++) {
        tmp[8 + i] = cpx_div_phi(cpx_sub(tmp[8 + i], tmp[i]));
    }

    /* Stage 3 reverse: step=4 */
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 4; j++) {
            tmp[8 * i + 4 + j] = cpx_div_phi(
                cpx_sub(tmp[8 * i + 4 + j], tmp[8 * i + j]));
        }
    }

    /* Stage 2 reverse: step=2 */
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 2; j++) {
            tmp[4 * i + 2 + j] = cpx_div_phi(
                cpx_sub(tmp[4 * i + 2 + j], tmp[4 * i + j]));
        }
    }

    /* Stage 1 reverse: step=1 */
    for (int i = 0; i < 8; i++) {
        tmp[2 * i + 1] = cpx_div_phi(cpx_sub(tmp[2 * i + 1], tmp[2 * i]));
    }

    /* Apply DelabelingReduceW */
    return delabeling_reduce_w(tmp, tau, v);
}

/* =========================================================================
 * DelabelingComputeU — labels → message bytes
 * (matching C DelabelingComputeU, paper Algorithm 3 steps 11-12)
 *
 * Inverse of LabelingComputeV.
 * ========================================================================= */

static int delabeling_compute_u(const Complex v[SCLOUD_BW_COMPLEX],
                                 int tau, uint8_t *m) {
    /* Flatten v into vecV[0..31] = [v[0].real, v[0].imag, v[1].real, v[1].imag, ...] */
    uint16_t vecV[SCLOUD_BW_REAL];
    for (int i = 0; i < SCLOUD_BW_COMPLEX; i++) {
        vecV[2 * i]     = (uint16_t)v[i].real;
        vecV[2 * i + 1] = (uint16_t)v[i].imag;
    }

    /* Index maps matching LabelingComputeV's D array */
    const int A_idxs[6] = {0, 1, 2, 4, 8, 16};
    const int B_idxs[20] = {3, 5, 6, 7, 9, 10, 11, 12, 13, 14,
                             17, 18, 19, 20, 21, 22, 24, 25, 26, 28};
    const int C_idxs[6] = {15, 23, 27, 29, 30, 31};

    if (tau == 3) {
        memset(m, 0, 8);

        /* C[5..0] → m[7] bits 7..2 (6 single bits), then B[19] → m[7] bits 1..0 */
        for (int i = 5; i >= 0; i--)
            m[7] = (uint8_t)(((uint16_t)m[7] << 1) | vecV[C_idxs[i]]);
        m[7] = (uint8_t)(((uint16_t)m[7] << 2) | vecV[B_idxs[19]]);

        /* B[18..15] → m[6] */
        m[6] = (uint8_t)((((uint16_t)m[6] | vecV[B_idxs[18]]) << 2) & 0xFF);
        m[6] = (uint8_t)((((uint16_t)m[6] | vecV[B_idxs[17]]) << 2) & 0xFF);
        m[6] = (uint8_t)((((uint16_t)m[6] | vecV[B_idxs[16]]) << 2) & 0xFF);
        m[6] = (uint8_t)(m[6] | vecV[B_idxs[15]]);

        /* B[14..11] → m[5] */
        m[5] = (uint8_t)((((uint16_t)m[5] | vecV[B_idxs[14]]) << 2) & 0xFF);
        m[5] = (uint8_t)((((uint16_t)m[5] | vecV[B_idxs[13]]) << 2) & 0xFF);
        m[5] = (uint8_t)((((uint16_t)m[5] | vecV[B_idxs[12]]) << 2) & 0xFF);
        m[5] = (uint8_t)(m[5] | vecV[B_idxs[11]]);

        /* B[10..7] → m[4] */
        m[4] = (uint8_t)((((uint16_t)m[4] | vecV[B_idxs[10]]) << 2) & 0xFF);
        m[4] = (uint8_t)((((uint16_t)m[4] | vecV[B_idxs[9]]) << 2) & 0xFF);
        m[4] = (uint8_t)((((uint16_t)m[4] | vecV[B_idxs[8]]) << 2) & 0xFF);
        m[4] = (uint8_t)(m[4] | vecV[B_idxs[7]]);

        /* B[6..3] → m[3] */
        m[3] = (uint8_t)((((uint16_t)m[3] | vecV[B_idxs[6]]) << 2) & 0xFF);
        m[3] = (uint8_t)((((uint16_t)m[3] | vecV[B_idxs[5]]) << 2) & 0xFF);
        m[3] = (uint8_t)((((uint16_t)m[3] | vecV[B_idxs[4]]) << 2) & 0xFF);
        m[3] = (uint8_t)(m[3] | vecV[B_idxs[3]]);

        /* B[2..0] → m[2] bits 7..2, A[5] bit 1 → m[2] bit 1 */
        m[2] = (uint8_t)((((uint16_t)m[2] | vecV[B_idxs[2]]) << 2) & 0xFF);
        m[2] = (uint8_t)((((uint16_t)m[2] | vecV[B_idxs[1]]) << 2) & 0xFF);
        m[2] = (uint8_t)((((uint16_t)m[2] | vecV[B_idxs[0]]) << 2) & 0xFF);
        m[2] = (uint8_t)(m[2] | (vecV[A_idxs[5]] >> 1));

        /* A[5] bit 7..0, A[4..0] → m[1], m[0] */
        m[1] = (uint8_t)(m[1] | (vecV[A_idxs[5]] << 7));
        m[1] = (uint8_t)(m[1] | (vecV[A_idxs[4]] << 4));
        m[1] = (uint8_t)(m[1] | (vecV[A_idxs[3]] << 1));
        m[1] = (uint8_t)(m[1] | (vecV[A_idxs[2]] >> 2));
        m[0] = (uint8_t)(m[0] | (vecV[A_idxs[2]] << 6));
        m[0] = (uint8_t)(m[0] | (vecV[A_idxs[1]] << 3));
        m[0] = (uint8_t)(m[0] | vecV[A_idxs[0]]);
    } else if (tau == 4) {
        memset(m, 0, 12);

        m[11] = (uint8_t)((vecV[C_idxs[5]] << 6) | (vecV[C_idxs[4]] << 4) |
                          (vecV[C_idxs[3]] << 2) | vecV[C_idxs[2]]);
        m[10] = (uint8_t)((vecV[C_idxs[1]] << 6) | (vecV[C_idxs[0]] << 4) |
                          (vecV[B_idxs[19]] << 1) | (vecV[B_idxs[18]] >> 2));
        m[9]  = (uint8_t)((vecV[B_idxs[18]] << 6) | (vecV[B_idxs[17]] << 3) |
                          vecV[B_idxs[16]]);
        m[8]  = (uint8_t)((vecV[B_idxs[15]] << 5) | (vecV[B_idxs[14]] << 2) |
                          (vecV[B_idxs[13]] >> 1));
        m[7]  = (uint8_t)((vecV[B_idxs[13]] << 7) | (vecV[B_idxs[12]] << 4) |
                          (vecV[B_idxs[11]] << 1) | (vecV[B_idxs[10]] >> 2));
        m[6]  = (uint8_t)((vecV[B_idxs[10]] << 6) | (vecV[B_idxs[9]] << 3) |
                          vecV[B_idxs[8]]);
        m[5]  = (uint8_t)((vecV[B_idxs[7]] << 5) | (vecV[B_idxs[6]] << 2) |
                          (vecV[B_idxs[5]] >> 1));
        m[4]  = (uint8_t)((vecV[B_idxs[5]] << 7) | (vecV[B_idxs[4]] << 4) |
                          (vecV[B_idxs[3]] << 1) | (vecV[B_idxs[2]] >> 2));
        m[3]  = (uint8_t)((vecV[B_idxs[2]] << 6) | (vecV[B_idxs[1]] << 3) |
                          vecV[B_idxs[0]]);
        m[2]  = (uint8_t)((vecV[A_idxs[5]] << 4) | vecV[A_idxs[4]]);
        m[1]  = (uint8_t)((vecV[A_idxs[3]] << 4) | vecV[A_idxs[2]]);
        m[0]  = (uint8_t)((vecV[A_idxs[1]] << 4) | vecV[A_idxs[0]]);
    } else {
        return -1;
    }

    return 0;
}

/* =========================================================================
 * Single-block encode: msg bytes → Q-domain codeword (32 uint16 values)
 * Matching RTL scloud_msgfunc_param encode path.
 * ========================================================================= */

void hal_sw_msgencode_block(const uint8_t *msg_bytes, int tau,
                         uint16_t *enc_q_flat) {
    Complex v[SCLOUD_BW_COMPLEX];
    labeling_compute_v(msg_bytes, tau, v);
    labeling_compute_w(v, 12, tau, enc_q_flat);
}

/* =========================================================================
 * Single-block decode: noisy Q-domain → rounded Q + message bytes
 * Matching RTL scloud_msgfunc_param decode path.
 * ========================================================================= */

void hal_sw_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                         uint16_t *rounded_q_flat, uint8_t *msg_bytes) {
    int logq = 12;
    int bwn  = SCLOUD_BW_REAL;  /* 32 */

    /* Load noisy Q values into Complex array */
    Complex enc_msg[SCLOUD_BW_COMPLEX];
    for (int i = 0; i < SCLOUD_BW_COMPLEX; i++) {
        enc_msg[i].real = (int32_t)noisy_q_flat[2 * i];
        enc_msg[i].imag = (int32_t)noisy_q_flat[2 * i + 1];
    }

    /* BDD decode */
    Complex *w_dec = bdd_decode_bwn(enc_msg, bwn, logq, tau);
    if (!w_dec) return;

    /* Recover labels via inverse Barnes-Wall */
    Complex u[SCLOUD_BW_COMPLEX];
    delabeling_recover_w(w_dec, logq, tau, u);

    /* Recover message bytes */
    delabeling_compute_u(u, tau, msg_bytes);

    /* Flatten rounded Q-domain output */
    for (int i = 0; i < SCLOUD_BW_COMPLEX; i++) {
        rounded_q_flat[2 * i]     = (uint16_t)w_dec[i].real;
        rounded_q_flat[2 * i + 1] = (uint16_t)w_dec[i].imag;
    }

    free(w_dec);
}

/* =========================================================================
 * Multi-block encode / decode
 * ========================================================================= */

void hal_sw_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                   uint16_t *matrixM) {
    int mu_bytes  = para->mu / 8;       /* 8 for tau=3, 12 for tau=4 */
    int mu_conut  = para->muConut;       /* 2 or 4 */
    int block_size = SCLOUD_BW_REAL;     /* 32 */

    memset(matrixM, 0, mu_conut * block_size * sizeof(uint16_t));

    for (int i = 0; i < mu_conut; i++) {
        hal_sw_msgencode_block(msg + i * mu_bytes, para->tau,
                            matrixM + i * block_size);
    }
}

int hal_sw_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                  uint8_t *msg) {
    int mu_bytes  = para->mu / 8;
    int mu_conut  = para->muConut;
    int block_size = SCLOUD_BW_REAL;

    for (int i = 0; i < mu_conut; i++) {
        uint16_t rounded[SCLOUD_BW_REAL];
        hal_sw_msgdecode_block(matrixM + i * block_size, para->tau,
                            rounded, msg + i * mu_bytes);
    }

    return 0;
}
