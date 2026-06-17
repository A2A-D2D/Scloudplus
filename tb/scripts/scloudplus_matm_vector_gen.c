/*
 * Deterministic C reference vectors for the Scloud+ block matrix multiplier.
 *
 * The vectors cover the same MatM roles used by the RTL regression:
 *   - keygen_as:          A * S
 *   - enc_c1_transpose:   A' * S'
 *   - dec_c1s:            C1 * S
 *
 * This is a small standalone C golden model for RTL verification.  It is not a
 * full Scloud+ KEM/PKE KAT generator.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#endif

#define B 8
#define MAX_ROWS 1200
#define MAX_COLS 1200
#define MAX_REQ_128 150
#define MAX_EXP_128 2

static unsigned int left_mat[MAX_ROWS][MAX_COLS];
static int right_mat[MAX_ROWS][MAX_COLS];
static unsigned int out_mat[MAX_ROWS][MAX_COLS];

static unsigned int q_mod(unsigned int q_width)
{
    return 1u << q_width;
}

static unsigned int make_a8(unsigned int r, unsigned int c, unsigned int salt)
{
    return (17u * r + 31u * c + 19u * salt + 7u * r * c + 3u) & 255u;
}

static int make_s8(unsigned int r, unsigned int c, unsigned int salt)
{
    static const int lut[7] = {0, 1, -1, 0, 1, -1, 1};
    return lut[(5u * r + 3u * c + salt) % 7u];
}

static unsigned int make_a12(unsigned int r, unsigned int c, unsigned int salt)
{
    return (43u * r + 97u * c + 29u * salt + 11u * r * c + 5u) & 4095u;
}

static int make_s12(unsigned int r, unsigned int c, unsigned int salt)
{
    static const int lut[11] = {0, 1, -1, 0, 1, -1, 1, 0, -1, 1, 0};
    return lut[(7u * r + 5u * c + salt) % 11u];
}

static unsigned int coeff_enc(int value)
{
    if (value > 0) {
        return 1u;
    }
    if (value < 0) {
        return 2u;
    }
    return 0u;
}

static void clear_mats(void)
{
    memset(left_mat, 0, sizeof(left_mat));
    memset(right_mat, 0, sizeof(right_mat));
    memset(out_mat, 0, sizeof(out_mat));
}

static void ensure_dir(const char *dir)
{
#ifdef _WIN32
    _mkdir(dir);
#else
    mkdir(dir, 0777);
#endif
}

static void mat_mul_ternary(unsigned int rows, unsigned int inner,
                            unsigned int cols, unsigned int q_width)
{
    unsigned int r;
    unsigned int c;
    unsigned int k;
    unsigned int mod;
    long acc;

    mod = q_mod(q_width);
    for (r = 0; r < rows; r = r + 1u) {
        for (c = 0; c < cols; c = c + 1u) {
            acc = 0;
            for (k = 0; k < inner; k = k + 1u) {
                acc += ((long)left_mat[r][k]) * ((long)right_mat[k][c]);
            }
            while (acc < 0) {
                acc += (long)mod;
            }
            out_mat[r][c] = ((unsigned int)acc) & (mod - 1u);
        }
    }
}

static unsigned int ceil_div_b(unsigned int value)
{
    return (value + B - 1u) / B;
}

static void set_hex_bit(char *nibbles, unsigned int bit_index)
{
    unsigned int nib_idx;
    unsigned int bit_in_nib;
    unsigned int value;

    nib_idx = bit_index >> 2;
    bit_in_nib = bit_index & 3u;
    value = (unsigned int)nibbles[nib_idx];
    value |= (1u << bit_in_nib);
    nibbles[nib_idx] = (char)value;
}

static void print_hex_from_values(FILE *fp, const unsigned int *vals,
                                  unsigned int count, unsigned int width)
{
    unsigned int hex_digits;
    unsigned int idx;
    unsigned int bit;
    unsigned int nib;
    unsigned int value;
    char *nibbles;

    hex_digits = (count * width + 3u) >> 2;
    nibbles = (char *)calloc(hex_digits, sizeof(char));
    if (nibbles == NULL) {
        fprintf(stderr, "out of memory\n");
        exit(1);
    }

    for (idx = 0; idx < count; idx = idx + 1u) {
        value = vals[idx] & ((1u << width) - 1u);
        for (bit = 0; bit < width; bit = bit + 1u) {
            if (((value >> bit) & 1u) != 0u) {
                set_hex_bit(nibbles, idx * width + bit);
            }
        }
    }

    for (idx = hex_digits; idx > 0; idx = idx - 1u) {
        nib = (unsigned int)nibbles[idx - 1u] & 15u;
        fputc((int)((nib < 10u) ? ('0' + nib) : ('a' + nib - 10u)), fp);
    }

    free(nibbles);
}

static void gather_left_block(unsigned int row_blk, unsigned int col_blk,
                              unsigned int *vals)
{
    unsigned int r;
    unsigned int c;
    unsigned int idx;

    idx = 0u;
    for (r = 0; r < B; r = r + 1u) {
        for (c = 0; c < B; c = c + 1u) {
            vals[idx] = left_mat[row_blk * B + r][col_blk * B + c];
            idx = idx + 1u;
        }
    }
}

static void gather_right_block(unsigned int row_blk, unsigned int col_blk,
                               unsigned int *vals)
{
    unsigned int r;
    unsigned int c;
    unsigned int idx;

    idx = 0u;
    for (r = 0; r < B; r = r + 1u) {
        for (c = 0; c < B; c = c + 1u) {
            vals[idx] = coeff_enc(right_mat[row_blk * B + r][col_blk * B + c]);
            idx = idx + 1u;
        }
    }
}

static void gather_out_block(unsigned int row_blk, unsigned int col_blk,
                             unsigned int *vals)
{
    unsigned int r;
    unsigned int c;
    unsigned int idx;

    idx = 0u;
    for (r = 0; r < B; r = r + 1u) {
        for (c = 0; c < B; c = c + 1u) {
            vals[idx] = out_mat[row_blk * B + r][col_blk * B + c];
            idx = idx + 1u;
        }
    }
}

static void write_case_files(const char *dir, const char *name,
                             unsigned int rows, unsigned int inner,
                             unsigned int cols, unsigned int q_width,
                             unsigned int pad_req, unsigned int pad_exp)
{
    char req_path[256];
    char exp_path[256];
    FILE *req_fp;
    FILE *exp_fp;
    unsigned int vals[B * B];
    unsigned int rb;
    unsigned int ib;
    unsigned int cb;
    unsigned int req_count;
    unsigned int exp_count;

    snprintf(req_path, sizeof(req_path), "%s/%s_req.mem", dir, name);
    snprintf(exp_path, sizeof(exp_path), "%s/%s_exp.mem", dir, name);
    req_fp = fopen(req_path, "w");
    exp_fp = fopen(exp_path, "w");
    if (req_fp == NULL || exp_fp == NULL) {
        fprintf(stderr, "cannot open output files for %s\n", name);
        exit(1);
    }

    mat_mul_ternary(rows, inner, cols, q_width);
    req_count = 0u;
    exp_count = 0u;
    for (rb = 0; rb < rows / B; rb = rb + 1u) {
        for (cb = 0; cb < cols / B; cb = cb + 1u) {
            for (ib = 0; ib < inner / B; ib = ib + 1u) {
                gather_left_block(rb, ib, vals);
                print_hex_from_values(req_fp, vals, B * B, q_width);
                fputc('_', req_fp);
                gather_right_block(ib, cb, vals);
                print_hex_from_values(req_fp, vals, B * B, 2u);
                fputc('\n', req_fp);
                req_count = req_count + 1u;
            }
            gather_out_block(rb, cb, vals);
            print_hex_from_values(exp_fp, vals, B * B, q_width);
            fputc('\n', exp_fp);
            exp_count = exp_count + 1u;
        }
    }

    while (req_count < pad_req) {
        fputs("0\n", req_fp);
        req_count = req_count + 1u;
    }
    while (exp_count < pad_exp) {
        fputs("0\n", exp_fp);
        exp_count = exp_count + 1u;
    }

    fclose(req_fp);
    fclose(exp_fp);
    printf("%s rows=%u inner=%u cols=%u q_width=%u req=%u exp=%u\n",
           name, rows, inner, cols, q_width,
           (rows / B) * (inner / B) * (cols / B),
           (rows / B) * (cols / B));
}

static void write_case_files_padded(const char *dir, const char *name,
                                    unsigned int rows, unsigned int inner,
                                    unsigned int cols, unsigned int q_width)
{
    char req_path[256];
    char exp_path[256];
    FILE *req_fp;
    FILE *exp_fp;
    unsigned int vals[B * B];
    unsigned int rb;
    unsigned int ib;
    unsigned int cb;
    unsigned int row_blocks;
    unsigned int inner_blocks;
    unsigned int col_blocks;

    row_blocks = ceil_div_b(rows);
    inner_blocks = ceil_div_b(inner);
    col_blocks = ceil_div_b(cols);

    snprintf(req_path, sizeof(req_path), "%s/%s_req.mem", dir, name);
    snprintf(exp_path, sizeof(exp_path), "%s/%s_exp.mem", dir, name);
    req_fp = fopen(req_path, "w");
    exp_fp = fopen(exp_path, "w");
    if (req_fp == NULL || exp_fp == NULL) {
        fprintf(stderr, "cannot open output files for %s\n", name);
        exit(1);
    }

    mat_mul_ternary(row_blocks * B, inner_blocks * B, col_blocks * B, q_width);
    for (rb = 0; rb < row_blocks; rb = rb + 1u) {
        for (cb = 0; cb < col_blocks; cb = cb + 1u) {
            for (ib = 0; ib < inner_blocks; ib = ib + 1u) {
                gather_left_block(rb, ib, vals);
                print_hex_from_values(req_fp, vals, B * B, q_width);
                fputc('_', req_fp);
                gather_right_block(ib, cb, vals);
                print_hex_from_values(req_fp, vals, B * B, 2u);
                fputc('\n', req_fp);
            }
            gather_out_block(rb, cb, vals);
            print_hex_from_values(exp_fp, vals, B * B, q_width);
            fputc('\n', exp_fp);
        }
    }

    fclose(req_fp);
    fclose(exp_fp);
    printf("%s rows=%u inner=%u cols=%u padded=(%u,%u,%u) q_width=%u req=%u exp=%u\n",
           name, rows, inner, cols,
           row_blocks * B, inner_blocks * B, col_blocks * B, q_width,
           row_blocks * inner_blocks * col_blocks,
           row_blocks * col_blocks);
}

static void fill_keygen_8(void)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < 16u; r = r + 1u) {
        for (c = 0; c < 16u; c = c + 1u) {
            left_mat[r][c] = make_a8(r, c, 1u);
        }
    }
    for (r = 0; r < 16u; r = r + 1u) {
        for (c = 0; c < 8u; c = c + 1u) {
            right_mat[r][c] = make_s8(r, c, 2u);
        }
    }
}

static void fill_enc_transpose_8(void)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < 16u; r = r + 1u) {
        for (c = 0; c < 16u; c = c + 1u) {
            left_mat[r][c] = make_a8(c, r, 3u);
        }
    }
    for (r = 0; r < 16u; r = r + 1u) {
        for (c = 0; c < 8u; c = c + 1u) {
            right_mat[r][c] = make_s8(c, r, 4u);
        }
    }
}

static void fill_dec_8(void)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < 8u; r = r + 1u) {
        for (c = 0; c < 16u; c = c + 1u) {
            left_mat[r][c] = make_a8(r, c, 5u);
        }
    }
    for (r = 0; r < 16u; r = r + 1u) {
        for (c = 0; c < 8u; c = c + 1u) {
            right_mat[r][c] = make_s8(r, c, 6u);
        }
    }
}

static void fill_keygen_128(void)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < 16u; r = r + 1u) {
        for (c = 0; c < 600u; c = c + 1u) {
            left_mat[r][c] = make_a12(r, c, 1u);
        }
    }
    for (r = 0; r < 600u; r = r + 1u) {
        for (c = 0; c < 8u; c = c + 1u) {
            right_mat[r][c] = make_s12(r, c, 2u);
        }
    }
}

static void fill_official_keygen(unsigned int m, unsigned int n,
                                 unsigned int nbar, unsigned int salt_base)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < m; r = r + 1u) {
        for (c = 0; c < n; c = c + 1u) {
            left_mat[r][c] = make_a12(r, c, salt_base);
        }
    }
    for (r = 0; r < n; r = r + 1u) {
        for (c = 0; c < nbar; c = c + 1u) {
            right_mat[r][c] = make_s12(r, c, salt_base + 1u);
        }
    }
}

static void fill_official_enc_transpose(unsigned int m, unsigned int n,
                                        unsigned int mbar, unsigned int salt_base)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < n; r = r + 1u) {
        for (c = 0; c < m; c = c + 1u) {
            left_mat[r][c] = make_a12(c, r, salt_base);
        }
    }
    for (r = 0; r < m; r = r + 1u) {
        for (c = 0; c < mbar; c = c + 1u) {
            right_mat[r][c] = make_s12(c, r, salt_base + 1u);
        }
    }
}

static void fill_official_dec(unsigned int n, unsigned int mbar,
                              unsigned int nbar, unsigned int salt_base)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < mbar; r = r + 1u) {
        for (c = 0; c < n; c = c + 1u) {
            left_mat[r][c] = make_a12(r, c, salt_base);
        }
    }
    for (r = 0; r < n; r = r + 1u) {
        for (c = 0; c < nbar; c = c + 1u) {
            right_mat[r][c] = make_s12(r, c, salt_base + 1u);
        }
    }
}

static void fill_official_sb_transpose(unsigned int m, unsigned int mbar,
                                       unsigned int nbar, unsigned int salt_base)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < nbar; r = r + 1u) {
        for (c = 0; c < m; c = c + 1u) {
            left_mat[r][c] = make_a12(c, r, salt_base);
        }
    }
    for (r = 0; r < m; r = r + 1u) {
        for (c = 0; c < mbar; c = c + 1u) {
            right_mat[r][c] = make_s12(c, r, salt_base + 1u);
        }
    }
}

static void write_official_param_set(const char *dir, const char *prefix,
                                     unsigned int m, unsigned int n,
                                     unsigned int mbar, unsigned int nbar,
                                     unsigned int salt_base)
{
    char name[128];
    unsigned int row_slice;

    row_slice = 16u;

    snprintf(name, sizeof(name), "%s_keygen_as", prefix);
    fill_official_keygen(m, n, nbar, salt_base);
    write_case_files_padded(dir, name, row_slice, n, nbar, 12u);

    snprintf(name, sizeof(name), "%s_enc_c1_transpose", prefix);
    fill_official_enc_transpose(m, n, mbar, salt_base + 10u);
    write_case_files_padded(dir, name, row_slice, m, mbar, 12u);

    snprintf(name, sizeof(name), "%s_dec_c1s", prefix);
    fill_official_dec(n, mbar, nbar, salt_base + 20u);
    write_case_files_padded(dir, name, mbar, n, nbar, 12u);

    snprintf(name, sizeof(name), "%s_enc_sb_transpose", prefix);
    fill_official_sb_transpose(m, mbar, nbar, salt_base + 30u);
    write_case_files_padded(dir, name, nbar, m, mbar, 12u);
}

static void fill_enc_transpose_128(void)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < 16u; r = r + 1u) {
        for (c = 0; c < 600u; c = c + 1u) {
            left_mat[r][c] = make_a12(c, r, 3u);
        }
    }
    for (r = 0; r < 600u; r = r + 1u) {
        for (c = 0; c < 8u; c = c + 1u) {
            right_mat[r][c] = make_s12(c, r, 4u);
        }
    }
}

static void fill_dec_128(void)
{
    unsigned int r;
    unsigned int c;

    clear_mats();
    for (r = 0; r < 8u; r = r + 1u) {
        for (c = 0; c < 600u; c = c + 1u) {
            left_mat[r][c] = make_a12(r, c, 5u);
        }
    }
    for (r = 0; r < 600u; r = r + 1u) {
        for (c = 0; c < 8u; c = c + 1u) {
            right_mat[r][c] = make_s12(r, c, 6u);
        }
    }
}

int main(void)
{
    ensure_dir("tb/vectors/scloudplus_c");
    ensure_dir("tb/vectors/scloudplus128_c");
    ensure_dir("tb/vectors/scloudplus_official_c");

    fill_keygen_8();
    write_case_files("tb/vectors/scloudplus_c", "keygen_as",
                     16u, 16u, 8u, 8u, 0u, 0u);
    fill_enc_transpose_8();
    write_case_files("tb/vectors/scloudplus_c", "enc_c1_transpose",
                     16u, 16u, 8u, 8u, 0u, 0u);
    fill_dec_8();
    write_case_files("tb/vectors/scloudplus_c", "dec_c1s",
                     8u, 16u, 8u, 8u, 0u, 0u);

    fill_keygen_128();
    write_case_files("tb/vectors/scloudplus128_c", "keygen_as",
                     16u, 600u, 8u, 12u, MAX_REQ_128, MAX_EXP_128);
    fill_enc_transpose_128();
    write_case_files("tb/vectors/scloudplus128_c", "enc_c1_transpose",
                     16u, 600u, 8u, 12u, MAX_REQ_128, MAX_EXP_128);
    fill_dec_128();
    write_case_files("tb/vectors/scloudplus128_c", "dec_c1s",
                     8u, 600u, 8u, 12u, MAX_REQ_128, MAX_EXP_128);

    write_official_param_set("tb/vectors/scloudplus_official_c", "scloudplus128",
                             600u, 600u, 8u, 8u, 31u);
    write_official_param_set("tb/vectors/scloudplus_official_c", "scloudplus192",
                             928u, 896u, 8u, 8u, 61u);
    write_official_param_set("tb/vectors/scloudplus_official_c", "scloudplus256",
                             1136u, 1120u, 12u, 11u, 91u);

    return 0;
}
