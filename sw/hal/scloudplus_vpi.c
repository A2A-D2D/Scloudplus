/*
 * scloudplus_vpi.c — VPI bridge for Scloud+ iverilog co-simulation.
 *
 * Provides $sw_* system tasks callable from Verilog testbench:
 *   $sw_random(seed_out_base)             — generate 32 random bytes → DPRAM
 *   $sw_shake256(in_base, in_bytes, out_base, out_bytes) — SHAKE256 hash
 *   $sw_sample_psi(seed_base)             — sample ternary S → DPRAM
 *   $sw_sample_phi(seed_base)             — sample ternary S' → DPRAM
 *   $sw_sample_eta1(seed_base)            — sample noise E → DPRAM
 *   $sw_sample_eta2(seed_base)            — sample noise E1,E2 → DPRAM
 *   $sw_generate_a(seed_base, row_start, n_rows, n_cols, out_base) — A rows
 *   $sw_msgencode_sw(msg_base, tau, muConut, q_out_base)  — SW ref encode
 *   $sw_msgdecode_sw(q_base, tau, muConut, msg_out_base) — SW ref decode
 *   $sw_init_params(ss)                   — init parameter set
 *   $sw_get_param(which)                  — get param: m, n, mbar, nbar, etc.
 *   $sw_pack_pk(B_base)                   — pack PK bytes
 *   $sw_unpack_pk(pk_base)                — unpack PK bytes
 *   $sw_pack_sk(S_base)                   — pack SK bytes
 *   $sw_unpack_sk(sk_base)                — unpack SK bytes
 *   $sw_add_mod_q(a_base, b_base, len, out_base)
 *   $sw_sub_mod_q(a_base, b_base, len, out_base)
 *
 * Data exchange through DPRAM:
 *   - Q values (12-bit): packed as uint16 in DPRAM 256-bit words
 *   - Bytes: packed 32 bytes per DPRAM word
 *   - Ternary values: packed as 2-bit in DPRAM
 *
 * Build: iverilog-vpi scloudplus_vpi.c scloudplus_util_sw.c --name=scloudplus_vpi
 */

#include <vpi_user.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* =========================================================================
 * Shared state — mirrors ScloudPlusPara
 * ========================================================================= */

static int g_m = 600, g_n = 600, g_mbar = 8, g_nbar = 8;
static int g_tau = 3, g_mu = 64, g_muConut = 2;
static int g_h1 = 128, g_h2 = 128, g_eta1 = 2, g_eta2 = 2;
static int g_logq = 12;

#define MOD_Q  0xFFF
#define B_SIZE 8

/* Forward declarations of utility functions (from scloudplus_util_sw.c) */
extern void get_random(uint8_t *buf, int len);
extern int  sw_shake256_hash(const uint8_t *input, uint32_t in_len,
                              uint8_t *output, uint32_t out_len);
extern int  sw_sample_psi(const uint8_t *seed, const void *para, int16_t *S);
extern int  sw_sample_phi(const uint8_t *seed, const void *para, int16_t *S_prime);
extern int  sw_sample_eta1(const uint8_t *seed, const void *para, uint16_t *E);
extern int  sw_sample_eta2(const uint8_t *seed, const void *para,
                            uint16_t *E1, uint16_t *E2);
extern void sw_generate_a_rows(const uint8_t *seedA, int row_start, int n_rows,
                                int n_cols, uint16_t *a_out);
extern void sw_pack_pk(const uint16_t *B, const void *para, uint8_t *pk);
extern void sw_unpack_pk(const uint8_t *pk, const void *para, uint16_t *B);
extern void sw_pack_sk(const int16_t *S, const void *para, uint8_t *sk);
extern void sw_unpack_sk(const uint8_t *sk, const void *para, int16_t *S);
extern void sw_add_mod_q(const uint16_t *a, const uint16_t *b, int len, uint16_t *out);
extern void sw_sub_mod_q(const uint16_t *a, const uint16_t *b, int len, uint16_t *out);

