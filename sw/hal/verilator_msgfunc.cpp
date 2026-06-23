/*
 * verilator_msgfunc.cpp — Verilator C++ wrapper for SCLOUD+ MsgFunc RCE accelerator.
 *
 * Wraps scloud_msgfunc_rce_accel with a DPRAM memory model and provides
 * C-callable functions for message encode/decode.
 *
 * DPRAM timing: reads are registered (non-blocking assignment on posedge in TB),
 * so dpram_rdata is valid one cycle after dpram_en is asserted.
 */

#ifdef USE_VERILATOR
#include "Vscloud_msgfunc_rce_accel.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" {
#include "../include/scloudplus_hal.h"
}

/* =========================================================================
 * DPRAM Memory Model
 * ========================================================================= */

/* 1024 x 256-bit words. Each word is 4 uint64_t elements. */
struct DPRamWord {
    uint64_t qw[4];
};

/* =========================================================================
 * VerilatorMsgFunc — RCE accelerator driver
 * ========================================================================= */

class VerilatorMsgFunc {
private:
    Vscloud_msgfunc_rce_accel *top;
    DPRamWord dpram_mem[1024];
    uint64_t tick_count;

    /* Registered read: dpram_rdata is set one cycle after dpram_en */
    DPRamWord pending_rdata;
    bool rdata_valid;

    /* Address map (256-bit word addresses) */
    static const uint32_t MSG_IN_BASE   = 0;
    static const uint32_t MSG_OUT_BASE  = 16;
    static const uint32_t Q_IN_BASE     = 64;
    static const uint32_t Q_AUX_BASE    = 128;
    static const uint32_t Q_OUT_BASE    = 192;
    static const uint32_t Q_ROUND_BASE  = 256;

    static const uint32_t DPRAM_MASK = 1023;

public:
    VerilatorMsgFunc() : top(nullptr), tick_count(0), rdata_valid(false) {
        memset(dpram_mem, 0, sizeof(dpram_mem));
        memset(&pending_rdata, 0, sizeof(pending_rdata));
    }

    int init() {
        top = new Vscloud_msgfunc_rce_accel;
        top->clk = 0;
        top->rst_n = 0;
        top->eval();
        top->clk = 1;
        top->eval();
        top->rst_n = 1;
        top->eval();
        tick_count = 0;
        rdata_valid = false;

        /* Tie off unused inputs */
        top->start = 0;
        top->op = 0;
        top->tau_sel = 0;
        top->block_count = 1;
        top->dec_write_q = 0;
        top->msg_in_base = 0;
        top->msg_out_base = 0;
        top->q_in_base = 0;
        top->q_aux_base = 0;
        top->q_out_base = 0;

        return 0;
    }

    ~VerilatorMsgFunc() { delete top; }

    void tick() {
        /* Phase 1: negedge */
        top->clk = 0;

        /* Provide previously-scheduled read data to DUT */
        if (rdata_valid) {
            for (int i = 0; i < 4; i++)
                ((uint64_t*)&top->dpram_rdata)[i] = pending_rdata.qw[i];
            rdata_valid = false;
        } else {
            for (int i = 0; i < 4; i++)
                ((uint64_t*)&top->dpram_rdata)[i] = 0;
        }

        top->eval();

        /* Phase 2: posedge — DPRAM access */
        top->clk = 1;

        if (top->dpram_en) {
            uint32_t addr = top->dpram_addr & DPRAM_MASK;

            /* Schedule read for NEXT cycle (registered read) */
            pending_rdata = dpram_mem[addr];
            rdata_valid = true;

            /* Perform write (byte-enable masked) */
            if (top->dpram_wr_en) {
                for (int b = 0; b < 32; b++) {
                    if ((top->dpram_be >> b) & 1) {
                        ((uint8_t*)&dpram_mem[addr])[b] =
                            ((uint8_t*)&top->dpram_wdata)[b];
                    }
                }
            }
        }

        top->eval();
        tick_count++;
    }

    /* Wait for done signal, ticking each cycle */
    void wait_for_done(int max_cycles = 500000) {
        int cnt = 0;
        while (!top->done && cnt < max_cycles) {
            tick();
            cnt++;
        }
        if (top->done) {
            tick();  /* one more to return to ST_IDLE */
        }
    }

