/*
 * hal_matmul.c — Matmul HAL dispatch layer.
 * Routes calls to the active backend (SW functional model or Verilator).
 */

#include <stdio.h>
#include <string.h>
#include "../include/scloudplus_hal.h"

/* Backend selection (shared with hal_msgfunc.c) */
#define HAL_BACKEND_SW        0
#define HAL_BACKEND_VERILATOR 1
#define HAL_BACKEND_REG       2

int hal_active_backend = HAL_BACKEND_SW;  /* Global, used by hal_msgfunc.c */

/* Verilator availability flag — strong symbol defined in verilator_matmul.cpp */
__attribute__((weak))
int _hal_vlt_available = 0;

/* SW backend (implemented in hal_sw_matmul.c) */
extern void hal_sw_bmm_block(const uint16_t *a_block, const uint8_t *s_block,
                              uint16_t *c_block,
                              int b_active, int q_active, int coeff_mode);
extern int  hal_sw_matmul_serial(const uint16_t *A, const int16_t *S,
                                  uint16_t *C,
                                  int m_rows, int n_inner, int p_cols,
                                  int b_active, int q_active, int coeff_mode);
extern int  hal_sw_matmul_as_e(const uint8_t *seedA, const int16_t *S,
                                const uint16_t *E, const ScloudPlusPara *para,
                                uint16_t *B);
extern int  hal_sw_matmul_sa_e(const uint8_t *seedA, const int16_t *S,
                                uint16_t *E, const ScloudPlusPara *para,
                                uint16_t *C);
extern void hal_sw_matmul_sb_e(const int16_t *S, const uint16_t *B,
                                const uint16_t *E, const ScloudPlusPara *para,
                                uint16_t *out);
extern void hal_sw_matmul_cs(const uint16_t *C1, const int16_t *S,
                              const ScloudPlusPara *para, uint16_t *out);

/* Verilator backend (strong symbols from verilator_matmul.cpp when linked) */
#ifdef USE_VERILATOR
extern int  hal_vlt_matmul_init(void);
extern void hal_vlt_matmul_deinit(void);
extern int  hal_vlt_matmul_as_e(const uint8_t *seedA, const int16_t *S,
                                 const uint16_t *E, const ScloudPlusPara *para,
                                 uint16_t *B);
extern int  hal_vlt_matmul_sa_e(const uint8_t *seedA, const int16_t *S,
                                 uint16_t *E, const ScloudPlusPara *para,
                                 uint16_t *C);
extern void hal_vlt_matmul_sb_e(const int16_t *S, const uint16_t *B,
                                 const uint16_t *E, const ScloudPlusPara *para,
                                 uint16_t *out);
extern void hal_vlt_matmul_cs(const uint16_t *C1, const int16_t *S,
                               const ScloudPlusPara *para, uint16_t *out);
#else
/* Weak stubs when USE_VERILATOR is not defined */
__attribute__((weak))
int hal_vlt_matmul_init(void) { return -1; }
__attribute__((weak))
void hal_vlt_matmul_deinit(void) {}
__attribute__((weak))
int hal_vlt_matmul_as_e(const uint8_t *seedA, const int16_t *S,
                         const uint16_t *E, const ScloudPlusPara *para,
                         uint16_t *B) { return -1; }
__attribute__((weak))
int hal_vlt_matmul_sa_e(const uint8_t *seedA, const int16_t *S,
                         uint16_t *E, const ScloudPlusPara *para,
                         uint16_t *C) { return -1; }
__attribute__((weak))
void hal_vlt_matmul_sb_e(const int16_t *S, const uint16_t *B,
                          const uint16_t *E, const ScloudPlusPara *para,
                          uint16_t *out) {}
__attribute__((weak))
void hal_vlt_matmul_cs(const uint16_t *C1, const int16_t *S,
                        const ScloudPlusPara *para, uint16_t *out) {}
#endif

static int verilator_available(void) {
    return _hal_vlt_available;
}

/* =========================================================================
 * Initialization
 * ========================================================================= */

int hal_init(const char *backend) {
    if (!backend || strcmp(backend, "sw") == 0) {
        hal_active_backend = HAL_BACKEND_SW;
        printf("[HAL] Using SW functional backend\n");
        return 0;
    } else if (strcmp(backend, "verilator") == 0) {
        if (verilator_available()) {
            hal_active_backend = HAL_BACKEND_VERILATOR;
            printf("[HAL] Using Verilator backend\n");
            hal_vlt_matmul_init();
            return 0;
        } else {
            fprintf(stderr, "[HAL] Verilator not available, using SW backend\n");
            hal_active_backend = HAL_BACKEND_SW;
            return 0;
        }
    }
    fprintf(stderr, "[HAL] Unknown backend '%s', using SW\n", backend);
    hal_active_backend = HAL_BACKEND_SW;
    return 0;
}

void hal_deinit(void) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_available()) {
        hal_vlt_matmul_deinit();
    }
}

/* =========================================================================
 * Block-level dispatch
 * ========================================================================= */

void hal_bmm_block(const uint16_t *a_block, const uint8_t *s_block,
                   uint16_t *c_block,
                   int b_active, int q_active, int coeff_mode) {
    hal_sw_bmm_block(a_block, s_block, c_block, b_active, q_active, coeff_mode);
}

int hal_matmul_serial(const uint16_t *A, const int16_t *S,
                      uint16_t *C,
                      int m_rows, int n_inner, int p_cols,
                      int b_active, int q_active, int coeff_mode) {
    return hal_sw_matmul_serial(A, S, C, m_rows, n_inner, p_cols,
                                b_active, q_active, coeff_mode);
}

/* =========================================================================
 * Matrix-level dispatch
 * ========================================================================= */

int hal_matmul_as_e(const uint8_t *seedA, const int16_t *S,
                    const uint16_t *E, const ScloudPlusPara *para,
                    uint16_t *B) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_available()) {
        return hal_vlt_matmul_as_e(seedA, S, E, para, B);
    }
    return hal_sw_matmul_as_e(seedA, S, E, para, B);
}

int hal_matmul_sa_e(const uint8_t *seedA, const int16_t *S,
                    uint16_t *E, const ScloudPlusPara *para,
                    uint16_t *C) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_available()) {
        return hal_vlt_matmul_sa_e(seedA, S, E, para, C);
    }
    return hal_sw_matmul_sa_e(seedA, S, E, para, C);
}

void hal_matmul_sb_e(const int16_t *S, const uint16_t *B,
                     const uint16_t *E, const ScloudPlusPara *para,
                     uint16_t *out) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_available()) {
        hal_vlt_matmul_sb_e(S, B, E, para, out);
        return;
    }
    hal_sw_matmul_sb_e(S, B, E, para, out);
}

void hal_matmul_cs(const uint16_t *C1, const int16_t *S,
                   const ScloudPlusPara *para, uint16_t *out) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_available()) {
        hal_vlt_matmul_cs(C1, S, para, out);
        return;
    }
    hal_sw_matmul_cs(C1, S, para, out);
}
