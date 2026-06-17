/*
 * hal_msgfunc.c — MsgFunc HAL dispatch layer.
 */

#include <stdio.h>
#include "../include/scloudplus_hal.h"

extern int hal_active_backend;  /* defined in hal_matmul.c */
#define HAL_BACKEND_SW 0

/* SW backend */
extern void hal_sw_msgencode_block(const uint8_t *msg_bytes, int tau,
                                    uint16_t *enc_q_flat);
extern void hal_sw_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                                    uint16_t *rounded_q_flat, uint8_t *msg_bytes);
extern void hal_sw_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                              uint16_t *matrixM);
extern int  hal_sw_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                              uint8_t *msg);

void hal_msgencode_block(const uint8_t *msg_bytes, int tau,
                         uint16_t *enc_q_flat) {
    hal_sw_msgencode_block(msg_bytes, tau, enc_q_flat);
}

void hal_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                         uint16_t *rounded_q_flat, uint8_t *msg_bytes) {
    hal_sw_msgdecode_block(noisy_q_flat, tau, rounded_q_flat, msg_bytes);
}

void hal_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                   uint16_t *matrixM) {
    hal_sw_msgencode(msg, para, matrixM);
}

int hal_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                  uint8_t *msg) {
    return hal_sw_msgdecode(matrixM, para, msg);
}