/* External msgfunc SW reference */
extern void hal_sw_msgencode(const uint8_t *msg, const void *para, uint16_t *matrixM);
extern int  hal_sw_msgdecode(const uint16_t *matrixM, const void *para, uint8_t *msg);

/* =========================================================================
 * DPRAM access via VPI — read/write Verilog dpram_mem array
 * ========================================================================= */

/* Get handle to dpram_mem word at index */
static vpiHandle get_dpram_word(int idx) {
    vpiHandle sys = vpi_handle(vpiSysTfCall, NULL);
    vpiHandle mod = vpi_handle(vpiScope, sys);
    /* Navigate to dpram_mem[idx] */
    char name[64];
    snprintf(name, sizeof(name), "dpram_mem[%d]", idx);
    /* Try to find it in the current scope */
    vpiHandle mem = vpi_handle_by_name(name, mod);
    if (!mem) {
        /* Try one level up (module scope) */
        vpiHandle pmod = vpi_handle(vpiModule, mod);
        if (pmod) {
            char fullname[128];
            snprintf(fullname, sizeof(fullname), "tb.dpram_mem[%d]", idx);
            mem = vpi_handle_by_name(fullname, NULL);
        }
    }
    return mem;
}

/* Find dpram_mem array handle (cached) */
static vpiHandle dpram_handle = NULL;

static vpiHandle get_dpram_array(void) {
    if (dpram_handle) return dpram_handle;
    /* Search for dpram_mem in the design */
    vpiHandle mod_iter = vpi_iterate(vpiModule, NULL);
    if (!mod_iter) return NULL;
    vpiHandle mod;
    while ((mod = vpi_scan(mod_iter))) {
        const char *mod_name = vpi_get_str(vpiName, mod);
        /* Look in top-level module */
        vpiHandle mem_iter = vpi_iterate(vpiMemory, mod);
        if (mem_iter) {
            vpiHandle mem;
            while ((mem = vpi_scan(mem_iter))) {
                const char *mem_name = vpi_get_str(vpiName, mem);
                if (strcmp(mem_name, "dpram_mem") == 0) {
                    dpram_handle = mem;
                    vpi_free_object(mod_iter);
                    return mem;
                }
            }
        }
        vpi_free_object(mod);
    }
    return NULL;
}

/* Read one 256-bit DPRAM word → 4 uint64_t */
static void dpram_read(int addr, uint64_t *qw) {
    vpiHandle mem = get_dpram_array();
    if (!mem) { memset(qw, 0, 32); return; }

    /* Read word through VPI memory access */
    vpiHandle word_h = vpi_handle_by_index(mem, addr);
    if (!word_h) { memset(qw, 0, 32); return; }

    /* The word is 256 bits wide, get its value */
    s_vpi_value val;
    val.format = vpiVectorVal;
    vpi_get_value(word_h, &val);

    /* aval/bval are s_vpi_vecval structures with .aval and .bval as 32-bit chunks */
    /* For 256 bits, we need 8 32-bit aval/bval pairs */
    /* Actually, iverilog packs into 32-bit words in the val.value.vector */
    for (int i = 0; i < 4; i++) {
        uint64_t lo = (uint64_t)val.value.vector[i * 2].aval;
        uint64_t hi = (uint64_t)val.value.vector[i * 2 + 1].aval;
        qw[i] = lo | (hi << 32);
    }
}

/* Write one 256-bit DPRAM word from 4 uint64_t */
static void dpram_write(int addr, const uint64_t *qw) {
    vpiHandle mem = get_dpram_array();
    if (!mem) return;

    vpiHandle word_h = vpi_handle_by_index(mem, addr);
    if (!word_h) return;

    s_vpi_value val;
    val.format = vpiVectorVal;
    for (int i = 0; i < 4; i++) {
        val.value.vector[i * 2].aval = (uint32_t)(qw[i] & 0xFFFFFFFFULL);
        val.value.vector[i * 2].bval = 0;
        val.value.vector[i * 2 + 1].aval = (uint32_t)(qw[i] >> 32);
        val.value.vector[i * 2 + 1].bval = 0;
    }
    vpi_put_value(word_h, &val, NULL, vpiNoDelay);
}