    /* Run a single accelerator operation */
    void run_accel(int op, int tau_sel, int block_count, int dec_write_q,
                   uint32_t msg_in, uint32_t msg_out,
                   uint32_t q_in, uint32_t q_aux, uint32_t q_out) {
        rdata_valid = false;

        top->op = op;
        top->tau_sel = tau_sel;
        top->block_count = block_count;
        top->dec_write_q = dec_write_q;
        top->msg_in_base = msg_in;
        top->msg_out_base = msg_out;
        top->q_in_base = q_in;
        top->q_aux_base = q_aux;
        top->q_out_base = q_out;
        top->start = 0;

        /* Wait for start_ready (in ST_IDLE) */
        int cnt = 0;
        while (!top->start_ready && cnt < 100) { tick(); cnt++; }

        /* Pulse start */
        top->start = 1; tick();
        top->start = 0;

        /* Wait for completion */
        wait_for_done();
    }

    /* ---- DPRAM read/write helpers ---- */

    void write_msg_to_dpram(uint32_t base, int block_idx, const uint8_t *msg, int msg_bytes) {
        uint32_t addr = base + block_idx;
        memset(&dpram_mem[addr], 0, sizeof(DPRamWord));
        memcpy(&dpram_mem[addr], msg, msg_bytes);
    }

    void read_msg_from_dpram(uint32_t base, int block_idx, uint8_t *msg, int msg_bytes) {
        uint32_t addr = base + block_idx;
        memcpy(msg, &dpram_mem[addr], msg_bytes);
    }

    void write_q_to_dpram(uint32_t base, int block_idx, const uint16_t *q_vals) {
        /* Q block: 32 uint16 values packed into 2 DPRAM words (16 lanes each) */
        uint32_t addr0 = base + block_idx * 2;
        uint32_t addr1 = addr0 + 1;
        memset(&dpram_mem[addr0], 0, sizeof(DPRamWord));
        memset(&dpram_mem[addr1], 0, sizeof(DPRamWord));

        for (int i = 0; i < 16; i++)
            ((uint16_t*)&dpram_mem[addr0])[i] = q_vals[i] & 0xFFF;
        for (int i = 0; i < 16; i++)
            ((uint16_t*)&dpram_mem[addr1])[i] = q_vals[16 + i] & 0xFFF;
    }

    void read_q_from_dpram(uint32_t base, int block_idx, uint16_t *q_vals) {
        uint32_t addr0 = base + block_idx * 2;
        uint32_t addr1 = addr0 + 1;
        for (int i = 0; i < 16; i++)
            q_vals[i] = ((uint16_t*)&dpram_mem[addr0])[i] & 0xFFF;
        for (int i = 0; i < 16; i++)
            q_vals[16 + i] = ((uint16_t*)&dpram_mem[addr1])[i] & 0xFFF;
    }

    /* ---- High-level operations ---- */

    /* Single-block encode: msg → Q codeword */
    void msgencode_block(const uint8_t *msg_bytes, int tau, uint16_t *enc_q_flat) {
        int msg_len = (tau == 3) ? 8 : 12;
        int tau_flag = (tau == 4) ? 1 : 0;

        /* Clear DPRAM and write message */
        memset(dpram_mem, 0, sizeof(dpram_mem));
        write_msg_to_dpram(MSG_IN_BASE, 0, msg_bytes, msg_len);

        /* Run OP_MSGENC: encode only, no input Q */
        run_accel(0, tau_flag, 1, 0,
                  MSG_IN_BASE, 0, 0, 0, Q_OUT_BASE);

        /* Read result */
        read_q_from_dpram(Q_OUT_BASE, 0, enc_q_flat);
    }

