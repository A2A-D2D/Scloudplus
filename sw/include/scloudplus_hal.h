/*
 * scloudplus_hal.h — Hardware Abstraction Layer for SCLOUD+ Accelerators
 *
 * Provides a clean C API for hardware-accelerated operations:
 *   - Matrix multiply (4 variants: AS_E, SA_E, SB_E, CS)
 *   - Message encode / decode (Barnes-Wall lattice operations)
 *
 * Two backends are supported:
 *   - SW functional model (pure C, always available)
 *   - Verilator co-simulation (when Verilator is installed)
 *   - Register-map backend (for future FPGA/ASIC integration)
 *
 * Lifecycle: hal_init() before any HAL call, hal_deinit() when done.
 */

#ifndef SCLOUDPLUS_HAL_H
#define SCLOUDPLUS_HAL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --------------------------------------------------------------------------
 * Parameter struct (mirrors SCLOUDPLUS_Para from scloudplus_local.h)
 * -------------------------------------------------------------------------- */
typedef struct {
    uint8_t  ss;          /* security level: 16, 24, or 32 */
    uint8_t  mbar;        /* rows of S' matrix */
    uint8_t  nbar;        /* cols of S matrix */
    uint16_t m;           /* rows of A (public matrix) */
    uint16_t n;           /* cols of A (public matrix) */
    uint8_t  logq;        /* log2(modulus), always 12 */
    uint8_t  logq1;
    uint8_t  logq2;
    uint16_t h1;          /* Hamming weight per col for SamplePsi */
    uint16_t h2;          /* Hamming weight per col for SamplePhi */
    uint8_t  eta1;        /* noise parameter for E */
    uint8_t  eta2;        /* noise parameter for E1/E2 */
    uint8_t  mu;          /* message bits per BW block (64 or 96) */
    uint8_t  muConut;     /* number of BW blocks */
    uint8_t  tau;         /* modulus parameter (3 or 4) */
    uint16_t mnin;
    uint16_t mnout;
    uint16_t c1Size;
    uint16_t c2Size;
    uint16_t ctxSize;
    uint16_t pkSize;
    uint16_t pkeSkSize;
    uint16_t kemSkSize;
} ScloudPlusPara;

/* --------------------------------------------------------------------------
 * Hardware block-level parameters
 * -------------------------------------------------------------------------- */
#define SCLOUD_BLOCK_SIZE   8       /* B = 8 for matrix multiply block */
#define SCLOUD_Q_WIDTH      12      /* Q_WIDTH = 12 bits per coefficient */
#define SCLOUD_MOD_Q        0xFFF   /* modulus = 2^12 - 1 */
#define SCLOUD_BW_COMPLEX   16      /* Barnes-Wall complex coordinates */
#define SCLOUD_BW_REAL      (SCLOUD_BW_COMPLEX * 2)  /* 32 real dims */

/* Packed bus widths matching RTL */
#define SCLOUD_A_BLOCK_BITS  (SCLOUD_BLOCK_SIZE * SCLOUD_BLOCK_SIZE * SCLOUD_Q_WIDTH)  /* 768 */
#define SCLOUD_S_BLOCK_BITS  (SCLOUD_BLOCK_SIZE * SCLOUD_BLOCK_SIZE * 2)               /* 128 */
#define SCLOUD_C_BLOCK_BITS  SCLOUD_A_BLOCK_BITS
#define SCLOUD_MAX_Q_BITS    (SCLOUD_BW_REAL * SCLOUD_Q_WIDTH)                         /* 384 */
#define SCLOUD_MAX_MSG_BITS  ((SCLOUD_BW_COMPLEX * (2*4)) - ((SCLOUD_BW_COMPLEX * 4)/2)) /* 96 for tau=4 */

/* --------------------------------------------------------------------------
 * Initialization / Teardown
 * -------------------------------------------------------------------------- */

/* Initialize the hardware accelerator subsystem.
 * backend: "sw" for pure-C functional model, "verilator" for Verilator.
 * Returns 0 on success, non-zero on failure. */
int hal_init(const char *backend);

/* Shut down and release hardware resources. */
void hal_deinit(void);

/* --------------------------------------------------------------------------
 * Block-level Matrix Multiply (matching RTL scloudplus_matmul_serial)
 * -------------------------------------------------------------------------- */

