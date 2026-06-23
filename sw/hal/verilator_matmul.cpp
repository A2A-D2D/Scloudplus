/*
 * verilator_matmul.cpp — Verilator C++ wrapper for SCLOUD+ matrix multiply.
 *
 * To use this:
 *   1. Install Verilator 5.x
 *   2. Compile RTL: verilator --cc --exe scloudplus_matmul_serial.v ...
 *   3. Link against the generated Vscloudplus_matmul_serial class
 *
 * When Verilator is not available, the SW backend is used automatically.
 */

#ifdef USE_VERILATOR
#include "Vscloudplus_matmul_serial.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" {
#include "../include/scloudplus_hal.h"
#include "../src/scloudplus_util_sw.h"
}

/*
 * Block-Level MatMul Driver
 *
 * Implements the RTL handshake protocol from scloudplus_matmul_serial:
 *   Idle → (start) → Request → (blk_req_ready) → Wait → (blk_in_valid) →
 *   Accumulate → (last_inner) → Emit → (c_block_ready) → Request/Idle
 */

class VerilatorMatMul {
private:
    Vscloudplus_matmul_serial *top;
    uint64_t tick_count;

public:
    VerilatorMatMul() : top(nullptr), tick_count(0) {}

    int init() {
        top = new Vscloudplus_matmul_serial;
        top->clk = 0;
        top->rst_n = 0;
        top->eval();
        top->clk = 1;
        top->eval();
        top->rst_n = 1;
        top->eval();
        tick_count = 0;
        return 0;
    }

    ~VerilatorMatMul() { delete top; }

    void tick() {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
        tick_count++;
    }

    /*
     * Run a full matrix multiply:
     *   A: m_rows × n_inner, uint16_t row-major
     *   S: n_inner × p_cols, int16_t row-major (ternary: -1, 0, 1)
     *   C: m_rows × p_cols, uint16_t output row-major
     */
    int run_matmul(const uint16_t *A, const int16_t *S,
                   uint16_t *C,
                   int m_rows, int n_inner, int p_cols,
                   int b_active, int q_active, int coeff_mode) {
        const int B = 8;

        int row_blocks   = (m_rows + B - 1) / B;
        int inner_blocks = (n_inner + B - 1) / B;
        int col_blocks   = (p_cols + B - 1) / B;

        /* Safety: zero blocks degenerate to 1 */
        if (row_blocks < 1)   row_blocks = 1;
        if (inner_blocks < 1) inner_blocks = 1;
        if (col_blocks < 1)   col_blocks = 1;

        /* Configure */
        top->cfg_b_active    = b_active;
        top->cfg_q_active    = q_active;
        top->cfg_coeff_mode  = coeff_mode;
        top->cfg_row_blocks   = row_blocks;
        top->cfg_inner_blocks = inner_blocks;
        top->cfg_col_blocks   = col_blocks;
        top->start = 0;
        top->blk_in_valid = 0;
        top->c_block_ready = 0;
        top->blk_req_ready = 0;

        /* Reset */
        top->rst_n = 0; tick();
        top->rst_n = 1; tick();

        /* Start */
        top->start = 1; tick();
        top->start = 0;

        /* Drive the handshake protocol */
        bool done = false;
        int block_count = 0;
        int emit_count = 0;

        memset(C, 0, m_rows * p_cols * sizeof(uint16_t));

        while (!done) {
            tick();

            /* Block request */
            if (top->blk_req_valid) {
                int rb = top->a_row_blk;
                int ib = top->a_col_blk;
                int cb = top->s_col_blk;

                uint64_t a_packed[12] = {0};
                uint32_t s_packed[4] = {0};

                int r_start = rb * B, r_end = (r_start + B < m_rows) ? r_start + B : m_rows;
                int k_start = ib * B, k_end = (k_start + B < n_inner) ? k_start + B : n_inner;
                int c_start = cb * B, c_end = (c_start + B < p_cols) ? c_start + B : p_cols;

                for (int r = 0; r < r_end - r_start; r++) {
                    for (int k = 0; k < k_end - k_start; k++) {
                        uint64_t val = A[(r_start + r) * n_inner + (k_start + k)] & 0xFFF;
                        int bit = (r * B + k) * 12;
                        int qword = bit / 64, shift = bit % 64;
                        a_packed[qword] |= (val << shift);
                        if (shift > 52) {
                            a_packed[qword + 1] |= (val >> (64 - shift));
                        }
                    }
                }

                for (int k = 0; k < k_end - k_start; k++) {
                    for (int c = 0; c < c_end - c_start; c++) {
                        int16_t sv = S[(k_start + k) * p_cols + (c_start + c)];
                        uint32_t bits = (sv == 1) ? 0x01 : ((sv == -1) ? 0x02 : 0x00);
                        int bit = (k * B + c) * 2;
                        s_packed[bit / 32] |= (bits << (bit % 32));
                    }
                }

                for (int i = 0; i < 12; i++)
                    ((uint64_t*)(&top->a_block))[i] = a_packed[i];
                for (int i = 0; i < 4; i++)
                    ((uint32_t*)(&top->s_block))[i] = s_packed[i];

                top->blk_req_ready = 1;
                block_count++;
            } else {
                top->blk_req_ready = 0;
            }

            /* Wait state: data transfer */
            if (top->blk_in_ready) {
                top->blk_in_valid = 1;
            } else {
                top->blk_in_valid = 0;
            }

            /* Emit state: capture C block */
            if (top->c_block_valid) {
                int rb = top->c_row_blk;
                int cb = top->c_col_blk;
                int r_start = rb * B, c_start = cb * B;

                for (int r = 0; r < B && (r_start + r) < m_rows; r++) {
                    for (int c = 0; c < B && (c_start + c) < p_cols; c++) {
                        int bit = (r * B + c) * 12;
                        int qword = bit / 64, shift = bit % 64;
                        uint64_t val = ((uint64_t*)(&top->c_block))[qword];
                        C[(r_start + r) * p_cols + (c_start + c)] =
                            (uint16_t)((val >> shift) & 0xFFF);
                    }
                }
                top->c_block_ready = 1;
                emit_count++;
            } else {
                top->c_block_ready = 0;
            }

            done = top->done;
        }

        printf("[Verilator MatMul] Completed: %d blocks requested, "
               "%d emitted, %llu ticks\n",
               block_count, emit_count, (unsigned long long)tick_count);
        return 0;
    }
};