/* ---- Convenience: read/write Q values ---- */

/* Read N uint16 Q values from DPRAM starting at word address 'base' */
static void dpram_read_q(int base, uint16_t *out, int len) {
    for (int i = 0; i < len; i++) {
        int word_addr = base + (i / 16);
        int lane = i % 16;
        uint64_t qw[4];
        dpram_read(word_addr, qw);
        out[i] = ((uint16_t*)qw)[lane] & 0xFFF;
    }
}

/* Write N uint16 Q values to DPRAM starting at word address 'base' */
static void dpram_write_q(int base, const uint16_t *vals, int len) {
    for (int i = 0; i < len; i += 16) {
        int word_addr = base + (i / 16);
        uint64_t qw[4] = {0, 0, 0, 0};
        for (int j = 0; j < 16 && (i + j) < len; j++) {
            ((uint16_t*)qw)[j] = vals[i + j] & 0xFFF;
        }
        dpram_write(word_addr, qw);
    }
}

/* Read bytes from DPRAM */
static void dpram_read_bytes(int base, uint8_t *out, int byte_len) {
    for (int i = 0; i < byte_len; i++) {
        int word_addr = base + (i / 32);
        int byte_off = i % 32;
        uint64_t qw[4];
        dpram_read(word_addr, qw);
        out[i] = ((uint8_t*)qw)[byte_off];
    }
}

/* Write bytes to DPRAM */
static void dpram_write_bytes(int base, const uint8_t *bytes, int byte_len) {
    for (int i = 0; i < byte_len; i += 32) {
        int word_addr = base + (i / 32);
        uint64_t qw[4] = {0, 0, 0, 0};
        for (int j = 0; j < 32 && (i + j) < byte_len; j++) {
            ((uint8_t*)qw)[j] = bytes[i + j];
        }
        dpram_write(word_addr, qw);
    }
}

/* Read ternary values from DPRAM (packed 2-bit), start from word 'base' */
static void dpram_read_ternary(int base, int16_t *out, int len) {
    for (int i = 0; i < len; i++) {
        int bit = i * 2;
        int word_addr = base + (bit / 256);
        int bit_in_word = bit % 256;
        int byte_off = bit_in_word / 8;
        int bit_in_byte = bit_in_word % 8;
        uint64_t qw[4];
        dpram_read(word_addr, qw);
        uint8_t byte_val = ((uint8_t*)qw)[byte_off];
        uint8_t val = (byte_val >> bit_in_byte) & 0x03;
        if (val == 0x01) out[i] = 1;
        else if (val == 0x02) out[i] = -1;
        else out[i] = 0;
    }
}

/* Write ternary values to DPRAM */
static void dpram_write_ternary(int base, const int16_t *vals, int len) {
    for (int i = 0; i < len; i++) {
        int bit = i * 2;
        int word_addr = base + (bit / 256);
        int bit_in_word = bit % 256;
        int byte_off = bit_in_word / 8;
        int bit_in_byte = bit_in_word % 8;
        uint64_t qw[4];
        dpram_read(word_addr, qw);
        uint8_t byte_val = ((uint8_t*)qw)[byte_off];
        uint8_t bits;
        if (vals[i] == 1) bits = 0x01;
        else if (vals[i] == -1) bits = 0x02;
        else bits = 0x00;
        byte_val = (byte_val & ~(0x03 << bit_in_byte)) | (bits << bit_in_byte);
        ((uint8_t*)qw)[byte_off] = byte_val;
        dpram_write(word_addr, qw);
    }
}

