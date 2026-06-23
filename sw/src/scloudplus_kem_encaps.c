/*
 * scloudplus_kem_encaps.c — SCLOUD+ Encapsulation.
 *
 * Steps:
 *   1. Unpack public key B
 *   2. Generate randomness: r, msg, seeds
 *   3. Sample S' (mbar × m, ternary) via SamplePhi
 *   4. Sample noise E1 (mbar × n), E2 (mbar × nbar) via SampleEta2
 *   5. Compute C1 = S' * A + E1  (HAL-accelerated)
 *   6. Compute C2 = S' * B + E2  (HAL-accelerated)
 *   7. Encode message: M = MsgEncode(msg) (HAL-accelerated)
 *   8. C2 = C2 + M
 *   9. Compress and pack C1, C2
 *   10. Derive shared secret via KDF
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "scloudplus_util_sw.h"
#include "../include/scloudplus_kem.h"

extern void get_random(uint8_t *buf, int len);

int scloudplus_encaps(const uint8_t *pk, uint16_t pk_len,
                      uint8_t *ct, uint16_t *ct_len,
                      uint8_t *ss, uint16_t *ss_len,
                      const ScloudPlusPara *para) {
    int m = para->m, n = para->n, mbar = para->mbar, nbar = para->nbar;
    int mu_bytes  = para->mu / 8;
    int mu_conut  = para->muConut;
    int total_msg = mu_bytes * mu_conut;

    uint8_t seedA[SCLOUD_SEED_A_LEN];
    uint8_t seed_se_r[SCLOUD_SEED_R1_LEN];
    uint8_t seed_E_r[SCLOUD_SEED_R2_LEN];
    uint8_t msg[48];  /* max: ss=32 → 4*12=48 bytes */

    /* 1. Unpack public key (seedA is at end of pk) */
    uint16_t *B = (uint16_t *)calloc(m * nbar, sizeof(uint16_t));
    if (!B) return -1;
    int pk_mat_len = (m * nbar * 3 + 1) / 2;
    sw_unpack_pk(pk, para, B);
    memcpy(seedA, pk + pk_mat_len, SCLOUD_SEED_A_LEN);
    (void)pk_len;

    /* 2. Generate randomness */
    get_random(seed_se_r, SCLOUD_SEED_R1_LEN);
    get_random(seed_E_r, SCLOUD_SEED_R2_LEN);
    get_random(msg, total_msg);

    /* 3. Sample S' */
    int16_t *S_prime = (int16_t *)calloc(mbar * m, sizeof(int16_t));
    if (!S_prime) { free(B); return -1; }
    sw_sample_phi(seed_se_r, para, S_prime);

    /* 4. Sample noise */
    uint16_t *E1 = (uint16_t *)calloc(mbar * n, sizeof(uint16_t));
    uint16_t *E2 = (uint16_t *)calloc(mbar * nbar, sizeof(uint16_t));
    if (!E1 || !E2) { free(B); free(S_prime); free(E1); free(E2); return -1; }
    sw_sample_eta2(seed_E_r, para, E1, E2);

    /* 5. Compute C1 = S' * A + E1 (HAL) */
    uint16_t *C1 = (uint16_t *)calloc(mbar * n, sizeof(uint16_t));
    if (!C1) { free(B); free(S_prime); free(E1); free(E2); return -1; }
    hal_matmul_sa_e(seedA, S_prime, E1, para, C1);

    /* 6. Compute C2 = S' * B + E2 (HAL) */
    uint16_t *C2 = (uint16_t *)calloc(mbar * nbar, sizeof(uint16_t));
    if (!C2) { free(B); free(S_prime); free(E1); free(E2); free(C1); return -1; }
    hal_matmul_sb_e(S_prime, B, E2, para, C2);

    /* 7-8. Encode message and add to C2 */
    uint16_t *matrixM = (uint16_t *)calloc(mu_conut * SCLOUD_BW_REAL, sizeof(uint16_t));
    if (!matrixM) { free(B); free(S_prime); free(E1); free(E2); free(C1); free(C2); return -1; }
    hal_msgencode(msg, para, matrixM);
    sw_add_mod_q(C2, matrixM, mbar * nbar, C2);

    /* 9. Compress and pack */
    uint16_t *c1_comp = (uint16_t *)calloc(mbar * n, sizeof(uint16_t));
    uint16_t *c2_comp = (uint16_t *)calloc(mbar * nbar, sizeof(uint16_t));
    if (!c1_comp || !c2_comp) {
        free(B); free(S_prime); free(E1); free(E2);
        free(C1); free(C2); free(matrixM); free(c1_comp); free(c2_comp);
        return -1;
    }
    sw_compress_c1(C1, para, c1_comp);
    sw_compress_c2(C2, para, c2_comp);

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

    uint8_t *ct1 = (uint8_t *)calloc(c1_packed_len, 1);
    uint8_t *ct2 = (uint8_t *)calloc(c2_packed_len, 1);
    if (!ct1 || !ct2) {
        free(B); free(S_prime); free(E1); free(E2); free(C1); free(C2);
        free(matrixM); free(c1_comp); free(c2_comp); free(ct1); free(ct2);
        return -1;
    }
    sw_pack_c1(c1_comp, para, ct1);
    sw_pack_c2(c2_comp, para, ct2);

    /* Concatenate ct = ct1 || ct2 */
    *ct_len = (uint16_t)(c1_packed_len + c2_packed_len);
    memcpy(ct, ct1, c1_packed_len);
    memcpy(ct + c1_packed_len, ct2, c2_packed_len);

    /* 10. Derive shared secret: SS = SHAKE256(msg, 32) */
    *ss_len = 32;
    sw_shake256_hash(msg, total_msg, ss, 32);

    /* Cleanup */
    free(B); free(S_prime); free(E1); free(E2); free(C1); free(C2);
    free(matrixM); free(c1_comp); free(c2_comp); free(ct1); free(ct2);
    return 0;
}