    /* Single-block decode: noisy Q → rounded Q + message */
    void msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                          uint16_t *rounded_q_flat, uint8_t *msg_bytes) {
        int msg_len = (tau == 3) ? 8 : 12;
        int tau_flag = (tau == 4) ? 1 : 0;

        /* Clear DPRAM and write noisy Q */
        memset(dpram_mem, 0, sizeof(dpram_mem));
        write_q_to_dpram(Q_IN_BASE, 0, noisy_q_flat);

        /* Run OP_MSGDEC with dec_write_q=1 to also get rounded Q */
        run_accel(1, tau_flag, 1, 1,
                  0, MSG_OUT_BASE, Q_IN_BASE, 0, Q_ROUND_BASE);

        /* Read results */
        read_msg_from_dpram(MSG_OUT_BASE, 0, msg_bytes, msg_len);
        read_q_from_dpram(Q_ROUND_BASE, 0, rounded_q_flat);
    }

    /* Multi-block encode */
    void msgencode(const uint8_t *msg, const ScloudPlusPara *para, uint16_t *matrixM) {
        int mu_bytes = para->mu / 8;
        int mu_conut = para->muConut;
        int tau = para->tau;
        int tau_flag = (tau == 4) ? 1 : 0;
        int block_size = 32; /* SCLOUD_BW_REAL */

        memset(dpram_mem, 0, sizeof(dpram_mem));

        /* Write all message blocks */
        for (int i = 0; i < mu_conut; i++)
            write_msg_to_dpram(MSG_IN_BASE, i, msg + i * mu_bytes, mu_bytes);

        /* Run multi-block encode */
        run_accel(0, tau_flag, mu_conut, 0,
                  MSG_IN_BASE, 0, 0, 0, Q_OUT_BASE);

        /* Read all Q blocks */
        for (int i = 0; i < mu_conut; i++)
            read_q_from_dpram(Q_OUT_BASE, i, matrixM + i * block_size);
    }

    /* Multi-block decode */
    int msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para, uint8_t *msg) {
        int mu_bytes = para->mu / 8;
        int mu_conut = para->muConut;
        int tau = para->tau;
        int tau_flag = (tau == 4) ? 1 : 0;
        int block_size = 32;

        memset(dpram_mem, 0, sizeof(dpram_mem));

        /* Write all noisy Q blocks */
        for (int i = 0; i < mu_conut; i++)
            write_q_to_dpram(Q_IN_BASE, i, matrixM + i * block_size);

        /* Run multi-block decode (no rounded Q output for multi-block) */
        run_accel(1, tau_flag, mu_conut, 0,
                  0, MSG_OUT_BASE, Q_IN_BASE, 0, 0);

        /* Read all decoded messages */
        for (int i = 0; i < mu_conut; i++)
            read_msg_from_dpram(MSG_OUT_BASE, i, msg + i * mu_bytes, mu_bytes);

        return 0;
    }
};

/* =========================================================================
 * C-callable wrappers
 * ========================================================================= */

extern "C" {

static VerilatorMsgFunc *vlt_msgfunc = nullptr;

/* Override weak default to signal Verilator availability */
int _hal_vlt_msgfunc_available = 1;

int hal_vlt_msgfunc_init(void) {
    if (!vlt_msgfunc) {
        vlt_msgfunc = new VerilatorMsgFunc();
        return vlt_msgfunc->init();
    }
    return 0;
}

void hal_vlt_msgfunc_deinit(void) {
    delete vlt_msgfunc;
    vlt_msgfunc = nullptr;
}

void hal_vlt_msgencode_block(const uint8_t *msg_bytes, int tau,
                              uint16_t *enc_q_flat) {
    if (vlt_msgfunc)
        vlt_msgfunc->msgencode_block(msg_bytes, tau, enc_q_flat);
}

void hal_vlt_msgdecode_block(const uint16_t *noisy_q_flat, int tau,
                              uint16_t *rounded_q_flat, uint8_t *msg_bytes) {
    if (vlt_msgfunc)
        vlt_msgfunc->msgdecode_block(noisy_q_flat, tau, rounded_q_flat, msg_bytes);
}

void hal_vlt_msgencode(const uint8_t *msg, const ScloudPlusPara *para,
                        uint16_t *matrixM) {
    if (vlt_msgfunc)
        vlt_msgfunc->msgencode(msg, para, matrixM);
}

int hal_vlt_msgdecode(const uint16_t *matrixM, const ScloudPlusPara *para,
                       uint8_t *msg) {
    if (vlt_msgfunc)
        return vlt_msgfunc->msgdecode(matrixM, para, msg);
    return -1;
}

} /* extern "C" */

#endif /* USE_VERILATOR */