/* =========================================================================
 * VPI Argument Helpers
 * ========================================================================= */

static int vpi_get_int(vpiHandle systf, int arg_idx) {
    vpiHandle arg = vpi_handle_by_index(systf, arg_idx);
    if (!arg) return 0;
    s_vpi_value val;
    val.format = vpiIntVal;
    vpi_get_value(arg, &val);
    return val.value.integer;
}

static void vpi_put_int(vpiHandle systf, int arg_idx, int value) {
    vpiHandle arg = vpi_handle_by_index(systf, arg_idx);
    if (!arg) return;
    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = value;
    vpi_put_value(arg, &val, NULL, vpiNoDelay);
}

/* =========================================================================
 * VPI System Tasks
 * ========================================================================= */

/* $sw_init_params(ss) */
static int vpi_init_params(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int ss = vpi_get_int(systf, 1);

    g_logq = 12;
    if (ss == 16) {
        g_m = 600; g_n = 600; g_mbar = 8; g_nbar = 8;
        g_h1 = 128; g_h2 = 128; g_eta1 = 2; g_eta2 = 2;
        g_tau = 3; g_mu = 64; g_muConut = 2;
    } else if (ss == 24) {
        g_m = 928; g_n = 896; g_mbar = 8; g_nbar = 8;
        g_h1 = 128; g_h2 = 128; g_eta1 = 2; g_eta2 = 2;
        g_tau = 4; g_mu = 96; g_muConut = 2;
    } else {
        g_m = 1136; g_n = 1120; g_mbar = 12; g_nbar = 11;
        g_h1 = 128; g_h2 = 128; g_eta1 = 2; g_eta2 = 2;
        g_tau = 3; g_mu = 64; g_muConut = 4;
    }
    vpi_printf("[VPI] Init params ss=%d: m=%d n=%d mbar=%d nbar=%d tau=%d muConut=%d\n",
               ss, g_m, g_n, g_mbar, g_nbar, g_tau, g_muConut);
    return 0;
}

/* $sw_get_param(which) → returns the parameter value */
static int vpi_get_param(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int which = vpi_get_int(systf, 1);
    int val = 0;
    switch (which) {
        case 0: val = g_m; break;
        case 1: val = g_n; break;
        case 2: val = g_mbar; break;
        case 3: val = g_nbar; break;
        case 4: val = g_tau; break;
        case 5: val = g_mu; break;
        case 6: val = g_muConut; break;
        case 7: val = g_h1; break;
        case 8: val = g_h2; break;
        case 9: val = g_eta1; break;
        case 10: val = g_eta2; break;
        case 11: val = g_logq; break;
        default: val = -1;
    }
    /* Return as 32-bit through the DPRAM scratch area */
    uint64_t qw[4] = {0};
    qw[0] = (uint64_t)(uint32_t)val;
    dpram_write(1023, qw);  /* last DPRAM word = scratch */
    return 0;
}

/* $sw_random(byte_addr) — generate 32 random bytes → DPRAM[byte_addr] */
static int vpi_random(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int addr = vpi_get_int(systf, 1);
    uint8_t buf[32];
    get_random(buf, 32);
    dpram_write_bytes(addr, buf, 32);
    vpi_printf("[VPI] random() → DPRAM[%d]\n", addr);
    return 0;
}

/* $sw_shake256(in_addr, in_bytes, out_addr, out_bytes) */
static int vpi_shake256(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int in_addr   = vpi_get_int(systf, 1);
    int in_bytes  = vpi_get_int(systf, 2);
    int out_addr  = vpi_get_int(systf, 3);
    int out_bytes = vpi_get_int(systf, 4);

    uint8_t *in_buf  = (uint8_t *)malloc(in_bytes);
    uint8_t *out_buf = (uint8_t *)malloc(out_bytes);
    dpram_read_bytes(in_addr, in_buf, in_bytes);
    sw_shake256_hash(in_buf, in_bytes, out_buf, out_bytes);
    dpram_write_bytes(out_addr, out_buf, out_bytes);
    free(in_buf); free(out_buf);
    return 0;
}

