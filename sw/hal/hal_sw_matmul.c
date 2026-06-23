/*
 * hal_sw_matmul.c — Pure-C functional model of the SCLOUD+ matrix multiply
 * accelerator. Bit-exact with the RTL (scloudplus_matmul_serial +
 * scloudplus_bmm_block + scloudplus_bmm_pe).
 *
 * This implements both block-level (matching RTL cycle behavior) and
 * matrix-level (full KEM operations) functions.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../include/scloudplus_hal.h"
#include "../src/scloudplus_util_sw.h"

/* =========================================================================
 * Internal helpers
 * ========================================================================= */

/* Compute Q-mask: (1 << q_active) - 1, clamped to Q_WIDTH bits */
static inline uint16_t q_mask(int q_active) {
    if (q_active >= SCLOUD_Q_WIDTH) return SCLOUD_MOD_Q;
    return (1u << q_active) - 1;
}

/* Index into flat-packed A/C block: element (row, col), each Q_WIDTH bits */
static inline int ac_idx(int row, int col, int b) {
    return (row * b + col);
}

/* Index into flat-packed S block: element (row, col), each 2 bits.
 * Returns pointer to the byte containing the 2-bit field and the shift. */
static inline void s_idx(int row, int col, int b, int *byte_off, int *bit_off) {
    int bit = (row * b + col) * 2;
    *byte_off = bit / 8;
    *bit_off = bit % 8;
}

/* Extract a 2-bit S coefficient from the packed byte array.
 * Returns the ternary value: 00→0, 01→+1, 10→-1, 11→-1 (signed2) or 0 */
static inline int s_extract(const uint8_t *s_packed, int row, int col, int b,
                            int coeff_mode) {
    int byte_off, bit_off;
    s_idx(row, col, b, &byte_off, &bit_off);
    uint8_t val = (s_packed[byte_off] >> bit_off) & 0x03;
    switch (coeff_mode) {
        case 0: /* MODE_TERNARY */
            if (val == 0x01) return 1;
            if (val == 0x02) return -1;
            return 0;
        case 1: /* MODE_BINARY */
            return (val & 0x01) ? 1 : 0;
        case 2: /* MODE_SIGNED2 */
            if (val == 0x01) return 1;
            if (val == 0x02) return -2;
            if (val == 0x03) return -1;
            return 0;
        default:
            if (val == 0x01) return 1;
            if (val == 0x02) return -1;
            return 0;
    }
}

/* =========================================================================
 * Block-level multiply: C = A * S  (B×B blocks)
 * Matching RTL scloudplus_bmm_block + scloudplus_bmm_pe
 * ========================================================================= */

void hal_sw_bmm_block(const uint16_t *a_block, const uint8_t *s_block,
                   uint16_t *c_block,
                   int b_active, int q_active, int coeff_mode) {
    const int B = SCLOUD_BLOCK_SIZE;
    uint16_t mask = q_mask(q_active);

    for (int row = 0; row < B; row++) {
        for (int col = 0; col < B; col++) {
            if (row >= b_active || col >= b_active) {
                c_block[ac_idx(row, col, B)] = 0;
                continue;
            }

            /* Dot product: sum over k of A[row][k] * S[k][col] */
            int32_t sum = 0;
            for (int k = 0; k < B; k++) {
                if (k >= b_active) continue;
                uint16_t a_val = a_block[ac_idx(row, k, B)] & mask;
                int s_val = s_extract(s_block, k, col, B, coeff_mode);
                sum += (int32_t)a_val * s_val;
            }
            /* Truncate to Q_WIDTH bits (mod 2^q) */
            c_block[ac_idx(row, col, B)] = (uint16_t)(sum & mask);
        }
    }
}

/* =========================================================================
 * Block-scheduled matrix multiply (matching RTL scloudplus_matmul_serial)
 *
 * Splits matrices into B×B blocks and sequences through them using the
 * same (row, inner, col) triple-loop order as the RTL scheduler.
 * ========================================================================= */

