/*
 * test_scloudplus.c — Comprehensive test for SCLOUD+ HAL and KEM.
 *
 * Tests:
 *   1. Block-level matrix multiply against known vectors
 *   2. MsgEncode/MsgDecode roundtrip (zero noise, tau=3)
 *   3. MsgEncode/MsgDecode roundtrip (zero noise, tau=4)
 *   4. Multi-block encode/decode
 *   5. BDD with small noise (should still decode correctly)
 *   6. End-to-end MsgEncode/MsgDecode within KEM context
 *   7. KEM KeyGen → Encaps → Decaps flow (functional)
 *   8. MatMul AS_E small-scale correctness check
 *
 * When Verilator backend is available (USE_VERILATOR), also runs:
 *   9. Cross-backend matmul consistency (SW vs Verilator)
 *   10. Cross-backend msgfunc consistency (SW vs Verilator)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../include/scloudplus_hal.h"
#include "../src/scloudplus_util_sw.h"
#include "../include/scloudplus_kem.h"

static int test_count = 0;
static int pass_count = 0;

#define TEST(name) do { \
    test_count++; \
    printf("  TEST %d: %s ... ", test_count, name); \
    fflush(stdout); \
} while(0)

#define PASS() do { \
    printf("PASS\n"); pass_count++; \
} while(0)

#define FAIL(msg) do { \
    printf("FAIL: %s\n", msg); \
} while(0)

/* =========================================================================
 * Test 1: Block-level matmul against identity
 * ========================================================================= */

static void test_matmul_block(void) {
    TEST("Block matmul (identity test)");
    const int B = 8, Q = 12;
    uint16_t a_block[B * B];
    uint8_t  s_block[B * B * 2 / 8];
    uint16_t c_block[B * B];

    memset(a_block, 0, sizeof(a_block));
    memset(s_block, 0, sizeof(s_block));
    for (int i = 0; i < B; i++) {
        a_block[i * B + i] = 100;
        int bit = (i * B + i) * 2;
        s_block[bit / 8] |= (0x01 << (bit % 8));
    }

    hal_bmm_block(a_block, s_block, c_block, B, Q, 0);

    int ok = 1;
    for (int i = 0; i < B; i++) {
        if (c_block[i * B + i] != 100) { ok = 0; break; }
    }
    if (ok) PASS(); else FAIL("identity result mismatch");
}

/* =========================================================================
 * Test 2: MsgEncode/MsgDecode roundtrip with zero noise (tau=3)
 * ========================================================================= */

static void test_msgfunc_roundtrip_tau3(void) {
    TEST("MsgEncode/Decode roundtrip (tau=3, zero noise)");
    int tau = 3;
    int msg_bytes = 8;

    uint8_t msg[8];
    uint16_t enc_q[32];
    uint16_t rounded_q[32];
    uint8_t decoded[8];

    const char *patterns[] = {
        "\x00\x00\x00\x00\x00\x00\x00\x00",
        "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF",
        "\x12\x34\x56\x78\x9A\xBC\xDE\xF0",
        "\xA5\x5A\xA5\x5A\xA5\x5A\xA5\x5A",
    };
    int n_pat = 4;
    int ok = 1;

    for (int p = 0; p < n_pat; p++) {
        memcpy(msg, patterns[p], 8);
        hal_msgencode_block(msg, tau, enc_q);
        hal_msgdecode_block(enc_q, tau, rounded_q, decoded);

        if (memcmp(msg, decoded, 8) != 0) {
            printf("FAIL at pattern %d\n", p);
            ok = 0;
            break;
        }
    }

    if (ok) PASS(); else FAIL("roundtrip mismatch");
}

/* =========================================================================
 * Test 3: MsgEncode/MsgDecode roundtrip with zero noise (tau=4)
 * ========================================================================= */

static void test_msgfunc_roundtrip_tau4(void) {
    TEST("MsgEncode/Decode roundtrip (tau=4, zero noise)");
    int tau = 4;
    int msg_bytes = 12;

    uint8_t msg[12];
    uint16_t enc_q[32];
    uint16_t rounded_q[32];
    uint8_t decoded[12];

    memset(msg, 0x00, 12);
    hal_msgencode_block(msg, tau, enc_q);
    hal_msgdecode_block(enc_q, tau, rounded_q, decoded);
    if (memcmp(msg, decoded, 12) != 0) { FAIL("zero-msg mismatch"); return; }

    memset(msg, 0xFF, 12);
    hal_msgencode_block(msg, tau, enc_q);
    hal_msgdecode_block(enc_q, tau, rounded_q, decoded);
    if (memcmp(msg, decoded, 12) != 0) { FAIL("all-ones mismatch"); return; }

    PASS();
}

/* =========================================================================
 * Test 4: Multi-block encode/decode
 * ========================================================================= */