/* $sw_sample_psi(seed_addr) — S goes to DPRAM addr 0 (ternary packed) */
static int vpi_sample_psi(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int seed_addr = vpi_get_int(systf, 1);
    uint8_t seed[32];
    dpram_read_bytes(seed_addr, seed, 32);

    int16_t *S = (int16_t *)calloc(g_n * g_nbar, sizeof(int16_t));
    /* Build a minimal para struct on the fly */
    struct { int n, nbar, h1, h2, eta1, eta2, m, mbar, tau, mu, muConut; } para;
    para.n = g_n; para.nbar = g_nbar; para.h1 = g_h1; para.h2 = g_h2;
    para.eta1 = g_eta1; para.eta2 = g_eta2;
    para.m = g_m; para.mbar = g_mbar;
    sw_sample_psi(seed, &para, S);

    dpram_write_ternary(0, S, g_n * g_nbar);
    free(S);
    vpi_printf("[VPI] sample_psi() → DPRAM[0] (%d ternary values)\n", g_n * g_nbar);
    return 0;
}

/* $sw_sample_phi(seed_addr) — S' goes to DPRAM ternary area */
static int vpi_sample_phi(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int seed_addr = vpi_get_int(systf, 1);
    uint8_t seed[32];
    dpram_read_bytes(seed_addr, seed, 32);

    int16_t *Sp = (int16_t *)calloc(g_mbar * g_m, sizeof(int16_t));
    struct { int n, nbar, h1, h2, eta1, eta2, m, mbar, tau, mu, muConut; } para;
    para.n = g_n; para.nbar = g_nbar; para.h1 = g_h1; para.h2 = g_h2;
    para.eta1 = g_eta1; para.eta2 = g_eta2;
    para.m = g_m; para.mbar = g_mbar;
    sw_sample_phi(seed, &para, Sp);

    /* Store after S */
    int base = (g_n * g_nbar * 2 + 255) / 256;  /* words needed for S */
    dpram_write_ternary(base, Sp, g_mbar * g_m);
    free(Sp);
    vpi_printf("[VPI] sample_phi() → DPRAM[%d] (%d ternary)\n", base, g_mbar * g_m);
    return 0;
}

/* $sw_sample_eta1(seed_addr) — E noise → DPRAM Q area */
static int vpi_sample_eta1(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int seed_addr = vpi_get_int(systf, 1);
    uint8_t seed[32];
    dpram_read_bytes(seed_addr, seed, 32);

    uint16_t *E = (uint16_t *)calloc(g_m * g_nbar, sizeof(uint16_t));
    struct { int n, nbar, h1, h2, eta1, eta2, m, mbar, tau, mu, muConut; } para;
    para.n = g_n; para.nbar = g_nbar; para.h1 = g_h1; para.h2 = g_h2;
    para.eta1 = g_eta1; para.eta2 = g_eta2;
    para.m = g_m; para.mbar = g_mbar;
    sw_sample_eta1(seed, &para, E);

    /* Store in Q area at DPRAM word 512 */
    dpram_write_q(512, E, g_m * g_nbar);
    free(E);
    vpi_printf("[VPI] sample_eta1() → DPRAM[512] (%d Q values)\n", g_m * g_nbar);
    return 0;
}