int hal_sw_matmul_serial(const uint16_t *A, const int16_t *S,
                      uint16_t *C,
                      int m_rows, int n_inner, int p_cols,
                      int b_active, int q_active, int coeff_mode) {
    const int B = SCLOUD_BLOCK_SIZE;
    uint16_t mask = q_mask(q_active);

    /* Block counts (ceiling division) */
    int row_blocks   = (m_rows + B - 1) / B;
    int inner_blocks = (n_inner + B - 1) / B;
    int col_blocks   = (p_cols + B - 1) / B;

    /* Zero output */
    memset(C, 0, m_rows * p_cols * sizeof(uint16_t));

    /* RTL scheduling order: for each row_block, for each col_block,
     * accumulate over inner_blocks, then emit */
    for (int rb = 0; rb < row_blocks; rb++) {
        int r_start = rb * B;
        int r_end   = (rb + 1 == row_blocks) ? m_rows : r_start + B;
        int r_size  = r_end - r_start;

        for (int cb = 0; cb < col_blocks; cb++) {
            int c_start = cb * B;
            int c_end   = (cb + 1 == col_blocks) ? p_cols : c_start + B;
            int c_size  = c_end - c_start;

            /* Accumulate over inner blocks */
            uint16_t acc[SCLOUD_BLOCK_SIZE * SCLOUD_BLOCK_SIZE];
            memset(acc, 0, sizeof(acc));

            for (int ib = 0; ib < inner_blocks; ib++) {
                int k_start = ib * B;
                int k_end   = (ib + 1 == inner_blocks) ? n_inner : k_start + B;

                /* Extract A block: r_size × (k_end-k_start), zero-padded to B×B */
                uint16_t a_blk[SCLOUD_BLOCK_SIZE * SCLOUD_BLOCK_SIZE];
                memset(a_blk, 0, sizeof(a_blk));
                for (int r = 0; r < r_size; r++) {
                    for (int k = 0; k < k_end - k_start; k++) {
                        a_blk[ac_idx(r, k, B)] = A[(r_start + r) * n_inner + (k_start + k)] & mask;
                    }
                }

                /* Extract S block: (k_end-k_start) × c_size, zero-padded to B×B */
                uint8_t s_blk[SCLOUD_BLOCK_SIZE * SCLOUD_BLOCK_SIZE * 2 / 8];
                memset(s_blk, 0, sizeof(s_blk));
                for (int k = 0; k < k_end - k_start; k++) {
                    for (int c = 0; c < c_size; c++) {
                        int16_t sv = S[(k_start + k) * p_cols + (c_start + c)];
                        uint8_t bits;
                        if (sv == 1)       bits = 0x01;
                        else if (sv == -1) bits = 0x02;
                        else               bits = 0x00;
                        /* Pack into s_blk at position (k, c) */
                        int bit = (k * B + c) * 2;
                        int byte_off = bit / 8;
                        int bit_off = bit % 8;
                        s_blk[byte_off] |= (bits << bit_off);
                    }
                }

                /* Compute product block */
                uint16_t prod[SCLOUD_BLOCK_SIZE * SCLOUD_BLOCK_SIZE];
                hal_sw_bmm_block(a_blk, s_blk, prod, B, q_active, coeff_mode);

                /* Accumulate */
                for (int i = 0; i < B * B; i++) {
                    acc[i] = (acc[i] + prod[i]) & mask;
                }
            }

            /* Write accumulated block to output matrix */
            for (int r = 0; r < r_size; r++) {
                for (int c = 0; c < c_size; c++) {
                    C[(r_start + r) * p_cols + (c_start + c)] = acc[ac_idx(r, c, B)];
                }
            }
        }
    }

    return 0;
}

/* =========================================================================
 * S matrix packing helpers: convert int16_t ternary to packed 2-bit format
 * ========================================================================= */

/* Pack ternary S values into flat 2-bit-per-element buffer.
 * s_vals: array of len elements, each in {-1, 0, 1}
 * s_packed: output buffer, must be at least (len*2+7)/8 bytes */
static void pack_ternary_s(const int16_t *s_vals, int len, uint8_t *s_packed) {
    memset(s_packed, 0, (len * 2 + 7) / 8);
    for (int i = 0; i < len; i++) {
        uint8_t bits;
        if (s_vals[i] == 1)       bits = 0x01;
        else if (s_vals[i] == -1) bits = 0x02;
        else                      bits = 0x00;
        int bit = i * 2;
        s_packed[bit / 8] |= (bits << (bit % 8));
    }
}

/* A matrix generation: uses shared sw_generate_a_rows() from scloudplus_util_sw.c.
 * TODO: Replace LCG placeholder with real AES-128-ECB for production. */

/* =========================================================================
 * Matrix-level operations
 * ========================================================================= */

int hal_sw_matmul_as_e(const uint8_t *seedA, const int16_t *S,
                    const uint16_t *E, const ScloudPlusPara *para,
                    uint16_t *B) {
    int m = para->m;
    int n = para->n;
    int nbar = para->nbar;
    const int B_SIZE = SCLOUD_BLOCK_SIZE;

    /* B = E initially */
    memcpy(B, E, m * nbar * sizeof(uint16_t));

    /* Process A in batches of B_SIZE rows */
    int row_blocks = (m + B_SIZE - 1) / B_SIZE;
    int inner_blocks = (n + B_SIZE - 1) / B_SIZE;
    int col_blocks = (nbar + B_SIZE - 1) / B_SIZE;

    for (int rb = 0; rb < row_blocks; rb++) {
        int r_start = rb * B_SIZE;
        int n_rows_batch = (r_start + B_SIZE <= m) ? B_SIZE : (m - r_start);

        /* Generate this batch of A rows */
        uint16_t *a_batch = (uint16_t *)malloc(n_rows_batch * n * sizeof(uint16_t));
        if (!a_batch) return -1;
        sw_generate_a_rows(seedA, r_start, n_rows_batch, n, a_batch);

        /* For each inner block and col block, accumulate */
        for (int cb = 0; cb < col_blocks; cb++) {
            int c_start = cb * B_SIZE;
            int n_cols_batch = (c_start + B_SIZE <= nbar) ? B_SIZE : (nbar - c_start);

            for (int ib = 0; ib < inner_blocks; ib++) {
                int k_start = ib * B_SIZE;
                int n_inner_batch = (k_start + B_SIZE <= n) ? B_SIZE : (n - k_start);

                /* Direct accumulate (no block packing for small batches) */
                for (int r = 0; r < n_rows_batch; r++) {
                    for (int c = 0; c < n_cols_batch; c++) {
                        int32_t sum = 0;
                        for (int k = 0; k < n_inner_batch; k++) {
                            int16_t sv = S[(k_start + k) * nbar + (c_start + c)];
                            sum += (int32_t)a_batch[r * n + (k_start + k)] * sv;
                        }
                        B[(r_start + r) * nbar + (c_start + c)] =
                            (B[(r_start + r) * nbar + (c_start + c)] + (uint16_t)(sum & SCLOUD_MOD_Q)) & SCLOUD_MOD_Q;
                    }
                }
            }
        }
        free(a_batch);
    }
    return 0;
}