/* =========================================================================
 * C-callable wrappers
 * ========================================================================= */

extern "C" {

static VerilatorMatMul *vlt_matmul = nullptr;

/* Override weak default to signal Verilator availability */
int _hal_vlt_available = 1;

int hal_vlt_matmul_init(void) {
    if (!vlt_matmul) {
        vlt_matmul = new VerilatorMatMul();
        return vlt_matmul->init();
    }
    return 0;
}

void hal_vlt_matmul_deinit(void) {
    delete vlt_matmul;
    vlt_matmul = nullptr;
}

/* =========================================================================
 * hal_vlt_matmul_as_e — B = A*S + E  (KeyGen)
 *
 * Process A in row batches of B=8 to limit memory.
 * ========================================================================= */

int hal_vlt_matmul_as_e(const uint8_t *seedA, const int16_t *S,
                         const uint16_t *E, const ScloudPlusPara *para,
                         uint16_t *B) {
    const int B_SIZE = SCLOUD_BLOCK_SIZE;
    int m = para->m, n = para->n, nbar = para->nbar;

    /* B = E initially (noise) */
    memcpy(B, E, m * nbar * sizeof(uint16_t));

    int row_blocks = (m + B_SIZE - 1) / B_SIZE;

    for (int rb = 0; rb < row_blocks; rb++) {
        int r_start = rb * B_SIZE;
        int n_rows = (r_start + B_SIZE <= m) ? B_SIZE : (m - r_start);

        /* Generate A rows for this batch */
        uint16_t *a_batch = (uint16_t *)malloc(n_rows * n * sizeof(uint16_t));
        if (!a_batch) return -1;
        sw_generate_a_rows(seedA, r_start, n_rows, n, a_batch);

        /* Compute A_batch * S via Verilator */
        uint16_t *prod = (uint16_t *)calloc(n_rows * nbar, sizeof(uint16_t));
        if (!prod) { free(a_batch); return -1; }
        vlt_matmul->run_matmul(a_batch, S, prod, n_rows, n, nbar,
                               B_SIZE, SCLOUD_Q_WIDTH, 0);

        /* Accumulate into B */
        for (int i = 0; i < n_rows * nbar; i++) {
            B[r_start * nbar + i] =
                (B[r_start * nbar + i] + prod[i]) & SCLOUD_MOD_Q;
        }

        free(a_batch);
        free(prod);
    }
    return 0;
}

/* =========================================================================
 * hal_vlt_matmul_sa_e — C = S'*A + E  (Encaps C1)
 *
 * S' is mbar×m (ternary), A is m×n (Q-domain).
 * We compute C^T = A^T * S'^T using the RTL, then transpose back.
 * ========================================================================= */

int hal_vlt_matmul_sa_e(const uint8_t *seedA, const int16_t *S,
                         uint16_t *E, const ScloudPlusPara *para,
                         uint16_t *C) {
    const int B_SIZE = SCLOUD_BLOCK_SIZE;
    int m = para->m, n = para->n, mbar = para->mbar;

    /* Generate full A (m × n) */
    uint16_t *A_full = (uint16_t *)malloc(m * n * sizeof(uint16_t));
    if (!A_full) return -1;
    sw_generate_a_rows(seedA, 0, m, n, A_full);

    /* Transpose A: A_T[n × m] = A^T */
    uint16_t *A_T = (uint16_t *)malloc(n * m * sizeof(uint16_t));
    if (!A_T) { free(A_full); return -1; }
    for (int i = 0; i < n; i++)
        for (int j = 0; j < m; j++)
            A_T[i * m + j] = A_full[j * n + i];

    /* Transpose S': S_T[m × mbar] = S'^T, S' is mbar×m ternary */
    int16_t *S_T = (int16_t *)malloc(m * mbar * sizeof(int16_t));
    if (!S_T) { free(A_full); free(A_T); return -1; }
    for (int i = 0; i < mbar; i++)
        for (int j = 0; j < m; j++)
            S_T[j * mbar + i] = S[i * m + j];

    /* C_T = A_T * S_T  (n × mbar) */
    uint16_t *C_T = (uint16_t *)calloc(n * mbar, sizeof(uint16_t));
    if (!C_T) { free(A_full); free(A_T); free(S_T); return -1; }
    vlt_matmul->run_matmul(A_T, S_T, C_T, n, m, mbar,
                           B_SIZE, SCLOUD_Q_WIDTH, 0);

    /* C[mbar × n] = E + C_T^T */
    for (int i = 0; i < mbar; i++)
        for (int j = 0; j < n; j++)
            C[i * n + j] = (E[i * n + j] + C_T[j * mbar + i]) & SCLOUD_MOD_Q;

    free(A_full); free(A_T); free(S_T); free(C_T);
    return 0;
}

/* =========================================================================
 * hal_vlt_matmul_sb_e — out = S'*B + E  (Encaps C2)
 *
 * S' is mbar×m (ternary), B is m×nbar (Q-domain).
 * Use transpose trick: C^T = B^T * S'^T.
 * ========================================================================= */

void hal_vlt_matmul_sb_e(const int16_t *S, const uint16_t *B_mat,
                          const uint16_t *E, const ScloudPlusPara *para,
                          uint16_t *out) {
    const int B_SIZE = SCLOUD_BLOCK_SIZE;
    int m = para->m, mbar = para->mbar, nbar = para->nbar;

    /* Transpose B: B_T[nbar × m] = B^T, B is m×nbar Q-domain */
    uint16_t *B_T = (uint16_t *)malloc(nbar * m * sizeof(uint16_t));
    if (!B_T) return;
    for (int i = 0; i < nbar; i++)
        for (int j = 0; j < m; j++)
            B_T[i * m + j] = B_mat[j * nbar + i];

    /* Transpose S': S_T[m × mbar] = S'^T, S' is mbar×m ternary */
    int16_t *S_T = (int16_t *)malloc(m * mbar * sizeof(int16_t));
    if (!S_T) { free(B_T); return; }
    for (int i = 0; i < mbar; i++)
        for (int j = 0; j < m; j++)
            S_T[j * mbar + i] = S[i * m + j];

    /* C_T = B_T * S_T  (nbar × mbar) */
    uint16_t *C_T = (uint16_t *)calloc(nbar * mbar, sizeof(uint16_t));
    if (!C_T) { free(B_T); free(S_T); return; }
    vlt_matmul->run_matmul(B_T, S_T, C_T, nbar, m, mbar,
                           B_SIZE, SCLOUD_Q_WIDTH, 0);

    /* out[mbar × nbar] = E + C_T^T */
    for (int i = 0; i < mbar; i++)
        for (int j = 0; j < nbar; j++)
            out[i * nbar + j] = (E[i * nbar + j] + C_T[j * mbar + i]) & SCLOUD_MOD_Q;

    free(B_T); free(S_T); free(C_T);
}

/* =========================================================================
 * hal_vlt_matmul_cs — out = C1*S  (Decaps temp)
 *
 * C1 is mbar×n (Q-domain), S is n×nbar (ternary).
 * Direct fit for RTL: A=C1, S=S, result=mbar×nbar.
 * ========================================================================= */

void hal_vlt_matmul_cs(const uint16_t *C1, const int16_t *S,
                        const ScloudPlusPara *para, uint16_t *out) {
    const int B_SIZE = SCLOUD_BLOCK_SIZE;
    int mbar = para->mbar, n = para->n, nbar = para->nbar;

    vlt_matmul->run_matmul(C1, S, out, mbar, n, nbar,
                           B_SIZE, SCLOUD_Q_WIDTH, 0);
}

} /* extern "C" */

#endif /* USE_VERILATOR */