/* $sw_sample_eta2(seed_addr) — E1,E2 → DPRAM */
static int vpi_sample_eta2(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int seed_addr = vpi_get_int(systf, 1);
    uint8_t seed[32];
    dpram_read_bytes(seed_addr, seed, 32);

    uint16_t *E1 = (uint16_t *)calloc(g_mbar * g_n, sizeof(uint16_t));
    uint16_t *E2 = (uint16_t *)calloc(g_mbar * g_nbar, sizeof(uint16_t));
    struct { int n, nbar, h1, h2, eta1, eta2, m, mbar, tau, mu, muConut; } para;
    para.n = g_n; para.nbar = g_nbar; para.h1 = g_h1; para.h2 = g_h2;
    para.eta1 = g_eta1; para.eta2 = g_eta2;
    para.m = g_m; para.mbar = g_mbar;
    sw_sample_eta2(seed, &para, E1, E2);

    dpram_write_q(512, E1, g_mbar * g_n);
    dpram_write_q(512 + (g_mbar * g_n + 15) / 16, E2, g_mbar * g_nbar);
    free(E1); free(E2);
    vpi_printf("[VPI] sample_eta2() → DPRAM[512]\n");
    return 0;
}

/* $sw_generate_a(seed_addr, row_start, n_rows, n_cols, out_word_addr) */
static int vpi_generate_a(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int seed_addr = vpi_get_int(systf, 1);
    int row_start = vpi_get_int(systf, 2);
    int n_rows    = vpi_get_int(systf, 3);
    int n_cols    = vpi_get_int(systf, 4);
    int out_addr  = vpi_get_int(systf, 5);

    uint8_t seed[16];
    dpram_read_bytes(seed_addr, seed, 16);

    uint16_t *a_out = (uint16_t *)malloc(n_rows * n_cols * sizeof(uint16_t));
    sw_generate_a_rows(seed, row_start, n_rows, n_cols, a_out);
    dpram_write_q(out_addr, a_out, n_rows * n_cols);
    free(a_out);
    return 0;
}

/* $sw_msgencode_sw(msg_addr, tau, muConut, q_out_addr) — SW reference encode */
static int vpi_msgencode_sw(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int msg_addr  = vpi_get_int(systf, 1);
    int tau       = vpi_get_int(systf, 2);
    int muConut   = vpi_get_int(systf, 3);
    int q_out     = vpi_get_int(systf, 4);

    int mu_bytes = (tau == 3) ? 8 : 12;
    uint8_t *msg = (uint8_t *)malloc(mu_bytes * muConut);
    dpram_read_bytes(msg_addr, msg, mu_bytes * muConut);

    int bw_real = 32;
    uint16_t *matrixM = (uint16_t *)calloc(muConut * bw_real, sizeof(uint16_t));

    /* Use the HAL SW reference */
    hal_sw_msgencode(msg, NULL, matrixM);

    dpram_write_q(q_out, matrixM, muConut * bw_real);
    free(msg); free(matrixM);
    return 0;
}

/* $sw_msgdecode_sw(q_addr, tau, muConut, msg_out_addr) — SW reference decode */
static int vpi_msgdecode_sw(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int q_addr    = vpi_get_int(systf, 1);
    int tau       = vpi_get_int(systf, 2);
    int muConut   = vpi_get_int(systf, 3);
    int msg_out   = vpi_get_int(systf, 4);

    int mu_bytes = (tau == 3) ? 8 : 12;
    int bw_real = 32;
    uint16_t *matrixM = (uint16_t *)malloc(muConut * bw_real * sizeof(uint16_t));
    dpram_read_q(q_addr, matrixM, muConut * bw_real);

    uint8_t *msg = (uint8_t *)calloc(mu_bytes * muConut, 1);
    hal_sw_msgdecode(matrixM, NULL, msg);

    dpram_write_bytes(msg_out, msg, mu_bytes * muConut);
    free(matrixM); free(msg);
    return 0;
}

/* $sw_pack_pk(B_q_addr) — pack Q values into pk bytes */
static int vpi_pack_pk(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int b_addr = vpi_get_int(systf, 1);

    uint16_t *B = (uint16_t *)malloc(g_m * g_nbar * sizeof(uint16_t));
    dpram_read_q(b_addr, B, g_m * g_nbar);

    int pk_len = (g_m * g_nbar * 3 + 1) / 2;
    uint8_t *pk = (uint8_t *)malloc(pk_len);
    sw_pack_pk(B, NULL, pk);
    dpram_write_bytes(900, pk, pk_len);  /* store at word 900 */
    free(B); free(pk);
    return 0;
}