int hal_sw_matmul_sa_e(const uint8_t *seedA, const int16_t *S,
                    uint16_t *E, const ScloudPlusPara *para,
                    uint16_t *C) {
    int m = para->m;
    int n = para->n;
    int mbar = para->mbar;

    /* C^T = A^T * S^T + E^T
     * i.e. C^T: n × mbar, A^T: n × m, S^T: m × mbar
     * We compute directly: C[i][j] = E[i][j] + sum_k A[k][i] * S[j][k]
     *                               = E[i][j] + sum_k A[k][i] * S[j][k]
     * This is C = E + S * A where S is mbar×m, A is m×n
     * For each j (0..mbar-1), i (0..n-1): C[j][i] = E[j][i] + sum_k S[j][k] * A[k][i]
     */

    /* C = E initially */
    memcpy(C, E, mbar * n * sizeof(uint16_t));

    /* Generate A column-wise? Actually generate all A then do multiply */
    /* For large matrices, we process A in batches to limit memory */
    const int B_SIZE = SCLOUD_BLOCK_SIZE;

    /* We generate A by rows (as in AS_E) but access transposed for SA_E.
     * Since this is functional anyway, let's generate full A once. */
    uint16_t *A_full = (uint16_t *)malloc(m * n * sizeof(uint16_t));
    if (!A_full) return -1;
    sw_generate_a_rows(seedA, 0, m, n, A_full);

    /* C[j][i] += sum_k S[j][k] * A[k][i]
     * Optimized: loop k outermost so A access is stride-1 (cache-friendly).
     * Skip zero entries in S (ternary matrix is very sparse ~85% zeros). */
    for (int j = 0; j < mbar; j++) {
        for (int k = 0; k < m; k++) {
            int16_t sv = S[j * m + k];
            if (sv == 0) continue;  /* skip zeros — S' is sparse */
            for (int i = 0; i < n; i++) {
                int32_t prod = (int32_t)sv * A_full[k * n + i];
                C[j * n + i] = (C[j * n + i] + (uint16_t)(prod & SCLOUD_MOD_Q)) & SCLOUD_MOD_Q;
            }
        }
    }

    free(A_full);
    return 0;
}

void hal_sw_matmul_sb_e(const int16_t *S, const uint16_t *B,
                     const uint16_t *E, const ScloudPlusPara *para,
                     uint16_t *out) {
    int m = para->m;
    int mbar = para->mbar;
    int nbar = para->nbar;

    /* out = E */
    memcpy(out, E, mbar * nbar * sizeof(uint16_t));

    /* out[i][j] += sum_k S[i][k] * B[k][j] */
    for (int i = 0; i < mbar; i++) {
        for (int j = 0; j < nbar; j++) {
            int32_t sum = 0;
            for (int k = 0; k < m; k++) {
                int16_t sv = S[i * m + k];
                sum += (int32_t)sv * B[k * nbar + j];
            }
            out[i * nbar + j] = (out[i * nbar + j] + (uint16_t)(sum & SCLOUD_MOD_Q)) & SCLOUD_MOD_Q;
        }
    }
}

void hal_sw_matmul_cs(const uint16_t *C1, const int16_t *S,
                   const ScloudPlusPara *para, uint16_t *out) {
    int n = para->n;
    int mbar = para->mbar;
    int nbar = para->nbar;

    memset(out, 0, mbar * nbar * sizeof(uint16_t));

    /* out[i][j] = sum_k C1[i][k] * S[k][j]  (S is n x nbar row-major)
     * Optimized: loop k outermost, skip zeros in sparse ternary S. */
    for (int i = 0; i < mbar; i++) {
        for (int k = 0; k < n; k++) {
            /* Pre-read the column j values? S is sparse — check all nbar cols */
            for (int j = 0; j < nbar; j++) {
                int16_t sv = S[k * nbar + j];
                if (sv == 0) continue;
                out[i * nbar + j] = (out[i * nbar + j] +
                    (uint16_t)(((int32_t)C1[i * n + k] * sv) & SCLOUD_MOD_Q)) & SCLOUD_MOD_Q;
            }
        }
    }
}
