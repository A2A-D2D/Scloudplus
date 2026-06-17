/*
 * scloudplus_kem_keygen.c — SCLOUD+ Key Generation.
 *
 * Steps:
 *   1. Generate random seeds (seedA, seed_se, seed_E)
 *   2. Sample secret S (n × nbar, ternary) via SamplePsi
 *   3. Sample noise E (m × nbar) via SampleEta1
 *   4. Compute B = A * S + E  (HAL-accelerated matrix multiply)
 *   5. Pack PK = B, SK = S
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "scloudplus_util_sw.h"
#include "../include/scloudplus_kem.h"

extern void get_random(uint8_t *buf, int len);

int scloudplus_init_params(ScloudPlusPara *para, int ss_level) {
    memset(para, 0, sizeof(*para));
    para->ss = (uint8_t)ss_level;
    para->logq = 12;
    para->logq1 = 12;
    para->logq2 = 12;

    if (ss_level == 16) {
        para->m = 600; para->n = 600;
        para->mbar = 8; para->nbar = 8;
        para->h1 = 128; para->h2 = 128;
        para->eta1 = 2; para->eta2 = 2;
        para->tau = 3; para->mu = 64; para->muConut = 2;
    } else if (ss_level == 24) {
        para->m = 928; para->n = 896;
        para->mbar = 8; para->nbar = 8;
        para->h1 = 128; para->h2 = 128;
        para->eta1 = 2; para->eta2 = 2;
        para->tau = 4; para->mu = 96; para->muConut = 2;
    } else if (ss_level == 32) {
        para->m = 1136; para->n = 1120;
        para->mbar = 12; para->nbar = 11;
        para->h1 = 128; para->h2 = 128;
        para->eta1 = 2; para->eta2 = 2;
        para->tau = 3; para->mu = 64; para->muConut = 4;
    } else {
        return -1;
    }
    return 0;
}

int scloudplus_keygen(uint8_t *pk, uint16_t *pk_len,
                      uint8_t *sk, uint16_t *sk_len,
                      const ScloudPlusPara *para) {
    int m = para->m, n = para->n, nbar = para->nbar;
    uint8_t seedA[SCLOUD_SEED_A_LEN];
    uint8_t seed_se[SCLOUD_SEED_R1_LEN];
    uint8_t seed_E[SCLOUD_SEED_R2_LEN];

    /* 1. Generate random seeds */
    get_random(seedA, SCLOUD_SEED_A_LEN);
    get_random(seed_se, SCLOUD_SEED_R1_LEN);
    get_random(seed_E, SCLOUD_SEED_R2_LEN);

    /* 2. Sample secret S */
    int16_t *S = (int16_t *)calloc(n * nbar, sizeof(int16_t));
    if (!S) return -1;
    sw_sample_psi(seed_se, para, S);

    /* 3. Sample noise E */
    uint16_t *E = (uint16_t *)calloc(m * nbar, sizeof(uint16_t));
    if (!E) { free(S); return -1; }
    sw_sample_eta1(seed_E, para, E);

    /* 4. Compute B = A*S + E (HAL-accelerated) */
    uint16_t *B = (uint16_t *)calloc(m * nbar, sizeof(uint16_t));
    if (!B) { free(S); free(E); return -1; }
    hal_matmul_as_e(seedA, S, E, para, B);

    /* 5. Pack keys */
    *pk_len = (uint16_t)((m * nbar * 3 + 1) / 2);  /* ~3600 bytes for ss=16 */
    *sk_len = (uint16_t)((n * nbar + 3) / 4);        /* ~1200 bytes for ss=16 */
    sw_pack_pk(B, para, pk);
    sw_pack_sk(S, para, sk);

    free(S); free(E); free(B);
    return 0;
}
