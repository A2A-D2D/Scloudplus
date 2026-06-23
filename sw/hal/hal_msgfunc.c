/*
 * hal_msgfunc.c — MsgFunc HAL dispatch layer.
 * Routes calls to the active backend (SW functional model or Verilator).
 */

#include <stdio.h>
#include "../include/scloudplus_hal.h"

extern int hal_active_backend;  /* defined in hal_matmul.c */
#define HAL_BACKEND_SW        0
#define HAL_BACKEND_VERILATOR 1

/* Verilator availability flag — strong symbol defined in verilator_msgfunc.cpp */
__attribute__((weak))
int _hal_vlt_msgfunc_available = 0;

/* SW backend */
extern void hal_sw_msgencode_block(const uint8_t *msg_bytes, int tau,
                                    uint16_t *enc_q_flat);
extern void hal_sw_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                                    uint16_t *rounded_q_flat, uint8_t *msg_bytes);
extern void hal_sw_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                              uint16_t *matrixM);
extern int  hal_sw_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                              uint8_t *msg);

/* Verilator backend (strong symbols from verilator_msgfunc.cpp when linked) */
#ifdef USE_VERILATOR
extern int  hal_vlt_msgfunc_init(void);
extern void hal_vlt_msgfunc_deinit(void);
extern void hal_vlt_msgencode_block(const uint8_t *msg_bytes, int tau,
                                     uint16_t *enc_q_flat);
extern void hal_vlt_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                                     uint16_t *rounded_q_flat, uint8_t *msg_bytes);
extern void hal_vlt_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                               uint16_t *matrixM);
extern int  hal_vlt_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                               uint8_t *msg);
#else
/* Weak stubs when USE_VERILATOR is not defined */
__attribute__((weak))
int  hal_vlt_msgfunc_init(void) { return -1; }
__attribute__((weak))
void hal_vlt_msgfunc_deinit(void) {}
__attribute__((weak))
void hal_vlt_msgencode_block(const uint8_t *msg_bytes, int tau,
                              uint16_t *enc_q_flat) {}
__attribute__((weak))
void hal_vlt_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                              uint16_t *rounded_q_flat, uint8_t *msg_bytes) {}
__attribute__((weak))
void hal_vlt_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                        uint16_t *matrixM) {}
__attribute__((weak))
int  hal_vlt_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                        uint8_t *msg) { return -1; }
#endif

static int verilator_msgfunc_available(void) {
    return _hal_vlt_msgfunc_available;
}

void hal_msgencode_block(const uint8_t *msg_bytes, int tau,
                         uint16_t *enc_q_flat) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_msgfunc_available()) {
        hal_vlt_msgencode_block(msg_bytes, tau, enc_q_flat);
        return;
    }
    hal_sw_msgencode_block(msg_bytes, tau, enc_q_flat);
}

void hal_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                         uint16_t *rounded_q_flat, uint8_t *msg_bytes) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_msgfunc_available()) {
        hal_vlt_msgdecode_block(noisy_q_flat, tau, rounded_q_flat, msg_bytes);
        return;
    }
    hal_sw_msgdecode_block(noisy_q_flat, tau, rounded_q_flat, msg_bytes);
}

void hal_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                   uint16_t *matrixM) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_msgfunc_available()) {
        hal_vlt_msgencode(msg, para, matrixM);
        return;
    }
    hal_sw_msgencode(msg, para, matrixM);
}

int hal_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                  uint8_t *msg) {
    if (hal_active_backend == HAL_BACKEND_VERILATOR && verilator_msgfunc_available()) {
        return hal_vlt_msgdecode(matrixM, para, msg);
    }
    return hal_sw_msgdecode(matrixM, para, msg);
}