/* $sw_unpack_pk(pk_addr) — unpack pk bytes → Q values */
static int vpi_unpack_pk(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int pk_addr = vpi_get_int(systf, 1);

    int pk_len = (g_m * g_nbar * 3 + 1) / 2;
    uint8_t *pk = (uint8_t *)malloc(pk_len);
    dpram_read_bytes(pk_addr, pk, pk_len);

    uint16_t *B = (uint16_t *)calloc(g_m * g_nbar, sizeof(uint16_t));
    sw_unpack_pk(pk, NULL, B);
    dpram_write_q(0, B, g_m * g_nbar);
    free(pk); free(B);
    return 0;
}

/* $sw_add_mod_q(a_addr, b_addr, len, out_addr) */
static int vpi_add_mod_q(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int a_addr   = vpi_get_int(systf, 1);
    int b_addr   = vpi_get_int(systf, 2);
    int len      = vpi_get_int(systf, 3);
    int out_addr = vpi_get_int(systf, 4);

    uint16_t *a = (uint16_t *)malloc(len * sizeof(uint16_t));
    uint16_t *b = (uint16_t *)malloc(len * sizeof(uint16_t));
    uint16_t *out = (uint16_t *)malloc(len * sizeof(uint16_t));
    dpram_read_q(a_addr, a, len);
    dpram_read_q(b_addr, b, len);
    for (int i = 0; i < len; i++) out[i] = (a[i] + b[i]) & MOD_Q;
    dpram_write_q(out_addr, out, len);
    free(a); free(b); free(out);
    return 0;
}

/* $sw_sub_mod_q(a_addr, b_addr, len, out_addr) */
static int vpi_sub_mod_q(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int a_addr   = vpi_get_int(systf, 1);
    int b_addr   = vpi_get_int(systf, 2);
    int len      = vpi_get_int(systf, 3);
    int out_addr = vpi_get_int(systf, 4);

    uint16_t *a = (uint16_t *)malloc(len * sizeof(uint16_t));
    uint16_t *b = (uint16_t *)malloc(len * sizeof(uint16_t));
    uint16_t *out = (uint16_t *)malloc(len * sizeof(uint16_t));
    dpram_read_q(a_addr, a, len);
    dpram_read_q(b_addr, b, len);
    for (int i = 0; i < len; i++) out[i] = (a[i] - b[i]) & MOD_Q;
    dpram_write_q(out_addr, out, len);
    free(a); free(b); free(out);
    return 0;
}

/* $sw_verify(addr1, addr2, byte_len) — compare, return 1 if match */
static int vpi_verify(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int addr1 = vpi_get_int(systf, 1);
    int addr2 = vpi_get_int(systf, 2);
    int len   = vpi_get_int(systf, 3);

    uint8_t *a = (uint8_t *)malloc(len);
    uint8_t *b = (uint8_t *)malloc(len);
    dpram_read_bytes(addr1, a, len);
    dpram_read_bytes(addr2, b, len);

    int match = (memcmp(a, b, len) == 0) ? 1 : 0;
    /* Store result in scratch */
    uint64_t qw[4] = {0};
    qw[0] = (uint64_t)match;
    dpram_write(1022, qw);
    free(a); free(b);

    if (!match) {
        vpi_printf("[VPI] VERIFY FAIL at addr %d vs %d, len=%d\n", addr1, addr2, len);
        vpi_printf("[VPI]   First 16 bytes A: ");
        for (int i = 0; i < 16 && i < len; i++) vpi_printf("%02x ", a[i]);
        vpi_printf("\n");
        vpi_printf("[VPI]   First 16 bytes B: ");
        for (int i = 0; i < 16 && i < len; i++) vpi_printf("%02x ", b[i]);
        vpi_printf("\n");
    }
    return 0;
}

