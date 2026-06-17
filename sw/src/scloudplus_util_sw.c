/*
 * scloudplus_util_sw.c — SW reimplementation of SCLOUD+ KEM utility functions.
 *
 * Pack/Unpack, Compress/Decompress, Add/Sub/Verify, and CBD sampling.
 * Hash functions use a minimal portable Keccak/SHAKE256 implementation.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "scloudplus_util_sw.h"

/* =========================================================================
 * Minimal Keccak/SHAKE256 (public-domain, FIPS 202)
 * ========================================================================= */

#define KECCAK_ROUNDS 24
#define KECCAK_RATE_SHAKE256 136  /* 1088 bits */
#define KECCAK_RATE_SHA3_256  136

typedef struct {
    uint64_t state[25];
    int rate;
    int pos;        /* current position in rate buffer */
    int squeezing;  /* 0=absorbing, 1=squeezing */
    uint8_t buf[KECCAK_RATE_SHAKE256];
} KeccakCtx;

static const uint64_t keccak_rc[KECCAK_ROUNDS] = {
    0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
    0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
    0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
    0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
    0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};

static inline uint64_t rotl64(uint64_t x, int n) {
    return (x << n) | (x >> (64 - n));
}

static void keccak_f1600(uint64_t s[25]) {
    uint64_t bc[5], t;
    for (int r = 0; r < KECCAK_ROUNDS; r++) {
        /* Theta */
        for (int i = 0; i < 5; i++)
            bc[i] = s[i] ^ s[i + 5] ^ s[i + 10] ^ s[i + 15] ^ s[i + 20];
        for (int i = 0; i < 5; i++) {
            t = bc[(i + 4) % 5] ^ rotl64(bc[(i + 1) % 5], 1);
            for (int j = 0; j < 25; j += 5) s[j + i] ^= t;
        }
        /* Rho + Pi */
        t = s[1];
        int x = 0, y = 1, cur = 1;
        for (int i = 0; i < 24; i++) {
            int nx = y;
            int ny = (2 * x + 3 * y) % 5;
            x = nx; y = ny;
            uint64_t tmp = s[x + 5 * y];
            s[x + 5 * y] = rotl64(t, ((i + 1) * (i + 2) / 2) % 64);
            t = tmp;
        }
        /* Chi */
        for (int j = 0; j < 25; j += 5) {
            for (int i = 0; i < 5; i++) bc[i] = s[j + i];
            for (int i = 0; i < 5; i++)
                s[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }
        /* Iota */
        s[0] ^= keccak_rc[r];
    }
}

static void keccak_absorb(KeccakCtx *ctx, const uint8_t *data, uint32_t len) {
    while (len > 0) {
        int space = ctx->rate - ctx->pos;
        int take = (int)((uint32_t)space < len ? (uint32_t)space : len);
        for (int i = 0; i < take; i++) ctx->buf[ctx->pos + i] ^= data[i];
        data += take; len -= take; ctx->pos += take;
        if (ctx->pos == ctx->rate) {
            /* XOR buf into state */
            for (int i = 0; i < ctx->rate / 8; i++) {
                uint64_t v = 0;
                for (int j = 0; j < 8; j++)
                    v |= (uint64_t)ctx->buf[i * 8 + j] << (j * 8);
                ctx->state[i] ^= v;
            }
            keccak_f1600(ctx->state);
            ctx->pos = 0;
        }
    }
}

static void keccak_finish_absorb(KeccakCtx *ctx, uint8_t pad) {
    ctx->buf[ctx->pos] ^= pad;
    ctx->buf[ctx->rate - 1] ^= 0x80;
    for (int i = 0; i < ctx->rate / 8; i++) {
        uint64_t v = 0;
        for (int j = 0; j < 8; j++)
            v |= (uint64_t)ctx->buf[i * 8 + j] << (j * 8);
        ctx->state[i] ^= v;
    }
    keccak_f1600(ctx->state);
    ctx->pos = 0;
    ctx->squeezing = 1;
}

static void keccak_squeeze(KeccakCtx *ctx, uint8_t *out, uint32_t len) {
    while (len > 0) {
        if (ctx->pos == 0) {
            /* Output state as bytes */
            for (int i = 0; i < ctx->rate / 8; i++) {
                uint64_t v = ctx->state[i];
                for (int j = 0; j < 8; j++)
                    ctx->buf[i * 8 + j] = (uint8_t)(v >> (j * 8));
            }
        }
        int space = ctx->rate - ctx->pos;
        int take = (int)((uint32_t)space < len ? (uint32_t)space : len);
        memcpy(out, ctx->buf + ctx->pos, take);
        out += take; len -= take; ctx->pos += take;
        if (ctx->pos == ctx->rate) {
            ctx->pos = 0;
            keccak_f1600(ctx->state);
        }
    }
}

/* =========================================================================
 * Public SHAKE256 API
 * ========================================================================= */

void *sw_shake256_new(void) {
    KeccakCtx *ctx = (KeccakCtx *)calloc(1, sizeof(KeccakCtx));
    if (ctx) ctx->rate = KECCAK_RATE_SHAKE256;
    return ctx;
}

void sw_shake256_free(void *ctx) { free(ctx); }
int  sw_shake256_init(void *ctx_v) {
    KeccakCtx *ctx = (KeccakCtx *)ctx_v;
    memset(ctx->state, 0, sizeof(ctx->state));
    memset(ctx->buf, 0, sizeof(ctx->buf));
    ctx->pos = 0;
    ctx->squeezing = 0;
    return 0;
}

int sw_shake256_update(void *ctx_v, const uint8_t *data, uint32_t len) {
    KeccakCtx *ctx = (KeccakCtx *)ctx_v;
    if (ctx->squeezing) return -1;
    keccak_absorb(ctx, data, len);
    return 0;
}

int sw_shake256_squeeze(void *ctx_v, uint8_t *out, uint32_t out_len) {
    KeccakCtx *ctx = (KeccakCtx *)ctx_v;
    if (!ctx->squeezing) {
        keccak_finish_absorb(ctx, 0x1F);  /* SHAKE padding */
    }
    keccak_squeeze(ctx, out, out_len);
    return 0;
}

int sw_shake256_final(void *ctx_v, uint8_t *out, uint32_t *out_len) {
    return sw_shake256_squeeze(ctx_v, out, *out_len);
}

int sw_shake256_hash(const uint8_t *input, uint32_t in_len,
                     uint8_t *output, uint32_t out_len) {
    KeccakCtx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.rate = KECCAK_RATE_SHAKE256;
    sw_shake256_init(&ctx);
    sw_shake256_update(&ctx, input, in_len);
    return sw_shake256_squeeze(&ctx, output, out_len);
}

int sw_sha3_256(const uint8_t *input, uint32_t in_len, uint8_t output[32]) {
    KeccakCtx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.rate = KECCAK_RATE_SHA3_256;
    keccak_absorb(&ctx, input, in_len);
    keccak_finish_absorb(&ctx, 0x06);  /* SHA3 padding */
    keccak_squeeze(&ctx, output, 32);
    return 0;
}

/* =========================================================================
 * AES-128-ECB (placeholder for deterministic A expansion)
 *
 * For the functional model, we use a simple LCG-style PRNG seeded from
 * the AES key and counter. This is NOT cryptographically secure but
 * produces deterministic, reproducible outputs for testing.
 *
 * REPLACE with real AES (e.g., OpenSSL EVP_aes_128_ecb) for production.
 * ========================================================================= */

void *sw_aes128_ecb_new(void) { return NULL; }
void  sw_aes128_ecb_free(void *ctx) { (void)ctx; }
int   sw_aes128_ecb_init(void *ctx, const uint8_t key[16], int encrypt) {
    (void)ctx; (void)key; (void)encrypt; return 0;
}
int   sw_aes128_ecb_update(void *ctx, const uint8_t *in, uint32_t in_len,
                            uint8_t *out, uint32_t *out_len) {
    (void)ctx;
    /* Deterministic expansion: hash the input counter with a simple LCG */
    uint32_t state = 0;
    for (uint32_t i = 0; i < in_len; i++) state = state * 1103515245u + in[i] + 12345u;
    if (!state) state = 1;
    if (out_len) *out_len = in_len;
    for (uint32_t i = 0; i < in_len; i++) {
        state = state * 1103515245u + 12345u;
        out[i] = (uint8_t)(state >> 16);
    }
    return 0;
}

/* =========================================================================
 * Pack / Unpack functions
 * ========================================================================= */

void sw_pack_pk(const uint16_t *B, const ScloudPlusPara *para, uint8_t *pk) {
    const uint16_t *ptrIn = B;
    uint8_t *ptrOut = pk;
    for (int i = 0; i < para->m * para->nbar; i += 2) {
        uint32_t temp = ((uint32_t)ptrIn[0]) | ((uint32_t)ptrIn[1] << 16);
        temp = (temp & 0xFFF) ^ ((temp >> 4) & 0xFFF000);
        ptrOut[0] = temp & 0xFF;
        ptrOut[1] = (temp >> 8) & 0xFF;
        ptrOut[2] = (temp >> 16) & 0xFF;
        ptrIn += 2; ptrOut += 3;
    }
}

void sw_unpack_pk(const uint8_t *pk, const ScloudPlusPara *para, uint16_t *B) {
    const uint8_t *ptrIn = pk;
    uint16_t *ptrOut = B;
    for (int i = 0; i < para->m * para->nbar; i += 2) {
        ptrOut[0] = ((uint16_t)ptrIn[0]) | (((uint16_t)ptrIn[1] & 0x0F) << 8);
        ptrOut[1] = ((uint16_t)(ptrIn[1] >> 4)) | (((uint16_t)ptrIn[2]) << 4);
        ptrOut[0] &= SCLOUD_MOD_Q;
        ptrOut[1] &= SCLOUD_MOD_Q;
        ptrIn += 3; ptrOut += 2;
    }
}

void sw_pack_sk(const int16_t *S, const ScloudPlusPara *para, uint8_t *sk) {
    const int16_t *ptrIn = S;
    uint8_t *ptrOut = sk;
    for (int i = 0; i < para->n * para->nbar; i += 4) {
        uint8_t b0 = (uint8_t)(ptrIn[0] & 0x03);
        uint8_t b1 = (uint8_t)(ptrIn[1] & 0x03);
        uint8_t b2 = (uint8_t)(ptrIn[2] & 0x03);
        uint8_t b3 = (uint8_t)(ptrIn[3] & 0x03);
        *ptrOut = b0 | (b1 << 2) | (b2 << 4) | (b3 << 6);
        ptrIn += 4; ptrOut += 1;
    }
}

void sw_unpack_sk(const uint8_t *sk, const ScloudPlusPara *para, int16_t *S) {
    const uint8_t *ptrIn = sk;
    int16_t *ptrOut = S;
    for (int i = 0; i < para->n * para->nbar; i += 4) {
        uint8_t v = *ptrIn;
        /* Sign-extend 2-bit values: 00=0, 01=+1, 10=-1(-2 as 2-bit), 11=??→0 */
        int8_t vals[4];
        vals[0] = (int8_t)((v & 0x03) << 6) >> 6;       /* sign-extend */
        vals[1] = (int8_t)(((v >> 2) & 0x03) << 6) >> 6;
        vals[2] = (int8_t)(((v >> 4) & 0x03) << 6) >> 6;
        vals[3] = (int8_t)(((v >> 6) & 0x03) << 6) >> 6;
        for (int j = 0; j < 4; j++) {
            if (vals[j] == -2) vals[j] = -1;  /* 10 → -1 */
            if (vals[j] == -3 || vals[j] == -4) vals[j] = 0;  /* 11 → 0 (shouldn't happen) */
            ptrOut[j] = vals[j];
        }
        ptrIn += 1; ptrOut += 4;
    }
}

/* =========================================================================
 * Pack/Unpack C1 — security-level specific bit packing
 * ========================================================================= */

void sw_pack_c1(const uint16_t *C, const ScloudPlusPara *para, uint8_t *out) {
    if (para->ss == 16) {
        int inLen = para->mbar * para->n;
        const uint8_t *ptrIn = (const uint8_t *)C;
        for (int i = 0; i < inLen; i++) out[i] = ptrIn[2 * i];
        for (int i = 0; i < (inLen >> 3); i++)
            for (int j = 0; j < 8; j++)
                out[inLen + i] = (uint8_t)(out[inLen + i] << 1) | ptrIn[16 * i + 2 * j + 1];
    } else if (para->ss == 24) {
        /* Same as pk packing */
        const uint16_t *ptrIn = C;
        uint8_t *ptrOut = out;
        for (int i = 0; i < para->mbar * para->n; i += 2) {
            uint32_t temp = ((uint32_t)ptrIn[0]) | ((uint32_t)ptrIn[1] << 16);
            temp = (temp & 0xFFF) ^ ((temp >> 4) & 0xFFF000);
            ptrOut[0] = temp & 0xFF;
            ptrOut[1] = (temp >> 8) & 0xFF;
            ptrOut[2] = (temp >> 16) & 0xFF;
            ptrIn += 2; ptrOut += 3;
        }
    } else if (para->ss == 32) {
        int inLen = para->mbar * para->n;
        const uint8_t *ptrIn = (const uint8_t *)C;
        for (int i = 0; i < inLen; i++) out[i] = ptrIn[2 * i];
        for (int i = 0; i < (inLen >> 2); i++)
            for (int j = 0; j < 4; j++)
                out[inLen + i] = (uint8_t)(out[inLen + i] << 2) | ptrIn[8 * i + 2 * j + 1];
    }
}

void sw_unpack_c1(const uint8_t *in, const ScloudPlusPara *para, uint16_t *C) {
    if (para->ss == 16) {
        int outLen = para->mbar * para->n;
        for (int i = 0; i < outLen; i++) C[i] = (uint16_t)in[i];
        for (int i = 0; i < (outLen >> 3); i++) {
            for (int j = 0; j < 8; j++)
                C[8 * i + j] |= ((uint16_t)in[outLen + i] << (j + 1)) & 0x100;
        }
    } else if (para->ss == 24) {
        const uint8_t *ptrIn = in;
        uint16_t *ptrOut = C;
        for (int i = 0; i < para->mbar * para->n; i += 2) {
            ptrOut[0] = ((uint16_t)ptrIn[0]) | (((uint16_t)ptrIn[1] & 0x0F) << 8);
            ptrOut[1] = ((uint16_t)(ptrIn[1] >> 4)) | (((uint16_t)ptrIn[2]) << 4);
            ptrOut[0] &= SCLOUD_MOD_Q; ptrOut[1] &= SCLOUD_MOD_Q;
            ptrIn += 3; ptrOut += 2;
        }
    } else if (para->ss == 32) {
        int outLen = para->mbar * para->n;
        for (int i = 0; i < outLen; i++) C[i] = (uint16_t)in[i];
        for (int i = 0; i < (outLen >> 2); i++) {
            for (int j = 0; j < 4; j++)
                C[4 * i + j] |= ((uint16_t)in[outLen + i] << (2 * j + 2)) & 0x300;
        }
    }
}

/* =========================================================================
 * Pack/Unpack C2 — compressed ciphertext component
 * ========================================================================= */

void sw_pack_c2(const uint16_t *C, const ScloudPlusPara *para, uint8_t *out) {
    if (para->ss == 16) {
        int inLen = para->mbar * para->nbar;
        const uint16_t *ptrIn = C;
        uint8_t *ptrOut = out;
        for (int i = 0; i < inLen; i += 8) {
            ptrOut[0] = (uint8_t)((ptrIn[0] & 0x7F) | (ptrIn[1] << 7));
            ptrOut[1] = (uint8_t)(((ptrIn[1] >> 1) & 0x3F) | (ptrIn[2] << 6));
            ptrOut[2] = (uint8_t)(((ptrIn[2] >> 2) & 0x1F) | (ptrIn[3] << 5));
            ptrOut[3] = (uint8_t)(((ptrIn[3] >> 3) & 0x0F) | (ptrIn[4] << 4));
            ptrOut[4] = (uint8_t)(((ptrIn[4] >> 4) & 0x07) | (ptrIn[5] << 3));
            ptrOut[5] = (uint8_t)(((ptrIn[5] >> 5) & 0x03) | (ptrIn[6] << 2));
            ptrOut[6] = (uint8_t)(((ptrIn[6] >> 6) & 0x01) | (ptrIn[7] << 1));
            ptrIn += 8; ptrOut += 7;
        }
    } else if (para->ss == 24) {
        /* Same as C1 packing for ss=24 */
        sw_pack_c1(C, para, out);
    } else if (para->ss == 32) {
        int inLen = para->mbar * para->nbar & ~7;
        const uint16_t *ptrIn = C;
        uint8_t *ptrOut = out;
        for (int i = 0; i < inLen; i += 8) {
            ptrOut[0] = (uint8_t)((ptrIn[0] & 0x7F) | (ptrIn[1] << 7));
            ptrOut[1] = (uint8_t)(((ptrIn[1] >> 1) & 0x3F) | (ptrIn[2] << 6));
            ptrOut[2] = (uint8_t)(((ptrIn[2] >> 2) & 0x1F) | (ptrIn[3] << 5));
            ptrOut[3] = (uint8_t)(((ptrIn[3] >> 3) & 0x0F) | (ptrIn[4] << 4));
            ptrOut[4] = (uint8_t)(((ptrIn[4] >> 4) & 0x07) | (ptrIn[5] << 3));
            ptrOut[5] = (uint8_t)(((ptrIn[5] >> 5) & 0x03) | (ptrIn[6] << 2));
            ptrOut[6] = (uint8_t)(((ptrIn[6] >> 6) & 0x01) | (ptrIn[7] << 1));
            ptrIn += 8; ptrOut += 7;
        }
        /* Remainder */
        if (inLen < para->mbar * para->nbar) {
            ptrOut[0] = (uint8_t)((ptrIn[0] & 0x7F) | (ptrIn[1] << 7));
            ptrOut[1] = (uint8_t)(((ptrIn[1] >> 1) & 0x3F) | (ptrIn[2] << 6));
            ptrOut[2] = (uint8_t)(((ptrIn[2] >> 2) & 0x1F) | (ptrIn[3] << 5));
            ptrOut[3] = (uint8_t)((ptrIn[3] >> 3) & 0x0F);
        }
    }
}

void sw_unpack_c2(const uint8_t *in, const ScloudPlusPara *para, uint16_t *C) {
    if (para->ss == 16) {
        const uint8_t *ptrIn = in;
        uint16_t *ptrOut = C;
        for (int i = 0; i < para->mbar * para->nbar; i += 8) {
            ptrOut[0] = ptrIn[0] & 0x7F;
            ptrOut[1] = ((uint16_t)ptrIn[0] >> 7) | (((uint16_t)ptrIn[1] & 0x3F) << 1);
            ptrOut[2] = ((uint16_t)ptrIn[1] >> 6) | (((uint16_t)ptrIn[2] & 0x1F) << 2);
            ptrOut[3] = ((uint16_t)ptrIn[2] >> 5) | (((uint16_t)ptrIn[3] & 0x0F) << 3);
            ptrOut[4] = ((uint16_t)ptrIn[3] >> 4) | (((uint16_t)ptrIn[4] & 0x07) << 4);
            ptrOut[5] = ((uint16_t)ptrIn[4] >> 3) | (((uint16_t)ptrIn[5] & 0x03) << 5);
            ptrOut[6] = ((uint16_t)ptrIn[5] >> 2) | (((uint16_t)ptrIn[6] & 0x01) << 6);
            ptrOut[7] = ((uint16_t)ptrIn[6] >> 1) & 0x7F;
            ptrIn += 7; ptrOut += 8;
        }
    } else if (para->ss == 24) {
        sw_unpack_c1(in, para, C);
    } else if (para->ss == 32) {
        /* Same as ss=16 but handles remainder */
        const uint8_t *ptrIn = in;
        uint16_t *ptrOut = C;
        int full_blocks = (para->mbar * para->nbar) & ~7;
        for (int i = 0; i < full_blocks; i += 8) {
            ptrOut[0] = ptrIn[0] & 0x7F;
            ptrOut[1] = ((uint16_t)ptrIn[0] >> 7) | (((uint16_t)ptrIn[1] & 0x3F) << 1);
            ptrOut[2] = ((uint16_t)ptrIn[1] >> 6) | (((uint16_t)ptrIn[2] & 0x1F) << 2);
            ptrOut[3] = ((uint16_t)ptrIn[2] >> 5) | (((uint16_t)ptrIn[3] & 0x0F) << 3);
            ptrOut[4] = ((uint16_t)ptrIn[3] >> 4) | (((uint16_t)ptrIn[4] & 0x07) << 4);
            ptrOut[5] = ((uint16_t)ptrIn[4] >> 3) | (((uint16_t)ptrIn[5] & 0x03) << 5);
            ptrOut[6] = ((uint16_t)ptrIn[5] >> 2) | (((uint16_t)ptrIn[6] & 0x01) << 6);
            ptrOut[7] = ((uint16_t)ptrIn[6] >> 1) & 0x7F;
            ptrIn += 7; ptrOut += 8;
        }
        int rem = (para->mbar * para->nbar) - full_blocks;
        if (rem > 0) {
            ptrOut[0] = ptrIn[0] & 0x7F;
            if (rem > 1) ptrOut[1] = ((uint16_t)ptrIn[0] >> 7) | (((uint16_t)ptrIn[1] & 0x3F) << 1);
            if (rem > 2) ptrOut[2] = ((uint16_t)ptrIn[1] >> 6) | (((uint16_t)ptrIn[2] & 0x1F) << 2);
            if (rem > 3) ptrOut[3] = ((uint16_t)ptrIn[2] >> 5) | (((uint16_t)ptrIn[3] & 0x0F) << 3);
        }
    }
}

/* =========================================================================
 * Compress / Decompress
 * ========================================================================= */

void sw_compress_c1(const uint16_t *C, const ScloudPlusPara *para, uint16_t *out) {
    if (para->ss == 16) {
        for (int i = 0; i < para->mbar * para->n; i++)
            out[i] = (uint16_t)((((uint32_t)(C[i] & SCLOUD_MOD_Q) << 9) + 2048) >> 12) & 0x1FF;
    } else if (para->ss == 24) {
        memcpy(out, C, para->mbar * para->n * sizeof(uint16_t));
    } else if (para->ss == 32) {
        for (int i = 0; i < para->mbar * para->n; i++)
            out[i] = (uint16_t)((((uint32_t)(C[i] & SCLOUD_MOD_Q) << 10) + 2048) >> 12) & 0x3FF;
    }
}

void sw_decompress_c1(const uint16_t *in, const ScloudPlusPara *para, uint16_t *C) {
    if (para->ss == 16) {
        for (int i = 0; i < para->mbar * para->n; i++)
            C[i] = (uint16_t)((((uint32_t)(in[i] & 0x1FF) << 12) + 256) >> 9);
    } else if (para->ss == 24) {
        memcpy(C, in, para->mbar * para->n * sizeof(uint16_t));
    } else if (para->ss == 32) {
        for (int i = 0; i < para->mbar * para->n; i++)
            C[i] = (uint16_t)((((uint32_t)(in[i] & 0x3FF) << 12) + 512) >> 10);
    }
}

void sw_compress_c2(const uint16_t *C, const ScloudPlusPara *para, uint16_t *out) {
    if (para->ss == 16 || para->ss == 32) {
        for (int i = 0; i < para->mbar * para->nbar; i++) {
            uint32_t tmp = ((((uint32_t)(C[i] & SCLOUD_MOD_Q) << 7) + 2048) >> 12);
            uint32_t rem = (((uint32_t)(C[i] & SCLOUD_MOD_Q) << 7) + 2048) % 6144;
            out[i] = (uint16_t)((tmp - ((!rem) && 1)) & 0x7F);
        }
    } else if (para->ss == 24) {
        for (int i = 0; i < para->mbar * para->nbar; i++) {
            uint32_t tmp = ((((uint32_t)(C[i] & SCLOUD_MOD_Q) << 10) + 2048) >> 12);
            uint32_t rem = (((uint32_t)(C[i] & SCLOUD_MOD_Q) << 10) + 2048) % 6144;
            out[i] = (uint16_t)((tmp - ((!rem) && 1)) & 0x3FF);
        }
    }
}

void sw_decompress_c2(const uint16_t *in, const ScloudPlusPara *para, uint16_t *C) {
    if (para->ss == 16 || para->ss == 32) {
        for (int i = 0; i < para->mbar * para->nbar; i++)
            C[i] = (uint16_t)((((uint32_t)(in[i] & 0x7F) << 12) + 64) >> 7);
    } else if (para->ss == 24) {
        for (int i = 0; i < para->mbar * para->nbar; i++)
            C[i] = (uint16_t)((((uint32_t)(in[i] & 0x3FF) << 12) + 512) >> 10);
    }
}

/* =========================================================================
 * Arithmetic helpers
 * ========================================================================= */

void sw_add_mod_q(const uint16_t *a, const uint16_t *b, int len, uint16_t *out) {
    for (int i = 0; i < len; i++) out[i] = (a[i] + b[i]) & SCLOUD_MOD_Q;
}

void sw_sub_mod_q(const uint16_t *a, const uint16_t *b, int len, uint16_t *out) {
    for (int i = 0; i < len; i++) out[i] = (a[i] - b[i]) & SCLOUD_MOD_Q;
}

int sw_verify(const uint8_t *a, const uint8_t *b, int len) {
    uint8_t r = 0;
    for (int i = 0; i < len; i++) r |= a[i] ^ b[i];
    return ((int8_t)((-(r >> 1)) | (-(r & 1)))) >> 7;
}

/* =========================================================================
 * Random number generation (placeholder - replace with real RNG)
 * ========================================================================= */

void get_random(uint8_t *buf, int len) {
    static uint32_t fake_seed = 0xDEADBEEF;
    for (int i = 0; i < len; i++) {
        fake_seed = fake_seed * 1103515245u + 12345u;
        buf[i] = (uint8_t)(fake_seed >> 16);
    }
}

/* =========================================================================
 * CBD sampling helpers
 * ========================================================================= */

/* CBD1: 1 byte → 4 values (eta=1, each value from 1 bit) */
static void cbd1(uint8_t in, uint16_t *out) {
    for (int j = 0; j < 4; j++) {
        uint8_t b0 = in & 1, b1 = (in >> 1) & 1;
        out[j] = (uint16_t)((int16_t)b0 - (int16_t)b1);
        in >>= 2;
    }
}

/* CBD2: 1 byte → 2 values (eta=2, each value from 2 bits) */
static void cbd2(uint8_t in, uint16_t *out) {
    uint8_t b = (in & 0x55) + ((in >> 1) & 0x55);
    out[0] = (uint16_t)((int16_t)(b & 0x03) - (int16_t)((b >> 2) & 0x03));
    out[1] = (uint16_t)((int16_t)((b >> 4) & 0x03) - (int16_t)((b >> 6) & 0x03));
}

/* CBD3: 3 bytes → 4 values */
static void cbd3(uint32_t in, uint16_t *out) {
    uint32_t b = 0;
    b += in & 0x00249249;
    b += (in >> 1) & 0x00249249;
    b += (in >> 2) & 0x00249249;
    for (int i = 0; i < 4; i++)
        out[i] = (uint16_t)((int32_t)((b >> (6 * i)) & 0x07) - (int32_t)((b >> (6 * i + 3)) & 0x07));
}

/* CBD7: 7 bytes → 4 values */
static void cbd7(uint64_t in, uint16_t *out) {
    uint64_t b = 0;
    b += in & 0x2040810204081ULL;
    b += (in >> 1) & 0x2040810204081ULL;
    b += (in >> 2) & 0x2040810204081ULL;
    b += (in >> 3) & 0x2040810204081ULL;
    b += (in >> 4) & 0x2040810204081ULL;
    b += (in >> 5) & 0x2040810204081ULL;
    b += (in >> 6) & 0x2040810204081ULL;
    for (int i = 0; i < 4; i++)
        out[i] = (uint16_t)((int32_t)((b >> (14 * i)) & 0x7F) - (int32_t)((b >> (14 * i + 7)) & 0x7F));
}

/* =========================================================================
 * SamplePsi — sample ternary S (n × nbar) with h1 nonzeros per column
 * ========================================================================= */

int sw_sample_psi(const uint8_t *seed, const ScloudPlusPara *para, int16_t *S) {
    int n = para->n, nbar = para->nbar, h1 = para->h1;
    memset(S, 0, n * nbar * sizeof(int16_t));

    /* Generate enough random bytes via SHAKE256 */
    int hash_len = 5 * 136;  /* 680 bytes = 5 SHAKE256 rate blocks */
    uint8_t hash[680];
    sw_shake256_hash(seed, SCLOUD_SEED_R1_LEN, hash, hash_len);

    /* Rejection sampling to get column positions */
    /* For simplicity in this functional model, use a direct approach:
     * Populate each column with h1 nonzero entries at pseudo-random positions */
    uint32_t rng_state = 0;
    for (int i = 0; i < 32 && i < hash_len; i++)
        rng_state = rng_state * 1103515245u + hash[i] + 12345u;

    for (int col = 0; col < nbar; col++) {
        int count = 0;
        int attempts = 0;
        while (count < h1 * 2 && attempts < n * 10) {
            rng_state = rng_state * 1103515245u + 12345u;
            int pos = (int)(rng_state % (uint32_t)n);
            if (S[col * n + pos] == 0) {
                /* Alternate +1 and -1 */
                S[col * n + pos] = (int16_t)(1 - 2 * (count & 1));
                count++;
            }
            attempts++;
        }
    }
    return 0;
}

/* =========================================================================
 * SamplePhi — sample ternary S' (m × mbar) with h2 nonzeros per column
 * ========================================================================= */

int sw_sample_phi(const uint8_t *seed, const ScloudPlusPara *para, int16_t *S_prime) {
    int m = para->m, mbar = para->mbar, h2 = para->h2;
    memset(S_prime, 0, m * mbar * sizeof(int16_t));

    uint8_t hash[680];
    sw_shake256_hash(seed, SCLOUD_ALPHA_LEN, hash, 680);

    uint32_t rng_state = 0;
    for (int i = 0; i < 32; i++)
        rng_state = rng_state * 1103515245u + hash[i] + 12345u;

    for (int col = 0; col < mbar; col++) {
        int count = 0, attempts = 0;
        while (count < h2 * 2 && attempts < m * 10) {
            rng_state = rng_state * 1103515245u + 12345u;
            int pos = (int)(rng_state % (uint32_t)m);
            if (S_prime[col * m + pos] == 0) {
                S_prime[col * m + pos] = (int16_t)(1 - 2 * (count & 1));
                count++;
            }
            attempts++;
        }
    }
    return 0;
}

/* =========================================================================
 * SampleEta1 — sample noise E (m × nbar)
 * ========================================================================= */

int sw_sample_eta1(const uint8_t *seed, const ScloudPlusPara *para, uint16_t *E) {
    int m = para->m, nbar = para->nbar, eta1 = para->eta1;
    memset(E, 0, m * nbar * sizeof(uint16_t));

    int hash_len = (m * nbar * 2 * eta1) / 8;
    uint8_t *tmp = (uint8_t *)malloc(hash_len);
    if (!tmp) return -1;
    sw_shake256_hash(seed, SCLOUD_SEED_R2_LEN, tmp, hash_len);

    uint8_t *ptr = tmp;
    uint16_t *out = E;

    if (eta1 == 2) {
        for (int i = 0; i < m * nbar; i += 2) {
            cbd2(*ptr, out); ptr++; out += 2;
        }
    } else if (eta1 == 3) {
        for (int i = 0; i < m * nbar; i += 4) {
            uint32_t v = (uint32_t)ptr[0] | ((uint32_t)ptr[1] << 8) | ((uint32_t)ptr[2] << 16);
            cbd3(v & 0xFFFFFF, out); ptr += 3; out += 4;
        }
    } else if (eta1 == 7) {
        for (int i = 0; i < m * nbar; i += 4) {
            uint64_t v = (uint64_t)ptr[0] | ((uint64_t)ptr[1] << 8) |
                         ((uint64_t)ptr[2] << 16) | ((uint64_t)ptr[3] << 24) |
                         ((uint64_t)ptr[4] << 32) | ((uint64_t)ptr[5] << 40) |
                         ((uint64_t)ptr[6] << 48);
            cbd7(v & 0xFFFFFFFFFFFFFFULL, out); ptr += 7; out += 4;
        }
    }
    free(tmp);
    return 0;
}

/* =========================================================================
 * SampleEta2 — sample noise E1 (mbar × n) and E2 (mbar × nbar)
 * ========================================================================= */

int sw_sample_eta2(const uint8_t *seed, const ScloudPlusPara *para,
                   uint16_t *E1, uint16_t *E2) {
    int mbar = para->mbar, n = para->n, nbar = para->nbar, eta2 = para->eta2;
    memset(E1, 0, mbar * n * sizeof(uint16_t));
    memset(E2, 0, mbar * nbar * sizeof(uint16_t));

    int hash1_len = (mbar * n * 2 * eta2) / 8;
    int hash2_len = ((mbar * nbar * 2 * eta2) + 7) / 8;
    int hash_len = hash1_len + hash2_len;
    uint8_t *tmp = (uint8_t *)malloc(hash_len);
    if (!tmp) return -1;
    sw_shake256_hash(seed, SCLOUD_SEED_R2_LEN, tmp, hash_len);

    uint8_t *p1 = tmp, *p2 = tmp + hash1_len;
    uint16_t *o1 = E1, *o2 = E2;

    if (eta2 == 1) {
        for (int i = 0; i < mbar * n; i += 4) { cbd1(*p1, o1); p1++; o1 += 4; }
        for (int i = 0; i < mbar * nbar; i += 4) { cbd1(*p2, o2); p2++; o2 += 4; }
    } else if (eta2 == 2) {
        for (int i = 0; i < mbar * n; i += 2) { cbd2(*p1, o1); p1++; o1 += 2; }
        for (int i = 0; i < mbar * nbar; i += 2) { cbd2(*p2, o2); p2++; o2 += 2; }
    } else if (eta2 == 7) {
        for (int i = 0; i < mbar * n; i += 4) {
            uint64_t v = (uint64_t)p1[0] | ((uint64_t)p1[1] << 8) |
                         ((uint64_t)p1[2] << 16) | ((uint64_t)p1[3] << 24) |
                         ((uint64_t)p1[4] << 32) | ((uint64_t)p1[5] << 40) |
                         ((uint64_t)p1[6] << 48);
            cbd7(v & 0xFFFFFFFFFFFFFFULL, o1); p1 += 7; o1 += 4;
        }
        for (int i = 0; i < mbar * nbar; i += 4) {
            uint64_t v = (uint64_t)p2[0] | ((uint64_t)p2[1] << 8) |
                         ((uint64_t)p2[2] << 16) | ((uint64_t)p2[3] << 24) |
                         ((uint64_t)p2[4] << 32) | ((uint64_t)p2[5] << 40) |
                         ((uint64_t)p2[6] << 48);
            cbd7(v & 0xFFFFFFFFFFFFFFULL, o2); p2 += 7; o2 += 4;
        }
    }
    free(tmp);
    return 0;
}
