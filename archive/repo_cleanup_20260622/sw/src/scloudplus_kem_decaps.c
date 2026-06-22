/*
 * scloudplus_kem_decaps.c — SCLOUD+ Decapsulation.
 *
 * Steps:
 *   1. Unpack secret key S
 *   2. Unpack and decompress ciphertext C1, C2
 *   3. Compute temp = C1 * S  (HAL-accelerated)
 *   4. diff = C2 - temp
 *   5. msg' = MsgDecode(diff)  (HAL-accelerated)
 *   6. Re-encrypt msg' and verify against received ct
 *   7. KDF → shared secret
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "scloudplus_util_sw.h"
#include "../include/scloudplus_kem.h"

extern void get_random(uint8_t *buf, int len);

int scloudplus_decaps(const uint8_t *ct, uint16_t ct_len,
                      const uint8_t *sk, uint16_t sk_len,
                      uint8_t *ss, uint16_t *ss_len,
                      const ScloudPlusPara *para) {
    int m = para->m, n = para->n, mbar = para->mbar, nbar = para->nbar;
    int mu_bytes  = para->mu / 8;
    int mu_conut  = para->muConut;
    int total_msg = mu_bytes * mu_conut;

    (void)sk_len;

    /* 1. Unpack secret key */
    int16_t *S = (int16_t *)calloc(n * nbar, sizeof(int16_t));
    if (!S) return -1;
    sw_unpack_sk(sk, para, S);

    /* 2. Unpack and decompress ciphertext */
    /* Determine ct1/ct2 lengths */
    int c1_packed_len, c2_packed_len;
    if (para->ss == 16) {
        c1_packed_len = mbar * n + (mbar * n + 7) / 8;
        c2_packed_len = (mbar * nbar * 7 + 7) / 8;
    } else if (para->ss == 24) {
        c1_packed_len = (mbar * n * 3 + 1) / 2;
        c2_packed_len = (mbar * nbar * 3 + 1) / 2;
    } else { /* ss == 32 */
        c1_packed_len = mbar * n + (mbar * n + 3) / 4;
        c2_packed_len = (mbar * nbar * 7 + 7) / 8;
    }

    const uint8_t *ct1 = ct;
    const uint8_t *ct2 = ct + c1_packed_len;
    (void)ct_len;

    uint16_t *C1_comp = (uint16_t *)calloc(mbar * n, sizeof(uint16_t));
    uint16_t *C2_comp = (uint16_t *)calloc(mbar * nbar, sizeof(uint16_t));
    if (!C1_comp || !C2_comp) { free(S); free(C1_comp); free(C2_comp); return -1; }
    sw_unpack_c1(ct1, para, C1_comp);
    sw_unpack_c2(ct2, para, C2_comp);

    uint16_t *C1 = (uint16_t *)calloc(mbar * n, sizeof(uint16_t));
    uint16_t *C2 = (uint16_t *)calloc(mbar * nbar, sizeof(uint16_t));
    if (!C1 || !C2) {
        free(S); free(C1_comp); free(C2_comp); free(C1); free(C2);
        return -1;
    }
    sw_decompress_c1(C1_comp, para, C1);
    sw_decompress_c2(C2_comp, para, C2);

    /* 3. Compute temp = C1 * S (HAL) */
    uint16_t *CS_result = (uint16_t *)calloc(mbar * nbar, sizeof(uint16_t));
    if (!CS_result) {
        free(S); free(C1_comp); free(C2_comp); free(C1); free(C2);
        return -1;
    }
    hal_matmul_cs(C1, S, para, CS_result);

    /* 4. diff = C2 - temp */
    uint16_t *diff = (uint16_t *)calloc(mbar * nbar, sizeof(uint16_t));
    if (!diff) {
        free(S); free(C1_comp); free(C2_comp); free(C1); free(C2);
        free(CS_result); return -1;
    }
    sw_sub_mod_q(C2, CS_result, mbar * nbar, diff);

    /* 5. Decode message (HAL) */
    uint8_t msg[48];
    hal_msgdecode(diff, para, msg);

    /* 6. Re-encrypt & verify (simplified: just KDF the recovered msg) */
    /* In full FO transform: re-encrypt msg, verify ciphertext matches,
     * return failure if mismatch. For now, always succeed. */

    /* 7. Derive shared secret: SS = SHAKE256(msg, 32) */
    *ss_len = 32;
    sw_shake256_hash(msg, total_msg, ss, 32);

    free(S); free(C1_comp); free(C2_comp); free(C1); free(C2);
    free(CS_result); free(diff);
    return 0;
}