/* $sw_print_bytes(addr, len, label) — debug print */
static int vpi_print_bytes(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int addr = vpi_get_int(systf, 1);
    int len  = vpi_get_int(systf, 2);
    int label_addr = vpi_get_int(systf, 3);

    uint8_t *data = (uint8_t *)malloc(len);
    dpram_read_bytes(addr, data, len);
    if (len > 64) len = 64;  /* truncate display */

    char label[64] = "";
    if (label_addr > 0) dpram_read_bytes(label_addr, label, 32);

    vpi_printf("[VPI] %s (%d bytes): ", label, len);
    for (int i = 0; i < len; i++) vpi_printf("%02x", data[i]);
    vpi_printf("\n");
    free(data);
    return 0;
}

/* $sw_print_q(addr, len, label_addr) — debug print Q values */
static int vpi_print_q(char *user_data) {
    (void)user_data;
    vpiHandle systf = vpi_handle(vpiSysTfCall, NULL);
    int addr = vpi_get_int(systf, 1);
    int len  = vpi_get_int(systf, 2);

    uint16_t *qvals = (uint16_t *)malloc(len * sizeof(uint16_t));
    dpram_read_q(addr, qvals, len);
    if (len > 16) len = 16;

    vpi_printf("[VPI] Q values: ");
    for (int i = 0; i < len; i++) vpi_printf("%03x ", qvals[i] & 0xFFF);
    vpi_printf("\n");
    free(qvals);
    return 0;
}

/* =========================================================================
 * VPI Task Registration Table
 * ========================================================================= */

static void register_task(int type, const char *name, int (*func)(char *)) {
    s_vpi_systf_data tf_data;
    tf_data.type      = type;
    tf_data.sysfunctype = (type == vpiSysFunc) ? vpiIntFunc : 0;
    tf_data.tfname     = (char *)name;
    tf_data.calltf     = func;
    tf_data.compiletf  = NULL;
    tf_data.sizetf     = NULL;
    tf_data.user_data  = NULL;
    vpi_register_systf(&tf_data);
}

#define REG_TASK(name, func) register_task(vpiSysTask, name, func)

static void register_all_tasks(void) {
    REG_TASK("$sw_init_params",    vpi_init_params);
    REG_TASK("$sw_get_param",      vpi_get_param);
    REG_TASK("$sw_random",         vpi_random);
    REG_TASK("$sw_shake256",       vpi_shake256);
    REG_TASK("$sw_sample_psi",     vpi_sample_psi);
    REG_TASK("$sw_sample_phi",     vpi_sample_phi);
    REG_TASK("$sw_sample_eta1",    vpi_sample_eta1);
    REG_TASK("$sw_sample_eta2",    vpi_sample_eta2);
    REG_TASK("$sw_generate_a",     vpi_generate_a);
    REG_TASK("$sw_msgencode_sw",   vpi_msgencode_sw);
    REG_TASK("$sw_msgdecode_sw",  vpi_msgdecode_sw);
    REG_TASK("$sw_pack_pk",        vpi_pack_pk);
    REG_TASK("$sw_unpack_pk",      vpi_unpack_pk);
    REG_TASK("$sw_add_mod_q",      vpi_add_mod_q);
    REG_TASK("$sw_sub_mod_q",      vpi_sub_mod_q);
    REG_TASK("$sw_verify",         vpi_verify);
    REG_TASK("$sw_print_bytes",    vpi_print_bytes);
    REG_TASK("$sw_print_q",        vpi_print_q);
    vpi_printf("[VPI] Scloud+ VPI module loaded (%d tasks registered)\n", 18);
}

/* =========================================================================
 * VPI Bootstrap — called once at simulation start
 * ========================================================================= */

/* vlog_startup_routines is the standard iverilog entry point */
void (*vlog_startup_routines[])(void) = {
    register_all_tasks,
    NULL
};
