/*
 * scloudplus_util_sw.h — Internal SW utility functions for SCLOUD+ KEM.
 *
 * These are standard C reimplementations of the openHiTLS utility functions
 * that are NOT hardware-accelerated (kept in software).
 */

#ifndef SCLOUDPLUS_UTIL_SW_H
#define SCLOUDPLUS_UTIL_SW_H

#include <stdint.h>
#include "../include/scloudplus_hal.h"

#ifdef __cplusplus
extern "C" {
#endif

/* =========================================================================
 * Constants
 * ========================================================================= */

#define SCLOUD_MOD_Q           0xFFF
#define SCLOUD_ALPHA_LEN       32
#define SCLOUD_SEED_A_LEN      16
#define SCLOUD_SEED_R1_LEN     32
#define SCLOUD_SEED_R2_LEN     32
#define SCLOUD_SEED_K_LEN      32
#define SCLOUD_RAND_R_LEN      32
#define SCLOUD_RAND_Z_LEN      32
#define SCLOUD_HPK_LEN         32

/* =========================================================================
 * SHAKE256 / Hash wrapper
 *
 * This is a minimal SHAKE256 implementation using the public-domain
 * Keccak (SHA-3) code. For production use, link against OpenSSL.
 * For this functional model, we provide a simple portable implementation.
 * ========================================================================= */

/* Initialize SHAKE256 context */
void *sw_shake256_new(void);
void  sw_shake256_free(void *ctx);
int   sw_shake256_init(void *ctx);
int   sw_shake256_update(void *ctx, const uint8_t *data, uint32_t len);
int   sw_shake256_squeeze(void *ctx, uint8_t *out, uint32_t out_len);
int   sw_shake256_final(void *ctx, uint8_t *out, uint32_t *out_len);

/* Convenience: SHAKE256(msg, len) → output of arbitrary length */
int sw_shake256_hash(const uint8_t *input, uint32_t in_len,
                     uint8_t *output, uint32_t out_len);

/* Convenience: SHA3-256 for KDF */
int sw_sha3_256(const uint8_t *input, uint32_t in_len, uint8_t output[32]);

/* =========================================================================
 * AES-128-ECB (for deterministic A matrix expansion)
 *
 * For the functional model we use a lightweight placeholder.
 * Replace with OpenSSL EVP for production.
 * ========================================================================= */

void *sw_aes128_ecb_new(void);
void  sw_aes128_ecb_free(void *ctx);
int   sw_aes128_ecb_init(void *ctx, const uint8_t key[16], int encrypt);
int   sw_aes128_ecb_update(void *ctx, const uint8_t *in, uint32_t in_len,
                            uint8_t *out, uint32_t *out_len);

/* =========================================================================
 * A matrix generation (shared between SW and Verilator backends)
 *
 * Deterministic row generation from seedA. Uses LCG placeholder;
 * replace with AES-128-ECB for production.
 * ========================================================================= */

void sw_generate_a_rows(const uint8_t *seedA, int row_start, int n_rows,
                         int n_cols, uint16_t *a_out);

/* =========================================================================
 * Pack / Unpack functions
 * ========================================================================= */

/* PackPK: m×nbar uint16 → byte array (12-bit → 3 bytes per 2 values) */
void sw_pack_pk(const uint16_t *B, const ScloudPlusPara *para, uint8_t *pk);
void sw_unpack_pk(const uint8_t *pk, const ScloudPlusPara *para, uint16_t *B);

/* PackSK: n×nbar ternary int16 → byte array (2-bit per value) */
void sw_pack_sk(const int16_t *S, const ScloudPlusPara *para, uint8_t *sk);
void sw_unpack_sk(const uint8_t *sk, const ScloudPlusPara *para, int16_t *S);

/* PackC1/UnPackC1 */
void sw_pack_c1(const uint16_t *C, const ScloudPlusPara *para, uint8_t *out);
void sw_unpack_c1(const uint8_t *in, const ScloudPlusPara *para, uint16_t *C);

/* PackC2/UnPackC2 */
void sw_pack_c2(const uint16_t *C, const ScloudPlusPara *para, uint8_t *out);
void sw_unpack_c2(const uint8_t *in, const ScloudPlusPara *para, uint16_t *C);

/* =========================================================================
 * Compress / Decompress functions
 * ========================================================================= */

void sw_compress_c1(const uint16_t *C, const ScloudPlusPara *para, uint16_t *out);
void sw_decompress_c1(const uint16_t *in, const ScloudPlusPara *para, uint16_t *C);
void sw_compress_c2(const uint16_t *C, const ScloudPlusPara *para, uint16_t *out);
void sw_decompress_c2(const uint16_t *in, const ScloudPlusPara *para, uint16_t *C);

/* =========================================================================
 * Arithmetic helpers (mod 2^12)
 * ========================================================================= */

void sw_add_mod_q(const uint16_t *a, const uint16_t *b, int len, uint16_t *out);
void sw_sub_mod_q(const uint16_t *a, const uint16_t *b, int len, uint16_t *out);
int  sw_verify(const uint8_t *a, const uint8_t *b, int len);

/* =========================================================================
 * Sampling functions (SHAKE-based CBD)
 * ========================================================================= */

/* SamplePsi: sample ternary S (n × nbar) with h1 nonzeros per column */
int sw_sample_psi(const uint8_t *seed, const ScloudPlusPara *para, int16_t *S);

/* SamplePhi: sample ternary S' (mbar × m) with h2 nonzeros per column */
int sw_sample_phi(const uint8_t *seed, const ScloudPlusPara *para, int16_t *S_prime);

/* SampleEta1: sample noise E (m × nbar) */
int sw_sample_eta1(const uint8_t *seed, const ScloudPlusPara *para, uint16_t *E);

/* SampleEta2: sample noise E1 (mbar × n) and E2 (mbar × nbar) */
int sw_sample_eta2(const uint8_t *seed, const ScloudPlusPara *para,
                   uint16_t *E1, uint16_t *E2);

#ifdef __cplusplus
}
#endif

#endif /* SCLOUDPLUS_UTIL_SW_H */
