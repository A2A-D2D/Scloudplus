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
        const int B = 8;  /* SCLOUD_BLOCK_SIZE */

        int row_blocks   = (m_rows + B - 1) / B;
        int inner_blocks = (n_inner + B - 1) / B;
        int col_blocks   = (p_cols + B - 1) / B;

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

        while (!done) {
            tick();

            /* Block request */
            if (top->blk_req_valid) {
                int rb = top->a_row_blk;
                int ib = top->a_col_blk;  /* inner block index */
                int cb = top->s_col_blk;

                /* Provide A and S blocks for this request */
                uint64_t a_packed[12];    /* 8*8*12 = 768 bits = 12 uint64 */
                uint32_t s_packed[4];     /* 8*8*2 = 128 bits = 4 uint32 */
                memset(a_packed, 0, sizeof(a_packed));
                memset(s_packed, 0, sizeof(s_packed));

                int r_start = rb * B, r_end = (r_start + B < m_rows) ? r_start + B : m_rows;
                int k_start = ib * B, k_end = (k_start + B < n_inner) ? k_start + B : n_inner;
                int c_start = cb * B, c_end = (c_start + B < p_cols) ? c_start + B : p_cols;

                for (int r = 0; r < r_end - r_start; r++) {
                    for (int k = 0; k < k_end - k_start; k++) {
                        uint64_t val = A[(r_start + r) * n_inner + (k_start + k)] & 0xFFF;
                        int bit = (r * B + k) * 12;
                        int qword = bit / 64, shift = bit % 64;
                        a_packed[qword] |= (val << shift);
                        if (shift > 52) { /* spans two qwords */
                            a_packed[qword + 1] |= (val >> (64 - shift));
                        }
                    }
                }

                for (int k = 0; k < k_end - k_start; k++) {
                    for (int c = 0; c < c_end - c_start; c++) {
                        int16_t sv = S[(k_start + k) * p_cols + (c_start + c)];
                        uint8_t bits = (sv == 1) ? 0x01 : ((sv == -1) ? 0x02 : 0x00);
                        int bit = (k * B + c) * 2;
                        s_packed[bit / 32] |= (bits << (bit % 32));
                    }
                }

                /* Set a_block and s_block on the DUT */
                for (int i = 0; i < 12; i++) {
                    /* top->a_block is 768 bits wide, set through DataSeg */
                    ((uint64_t*)(&top->a_block))[i] = a_packed[i];
                }
                for (int i = 0; i < 4; i++) {
                    ((uint32_t*)(&top->s_block))[i] = s_packed[i];
                }

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

                /* Extract C block from packed 768-bit bus */
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

/* C-callable wrapper */
extern "C" {

static VerilatorMatMul *vlt_matmul = nullptr;

int hal_vlt_matmul_init(void) {
    vlt_matmul = new VerilatorMatMul();
    return vlt_matmul->init();
}

void hal_vlt_matmul_deinit(void) {
    delete vlt_matmul;
    vlt_matmul = nullptr;
}

int hal_vlt_matmul_as_e(const uint8_t *seedA, const int16_t *S,
                         const uint16_t *E, const ScloudPlusPara *para,
                         uint16_t *B) {
    /* TODO: Full AS_E with Verilator */
    return -1;
}

int hal_vlt_matmul_sa_e(const uint8_t *seedA, const int16_t *S,
                         uint16_t *E, const ScloudPlusPara *para,
                         uint16_t *C) {
    /* TODO: Full SA_E with Verilator */
    return -1;
}

void hal_vlt_matmul_sb_e(const int16_t *S, const uint16_t *B_mat,
                          const uint16_t *E, const ScloudPlusPara *para,
                          uint16_t *out) {
    /* TODO: Full SB_E with Verilator */
}

void hal_vlt_matmul_cs(const uint16_t *C1, const int16_t *S,
                        const ScloudPlusPara *para, uint16_t *out) {
    /* TODO: Full CS with Verilator */
}

} /* extern "C" */

#endif /* USE_VERILATOR */