/* Multiply one BxB block: C = A * S  (mod 2^q)
 *
 * a_block: B*B Q-domain values, flat-packed, B rows * B cols.
 *          Element (row,col) at bit offset (row*B + col)*Q_WIDTH.
 * s_block: B*B ternary values, flat-packed, B rows * B cols.
 *          Element (row,col) at bit offset (row*B + col)*2.
 *          Encoding: 00=0, 01=+1, 10=-1, 11=reserved(-1 in signed2 mode)
 * c_block: output B*B Q-domain results, same packing as a_block.
 * b_active: active block size (<= B, typically 8)
 * q_active: active modulus bit width (<= Q_WIDTH, typically 12)
 * coeff_mode: 0=ternary, 1=binary, 2=signed2
 */
void hal_bmm_block(const uint16_t *a_block, const uint8_t *s_block,
                   uint16_t *c_block,
                   int b_active, int q_active, int coeff_mode);

/* Run the full block-scheduled matrix multiply:
 *   C[m_rows × p_cols] = A[m_rows × n_inner] * S[n_inner × p_cols]
 *
 * A is stored row-major as uint16_t[m_rows * n_inner].
 * S is stored row-major as int16_t[n_inner * p_cols] with values in {-1,0,1}.
 * C is stored row-major as uint16_t[m_rows * p_cols].
 *
 * The operation is broken into BxB blocks using the RTL scheduling pattern.
 */
int hal_matmul_serial(const uint16_t *A, const int16_t *S,
                      uint16_t *C,
                      int m_rows, int n_inner, int p_cols,
                      int b_active, int q_active, int coeff_mode);

/* --------------------------------------------------------------------------
 * Matrix-level Operations (KEM protocol wrappers)
 * -------------------------------------------------------------------------- */

/* KeyGen: B = A * S + E
 *   A is generated from seedA via AES-128-ECB.
 *   S: n × nbar ternary matrix (values in {-1, 0, 1}).
 *   E: m × nbar noise matrix (Q-domain values).
 *   B: output m × nbar matrix (Q-domain).
 */
int hal_matmul_as_e(const uint8_t *seedA, const int16_t *S,
                    const uint16_t *E, const ScloudPlusPara *para,
                    uint16_t *B);

/* Encaps C1: C = S' * A + E  (transposed schedule)
 *   S': mbar × m ternary matrix.
 *   E:  mbar × n noise matrix.
 *   C:  output mbar × n matrix (Q-domain).
 */
int hal_matmul_sa_e(const uint8_t *seedA, const int16_t *S,
                    uint16_t *E, const ScloudPlusPara *para,
                    uint16_t *C);

/* Encaps C2: out = S * B + E
 *   S: mbar × m ternary matrix.
 *   B: m × nbar Q-domain matrix.
 *   E: mbar × nbar noise matrix.
 *   out: mbar × nbar Q-domain result.
 */
void hal_matmul_sb_e(const int16_t *S, const uint16_t *B,
                     const uint16_t *E, const ScloudPlusPara *para,
                     uint16_t *out);

/* Decaps: out = C1 * S
 *   C1: mbar × n Q-domain matrix.
 *   S:  n × nbar ternary matrix.
 *   out: mbar × nbar Q-domain result.
 */
void hal_matmul_cs(const uint16_t *C1, const int16_t *S,
                   const ScloudPlusPara *para, uint16_t *out);

/* --------------------------------------------------------------------------
 * Message Encode / Decode (Barnes-Wall lattice)
 * -------------------------------------------------------------------------- */

/* Encode message bytes to Q-domain matrix.
 * msg: muConut * (mu/8) bytes of message data.
 * matrixM: output flat array of muConut * 32 uint16_t Q-domain values.
 */
void hal_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                   uint16_t *matrixM);

/* Decode Q-domain matrix back to message bytes.
 * matrixM: input flat array of muConut * 32 uint16_t Q-domain values.
 * msg: output muConut * (mu/8) bytes of recovered message.
 * Returns 0 on success.
 */
int hal_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                  uint8_t *msg);

/* Single-block encode/decode (matching RTL scloud_msgfunc_param) */
void hal_msgencode_block(const uint8_t *msg_bytes, int tau,
                         uint16_t *enc_q_flat);
void hal_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                         uint16_t *rounded_q_flat, uint8_t *msg_bytes);

#ifdef __cplusplus
}
#endif

#endif /* SCLOUDPLUS_HAL_H */