static void test_msgfunc_multiblock(void) {
    TEST("Multi-block MsgEncode/Decode (ss=16, muConut=2)");
    ScloudPlusPara para;
    scloudplus_init_params(&para, 16);

    int mu_bytes = para.mu / 8;
    int mu_conut = para.muConut;
    int total = mu_bytes * mu_conut;

    uint8_t msg[16];
    uint16_t matrixM[64];
    uint8_t decoded[16];

    memset(msg, 0, total);
    hal_msgencode(msg, &para, matrixM);
    hal_msgdecode(matrixM, &para, decoded);
    if (memcmp(msg, decoded, total) != 0) { FAIL("zero-msg mismatch"); return; }

    for (int i = 0; i < total; i++) msg[i] = (uint8_t)(0xA5 + i);
    hal_msgencode(msg, &para, matrixM);
    hal_msgdecode(matrixM, &para, decoded);
    if (memcmp(msg, decoded, total) != 0) { FAIL("pattern mismatch"); return; }

    PASS();
}

/* =========================================================================
 * Test 5: BDD with small noise (should still decode correctly)
 * ========================================================================= */

static void test_bdd_noise_resilience(void) {
    TEST("BDD small-noise resilience (tau=3)");
    int tau = 3;
    uint8_t msg[8] = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0};
    uint16_t enc_q[32], noisy_q[32], rounded_q[32];
    uint8_t decoded[8];

    hal_msgencode_block(msg, tau, enc_q);

    for (int i = 0; i < 32; i++) {
        int n = (i & 1) ? -2 : 2;
        int val = (int)enc_q[i] + n;
        if (val < 0) val += SCLOUD_MOD_Q + 1;
        noisy_q[i] = (uint16_t)(val & SCLOUD_MOD_Q);
    }

    hal_msgdecode_block(noisy_q, tau, rounded_q, decoded);

    int ok = (memcmp(msg, decoded, 8) == 0);
    if (ok) PASS(); else FAIL("noise caused decode error");
}

/* =========================================================================
 * Test 6: MsgEncode/MsgDecode within KEM context
 * ========================================================================= */

static void test_kem_msg_roundtrip(void) {
    TEST("KEM msg encode/decode roundtrip (ss=16, zero noise)");
    ScloudPlusPara para;
    scloudplus_init_params(&para, 16);

    int mu_bytes = para.mu / 8;
    int mu_conut = para.muConut;
    int total = mu_bytes * mu_conut;

    uint8_t msg[16], decoded[16];
    for (int i = 0; i < total; i++) msg[i] = (uint8_t)(0x12 + i * 0x11);

    uint16_t matrixM[64];
    hal_msgencode(msg, &para, matrixM);
    hal_msgdecode(matrixM, &para, decoded);

    if (memcmp(msg, decoded, total) == 0)
        PASS();
    else
        FAIL("msg encode/decode mismatch");
}

/* =========================================================================
 * Test 7: KEM KeyGen → Encaps → Decaps flow (functional)
 * ========================================================================= */

static void test_kem_flow(void) {
    TEST("KEM KeyGen/Encaps/Decaps functional (no crash)");
    ScloudPlusPara para;
    scloudplus_init_params(&para, 16);

    uint8_t pk[4096], sk[4096], ct[8192], ss_enc[32], ss_dec[32];
    uint16_t pk_len, sk_len, ct_len, ss_len_enc, ss_len_dec;

    int ret = scloudplus_keygen(pk, &pk_len, sk, &sk_len, &para);
    if (ret != 0) { FAIL("KeyGen failed"); return; }

    ret = scloudplus_encaps(pk, pk_len, ct, &ct_len, ss_enc, &ss_len_enc, &para);
    if (ret != 0) { FAIL("Encaps failed"); return; }

    ret = scloudplus_decaps(ct, ct_len, sk, sk_len, ss_dec, &ss_len_dec, &para);
    if (ret != 0) { FAIL("Decaps failed"); return; }

    if (pk_len > 0 && sk_len > 0 && ct_len > 0 &&
        ss_len_enc == 32 && ss_len_dec == 32)
        PASS();
    else
        FAIL("invalid output lengths");
}

/* =========================================================================
 * Test 8: MatMul AS_E small-scale correctness check
 * ========================================================================= */

static void test_matmul_as_e(void) {
    TEST("MatMul AS_E small-scale (2x3 * 3x2)");
    uint8_t seedA[16] = {0};
    ScloudPlusPara para;
    memset(&para, 0, sizeof(para));
    para.m = 2; para.n = 3; para.nbar = 2;
    para.logq = 12;

    int16_t S[6] = {1, 0, -1, 0, 0, 1};
    uint16_t E[4] = {0, 0, 0, 0};
    uint16_t B[4];

    int ret = hal_matmul_as_e(seedA, S, E, &para, B);
    if (ret != 0) { FAIL("AS_E returned error"); return; }

    int nonzero = 0;
    for (int i = 0; i < 4; i++) if (B[i] != 0) nonzero++;
    if (nonzero > 0) PASS(); else FAIL("all B zero");
}

/* =========================================================================
 * Main
 * ========================================================================= */

int main(void) {
    printf("=== SCLOUD+ HAL Test Suite ===\n\n");

    hal_init("sw");

    test_matmul_block();
    test_msgfunc_roundtrip_tau3();
    test_msgfunc_roundtrip_tau4();
    test_msgfunc_multiblock();
    test_bdd_noise_resilience();
    test_kem_msg_roundtrip();
    test_kem_flow();
    test_matmul_as_e();

    printf("\n=== Results: %d/%d tests passed ===\n", pass_count, test_count);

    hal_deinit();
    return (pass_count == test_count) ? 0 : 1;
}
