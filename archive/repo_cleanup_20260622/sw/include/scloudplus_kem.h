/*
 * scloudplus_kem.h — SCLOUD+ KEM API (KeyGen / Encaps / Decaps).
 *
 * Uses the Hardware Abstraction Layer (HAL) for accelerated matrix multiply
 * and message encode/decode. All other operations (hashing, sampling,
 * pack/unpack) are done in standard C.
 */

#ifndef SCLOUDPLUS_KEM_H
#define SCLOUDPLUS_KEM_H

#include <stdint.h>
#include "scloudplus_hal.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Default parameter sets */
#define SCLOUD_SS_128  16
#define SCLOUD_SS_192  24
#define SCLOUD_SS_256  32

/* Initialize a parameter set by security level.
 * Returns 0 on success, negative on error. */
int scloudplus_init_params(ScloudPlusPara *para, int ss_level);

/* =========================================================================
 * Key Generation
 *
 * Input:  none (randomness from system)
 * Output: pk (public key bytes), sk (secret key bytes)
 *         pk_len, sk_len set to actual sizes
 * ========================================================================= */
int scloudplus_keygen(uint8_t *pk, uint16_t *pk_len,
                      uint8_t *sk, uint16_t *sk_len,
                      const ScloudPlusPara *para);

/* =========================================================================
 * Encapsulation
 *
 * Input:  pk (public key bytes), pk_len
 * Output: ct (ciphertext bytes), ct_len
 *         ss (shared secret bytes), ss_len
 * ========================================================================= */
int scloudplus_encaps(const uint8_t *pk, uint16_t pk_len,
                      uint8_t *ct, uint16_t *ct_len,
                      uint8_t *ss, uint16_t *ss_len,
                      const ScloudPlusPara *para);

/* =========================================================================
 * Decapsulation
 *
 * Input:  ct (ciphertext bytes), ct_len
 *         sk (secret key bytes), sk_len
 * Output: ss (shared secret bytes), ss_len
 * ========================================================================= */
int scloudplus_decaps(const uint8_t *ct, uint16_t ct_len,
                      const uint8_t *sk, uint16_t sk_len,
                      uint8_t *ss, uint16_t *ss_len,
                      const ScloudPlusPara *para);

#ifdef __cplusplus
}
#endif

#endif /* SCLOUDPLUS_KEM_H */
