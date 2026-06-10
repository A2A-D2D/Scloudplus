/*
 * Compare RTL MatM expected vectors with openHiTLS-style Scloud+ C loops.
 *
 * This file mirrors the matrix-multiply loop semantics from openHiTLS/PQCP:
 *   SCLOUDPLUS_AS_E, SCLOUDPLUS_SA_E, SCLOUDPLUS_CS, SCLOUDPLUS_SB_E
 *
 * It does not depend on openHiTLS AES/SHAKE/provider code; deterministic test
 * matrices are used so the comparison stays small and reproducible.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define B 8u
#define Q_MASK 0xFFFu
#define MAX_ROWS 1200u
#define MAX_COLS 1200u

static unsigned int mat_a[MAX_ROWS][MAX_COLS];
static unsigned int mat_s[MAX_ROWS][MAX_COLS];
static unsigned int out_std[MAX_ROWS][MAX_COLS];

static unsigned int make_q(unsigned int r, unsigned int c, unsigned int salt)
{
    return (43u * r + 97u * c + 29u * salt + 11u * r * c + 5u) & Q_MASK;
}

static unsigned int make_s(unsigned int r, unsigned int c, unsigned int salt)
{
    static const unsigned int lut[11] = {0u, 1u, Q_MASK, 0u, 1u, Q_MASK, 1u, 0u, Q_MASK, 1u, 0u};
    return lut[(7u * r + 5u * c + salt) % 11u];
}

static unsigned int ceil_div_b(unsigned int value)
{
    return (value + B - 1u) / B;
}

static void clear_all(void)
{
    memset(mat_a, 0, sizeof(mat_a));
    memset(mat_s, 0, sizeof(mat_s));
    memset(out_std, 0, sizeof(out_std));
}

static void openhitls_as(unsigned int rows, unsigned int inner, unsigned int cols)
{
    unsigned int i;
    unsigned int j;
    unsigned int k;
    unsigned int sum;

    for (i = 0; i < rows; i = i + 1u) {
        for (j = 0; j < cols; j = j + 1u) {
            sum = 0u;
            for (k = 0; k < inner; k = k + 1u) {
                sum = (sum + mat_a[i][k] * mat_s[j][k]) & Q_MASK;
            }
            out_std[i][j] = sum;
        }
    }
}

static void openhitls_sa_transpose(unsigned int rows, unsigned int inner, unsigned int cols)
{
    unsigned int i;
    unsigned int j;
    unsigned int k;
    unsigned int sum;

    for (i = 0; i < rows; i = i + 1u) {
        for (j = 0; j < cols; j = j + 1u) {
            sum = 0u;
            for (k = 0; k < inner; k = k + 1u) {
                sum = (sum + mat_s[j][k] * mat_a[k][i]) & Q_MASK;
            }
            out_std[i][j] = sum;
        }
    }
}

static void openhitls_cs(unsigned int rows, unsigned int inner, unsigned int cols)
{
    unsigned int i;
    unsigned int j;
    unsigned int k;
    unsigned int sum;

    for (i = 0; i < rows; i = i + 1u) {
        for (j = 0; j < cols; j = j + 1u) {
            sum = 0u;
            for (k = 0; k < inner; k = k + 1u) {
                sum = (sum + mat_a[i][k] * mat_s[j][k]) & Q_MASK;
            }
            out_std[i][j] = sum;
        }
    }
}

static void openhitls_sb_transpose(unsigned int rows, unsigned int inner, unsigned int cols)
{
    unsigned int i;
    unsigned int j;
    unsigned int k;
    unsigned int sum;

    for (i = 0; i < rows; i = i + 1u) {
        for (j = 0; j < cols; j = j + 1u) {
            sum = 0u;
            for (k = 0; k < inner; k = k + 1u) {
                sum = (sum + mat_s[j][k] * mat_a[k][i]) & Q_MASK;
            }
            out_std[i][j] = sum;
        }
    }
}

static void fill_as(unsigned int rows, unsigned int inner, unsigned int cols, unsigned int salt)
{
    unsigned int r;
    unsigned int c;

    clear_all();
    for (r = 0; r < rows; r = r + 1u) {
        for (c = 0; c < inner; c = c + 1u) {
            mat_a[r][c] = make_q(r, c, salt);
        }
    }
    for (r = 0; r < cols; r = r + 1u) {
        for (c = 0; c < inner; c = c + 1u) {
            mat_s[r][c] = make_s(c, r, salt + 1u);
        }
    }
}

static void fill_sa(unsigned int rows, unsigned int inner, unsigned int cols, unsigned int salt)
{
    unsigned int r;
    unsigned int c;

    clear_all();
    for (r = 0; r < inner; r = r + 1u) {
        for (c = 0; c < rows; c = c + 1u) {
            mat_a[r][c] = make_q(r, c, salt);
        }
    }
    for (r = 0; r < cols; r = r + 1u) {
        for (c = 0; c < inner; c = c + 1u) {
            mat_s[r][c] = make_s(r, c, salt + 1u);
        }
    }
}

static void print_hex_line(char *line, const unsigned int *vals, unsigned int count)
{
    unsigned int hex_digits;
    unsigned int idx;
    unsigned int bit;
    unsigned int nib_idx;
    unsigned int value;
    unsigned char nibbles[192];

    hex_digits = (count * 12u + 3u) >> 2;
    memset(nibbles, 0, sizeof(nibbles));
    for (idx = 0; idx < count; idx = idx + 1u) {
        value = vals[idx] & Q_MASK;
        for (bit = 0; bit < 12u; bit = bit + 1u) {
            if (((value >> bit) & 1u) != 0u) {
                nib_idx = (idx * 12u + bit) >> 2;
                nibbles[nib_idx] |= (unsigned char)(1u << ((idx * 12u + bit) & 3u));
            }
        }
    }
    for (idx = 0; idx < hex_digits; idx = idx + 1u) {
        value = nibbles[hex_digits - 1u - idx] & 15u;
        line[idx] = (char)((value < 10u) ? ('0' + value) : ('a' + value - 10u));
    }
    line[hex_digits] = '\0';
}

static int compare_exp_file(const char *name, const char *path,
                            unsigned int rows, unsigned int cols)
{
    FILE *fp;
    char got[256];
    char exp[256];
    unsigned int vals[B * B];
    unsigned int rb;
    unsigned int cb;
    unsigned int r;
    unsigned int c;
    unsigned int idx;
    unsigned int row_blocks;
    unsigned int col_blocks;
    int errors;

    fp = fopen(path, "r");
    if (fp == NULL) {
        fprintf(stderr, "cannot open %s\n", path);
        return 1;
    }
    errors = 0;
    row_blocks = ceil_div_b(rows);
    col_blocks = ceil_div_b(cols);
    for (rb = 0; rb < row_blocks; rb = rb + 1u) {
        for (cb = 0; cb < col_blocks; cb = cb + 1u) {
            idx = 0u;
            for (r = 0; r < B; r = r + 1u) {
                for (c = 0; c < B; c = c + 1u) {
                    vals[idx] = out_std[rb * B + r][cb * B + c];
                    idx = idx + 1u;
                }
            }
            print_hex_line(exp, vals, B * B);
            if (fgets(got, sizeof(got), fp) == NULL) {
                fprintf(stderr, "missing line in %s\n", path);
                errors = errors + 1;
                continue;
            }
            got[strcspn(got, "\r\n")] = '\0';
            if (strcmp(got, exp) != 0) {
                fprintf(stderr, "MISMATCH %s rb=%u cb=%u\n", name, rb, cb);
                fprintf(stderr, "  file=%s\n", got);
                fprintf(stderr, "  std =%s\n", exp);
                errors = errors + 1;
            }
        }
    }
    fclose(fp);
    return errors;
}

static int run_set(const char *prefix, unsigned int m, unsigned int n,
                   unsigned int mbar, unsigned int nbar, unsigned int salt)
{
    char path[256];
    int errors;

    errors = 0;
    fill_as(16u, n, nbar, salt);
    openhitls_as(16u, n, nbar);
    snprintf(path, sizeof(path), "tb/vectors_scloudplus_official_c/%s_keygen_as_exp.mem", prefix);
    errors += compare_exp_file("AS_E", path, 16u, nbar);

    fill_sa(16u, m, mbar, salt + 10u);
    openhitls_sa_transpose(16u, m, mbar);
    snprintf(path, sizeof(path), "tb/vectors_scloudplus_official_c/%s_enc_c1_transpose_exp.mem", prefix);
    errors += compare_exp_file("SA_E transpose", path, 16u, mbar);

    fill_as(mbar, n, nbar, salt + 20u);
    openhitls_cs(mbar, n, nbar);
    snprintf(path, sizeof(path), "tb/vectors_scloudplus_official_c/%s_dec_c1s_exp.mem", prefix);
    errors += compare_exp_file("CS", path, mbar, nbar);

    fill_sa(nbar, m, mbar, salt + 30u);
    openhitls_sb_transpose(nbar, m, mbar);
    snprintf(path, sizeof(path), "tb/vectors_scloudplus_official_c/%s_enc_sb_transpose_exp.mem", prefix);
    errors += compare_exp_file("SB_E transpose", path, nbar, mbar);

    return errors;
}

int main(void)
{
    int errors;

    errors = 0;
    errors += run_set("scloudplus128", 600u, 600u, 8u, 8u, 31u);
    errors += run_set("scloudplus192", 928u, 896u, 8u, 8u, 61u);
    errors += run_set("scloudplus256", 1136u, 1120u, 12u, 11u, 91u);
    if (errors == 0) {
        printf("OPENHITLS_C_COMPARE_PASS\n");
        return 0;
    }
    printf("OPENHITLS_C_COMPARE_FAIL errors=%d\n", errors);
    return 1;
}
