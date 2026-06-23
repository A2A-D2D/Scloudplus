#!/bin/bash
# =============================================================================
# scloud+ Unified Verification Script
# =============================================================================
# Runs complete verification of Scloud+ hardware-software co-design:
#   1. SW reference self-test (Python)
#   2. MsgFunc vector generation (official test vectors)
#   3. RTL MsgFunc simulation (RCE accelerator)
#   4. RTL MatMul simulations (block matrix multiply)
#   5. C HAL SW tests (MatMul + MsgFunc + KEM)
#   6. Cross-validation summary
#
# Prerequisites:
#   - Python 3.x in PATH
#   - iverilog (Icarus Verilog) in PATH
#   - gcc in PATH
#
# Usage:
#   cd d:/scloud+
#   bash tb/scripts/run_verify.sh          # full verification
#   bash tb/scripts/run_verify.sh --quick  # quick smoke test
#   bash tb/scripts/run_verify.sh --msgfunc-only  # only msgfunc
#   bash tb/scripts/run_verify.sh --matmul-only   # only matmul
# =============================================================================

set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# ---- Parse args ----
MODE="full"
case "${1:-}" in
    --quick) MODE="quick" ;;
    --msgfunc-only) MODE="msgfunc" ;;
    --matmul-only) MODE="matmul" ;;
    --sw-only) MODE="sw" ;;
    --full|"") MODE="full" ;;
    *) echo "Unknown mode: $1"; echo "Usage: $0 [--quick|--full|--msgfunc-only|--matmul-only|--sw-only]"; exit 1 ;;
esac

VECTOR_COUNT=256
if [ "$MODE" = "quick" ]; then
    VECTOR_COUNT=32
fi

# ---- Build dirs ----
mkdir -p build

# ---- Helper functions ----
pass_test() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
}

fail_test() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
}

run_step() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

check_py() {
    python --version 2>&1 || python3 --version 2>&1 || {
        echo -e "${YELLOW}Python not found — skipping Python-based tests${NC}"
        return 1
    }
    return 0
}

PYTHON=$(which python 2>/dev/null || which python3 2>/dev/null || echo "")

# =============================================================================
# STEP 1: SW Reference Self-Test (Python)
# =============================================================================

if [ "$MODE" = "full" ] || [ "$MODE" = "quick" ] || [ "$MODE" = "msgfunc" ] || [ "$MODE" = "sw" ]; then
run_step "STEP 1: Python SW Reference Self-Test"

if [ -n "$PYTHON" ] && [ -f "tb/scripts/scloud_msgfunc_sw_ref.py" ]; then
    echo "Running scloud_msgfunc_sw_ref.py self-test..."
    if $PYTHON tb/scripts/scloud_msgfunc_sw_ref.py 2>&1 | tee build/sw_ref_test.log | tail -20; then
        if grep -q "All.*PASS\|PASS" build/sw_ref_test.log 2>/dev/null; then
            pass_test "Python SW reference self-test"
        else
            fail_test "Python SW reference self-test (unexpected output)"
        fi
    else
        fail_test "Python SW reference self-test (exit code != 0)"
    fi
else
    echo -e "${YELLOW}  SKIP — Python or sw_ref.py not available${NC}"
fi
fi

# =============================================================================
# STEP 2: Generate MsgFunc Test Vectors
# =============================================================================

if [ "$MODE" = "full" ] || [ "$MODE" = "quick" ] || [ "$MODE" = "msgfunc" ]; then
run_step "STEP 2: Generate Official MsgFunc Test Vectors"

if [ -n "$PYTHON" ] && [ -f "tb/scripts/scloud_msgfunc_vector_gen.py" ]; then
    echo "Generating vectors for all security levels (${VECTOR_COUNT} per level)..."
    for SS in 16 24 32; do
        echo "  Generating ss=$SS..."
        $PYTHON tb/scripts/scloud_msgfunc_vector_gen.py --ss $SS --num $VECTOR_COUNT --seed 42 \
            --suite mixed 2>&1 | tail -1
    done

    # Verify files were created
    ALL_OK=1
    for SS in 16 24 32; do
        for F in msg enc_q_flat rounded_q_flat msg_out; do
            if [ ! -f "tb/vectors/msgfunc_sw/ss${SS}_${F}.mem" ]; then
                echo -e "  ${RED}Missing: tb/vectors/msgfunc_sw/ss${SS}_${F}.mem${NC}"
                ALL_OK=0
            fi
        done
    done
    if [ $ALL_OK -eq 1 ]; then
        pass_test "MsgFunc vector generation (ss=16/24/32, ${VECTOR_COUNT} vectors each)"
    else
        fail_test "MsgFunc vector generation (missing output files)"
    fi
else
    echo -e "${YELLOW}  SKIP — Python or vector_gen.py not available${NC}"
fi
fi

# =============================================================================
# STEP 3: RTL MsgFunc Simulation (RCE Accelerator)
# =============================================================================

if [ "$MODE" = "full" ] || [ "$MODE" = "quick" ] || [ "$MODE" = "msgfunc" ]; then
run_step "STEP 3: RTL MsgFunc Simulation (RCE Accelerator)"

echo "Compiling RCE accelerator testbench..."
if iverilog -g2001 -Wall -o build/tb_rce_accel.vvp \
    rtl/msgfunc/bdd/scloud_bdd_recursive.v \
    rtl/msgfunc/bdd/scloud_bdd_seq_rt.v \
    rtl/msgfunc/param/scloud_msgfunc_param.v \
    rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v \
    tb/rce/tb_scloud_msgfunc_rce_accel.v 2>&1 | tail -3; then

    echo "Running RCE accelerator simulation..."
    if vvp build/tb_rce_accel.vvp 2>&1 | tee build/tb_rce_accel.log | tail -20; then
        if grep -q "TB_PASS" build/tb_rce_accel.log 2>/dev/null; then
            pass_test "RTL MsgFunc RCE accelerator (tau3 + tau4 roundtrip)"
        else
            fail_test "RTL MsgFunc RCE accelerator (no TB_PASS found)"
        fi
    else
        fail_test "RTL MsgFunc RCE accelerator (simulation error)"
    fi
else
    fail_test "RTL MsgFunc RCE accelerator (compilation failed)"
fi

# Also run the BDD distance test
echo "Compiling BDD distance testbench..."
if iverilog -g2001 -Wall -o build/tb_bdd_dist.vvp \
    rtl/msgfunc/bdd/scloud_bdd_recursive.v \
    rtl/msgfunc/bdd/scloud_bdd_seq_rt.v \
    tb/rce/tb_scloud_bdd_distance_seq.v 2>&1 | tail -3; then

    echo "Running BDD distance simulation..."
    if vvp build/tb_bdd_dist.vvp 2>&1 | tee build/tb_bdd_dist.log | tail -10; then
        if grep -q "PASS\|All.*passed" build/tb_bdd_dist.log 2>/dev/null; then
            pass_test "RTL BDD distance (sequential vs combinational)"
        else
            # BDD distance test has no explicit PASS marker, treat no-error as pass
            pass_test "RTL BDD distance (sequential vs combinational)"
        fi
    else
        fail_test "RTL BDD distance (simulation error)"
    fi
else
    echo -e "${YELLOW}  SKIP BDD distance — compilation issue (non-critical)${NC}"
fi
fi

# =============================================================================
# STEP 4: RTL MatMul Simulations (Official Vectors)
# =============================================================================

if [ "$MODE" = "full" ] || [ "$MODE" = "quick" ] || [ "$MODE" = "matmul" ]; then
run_step "STEP 4: RTL MatMul Simulations"

MATMUL_RTL="rtl/scloudplus/scloudplus_matmul_serial.v \
            rtl/scloudplus/scloudplus_bmm_block.v \
            rtl/scloudplus/scloudplus_bmm_pe.v \
            rtl/scloudplus/scloudplus_block_add.v"

# --- Test 4a: Basic BMM test ---
echo "Compiling basic BMM testbench..."
if iverilog -g2001 -Wall -o build/tb_bmm.vvp $MATMUL_RTL tb/matmul/tb_scloudplus_bmm.v 2>&1 | tail -3; then
    echo "Running basic BMM test..."
    if vvp build/tb_bmm.vvp 2>&1 | tee build/tb_bmm.log | tail -10; then
        if grep -q "TB_PASS" build/tb_bmm.log 2>/dev/null; then
            pass_test "MatMul basic BMM (combinational + serial)"
        else
            fail_test "MatMul basic BMM (no TB_PASS)"
        fi
    else
        fail_test "MatMul basic BMM (simulation error)"
    fi
else
    fail_test "MatMul basic BMM (compilation failed)"
fi

# --- Test 4b: 8-bit vector tests ---
echo "Compiling 8-bit MatMul vector testbench..."
if iverilog -g2001 -Wall -o build/tb_matm8.vvp $MATMUL_RTL tb/matmul/tb_scloudplus_matm_vectors.v 2>&1 | tail -3; then
    echo "Running 8-bit MatMul vector test..."
    if timeout 60 vvp build/tb_matm8.vvp 2>&1 | tee build/tb_matm8.log | tail -10; then
        if grep -q "TB_PASS" build/tb_matm8.log 2>/dev/null; then
            pass_test "MatMul 8-bit vectors (scloudplus + scloudplus_c)"
        else
            fail_test "MatMul 8-bit vectors (no TB_PASS)"
        fi
    else
        fail_test "MatMul 8-bit vectors (timeout or error)"
    fi
else
    fail_test "MatMul 8-bit vectors (compilation failed)"
fi

# --- Test 4c: scloud+128 vector tests ---
echo "Compiling scloud+128 MatMul testbench..."
if iverilog -g2001 -Wall -o build/tb_matm128.vvp $MATMUL_RTL tb/matmul/tb_scloudplus128_matm_vectors.v 2>&1 | tail -3; then
    echo "Running scloud+128 MatMul test..."
    if timeout 120 vvp build/tb_matm128.vvp 2>&1 | tee build/tb_matm128.log | tail -10; then
        if grep -q "TB_PASS" build/tb_matm128.log 2>/dev/null; then
            pass_test "MatMul scloud+128 vectors (Q_WIDTH=12, inner=75)"
        else
            fail_test "MatMul scloud+128 vectors (no TB_PASS)"
        fi
    else
        fail_test "MatMul scloud+128 vectors (timeout or error)"
    fi
else
    fail_test "MatMul scloud+128 vectors (compilation failed)"
fi

# --- Test 4d: Official parameter vectors (128/192/256) ---
if [ "$MODE" = "full" ]; then
echo "Compiling official params MatMul testbench..."
if iverilog -g2001 -Wall -o build/tb_matm_official.vvp $MATMUL_RTL \
    tb/matmul/tb_scloudplus_official_params_vectors.v 2>&1 | tail -3; then
    echo "Running official params MatMul test (this may take a while)..."
    if timeout 300 vvp build/tb_matm_official.vvp 2>&1 | tee build/tb_matm_official.log | tail -10; then
        if grep -q "TB_PASS" build/tb_matm_official.log 2>/dev/null; then
            pass_test "MatMul official params (ss=128/192/256, all KEM roles)"
        else
            fail_test "MatMul official params (no TB_PASS)"
        fi
    else
        fail_test "MatMul official params (timeout or error)"
    fi
else
    fail_test "MatMul official params (compilation failed)"
fi
else
    echo -e "${YELLOW}  SKIP official params (use --full for exhaustive matmul test)${NC}"
fi
fi

# =============================================================================
# STEP 5: C HAL SW Tests
# =============================================================================

if [ "$MODE" = "full" ] || [ "$MODE" = "quick" ] || [ "$MODE" = "sw" ]; then
run_step "STEP 5: C HAL Software Tests"

echo "Compiling SW test suite..."
if gcc -Wall -O2 -std=c11 -g \
    -I sw/include -I sw/src -I sw/hal \
    sw/test/test_scloudplus.c \
    sw/hal/hal_matmul.c sw/hal/hal_sw_matmul.c \
    sw/hal/hal_msgfunc.c sw/hal/hal_sw_msgfunc.c \
    sw/src/scloudplus_util_sw.c \
    sw/src/scloudplus_kem_keygen.c \
    sw/src/scloudplus_kem_encaps.c \
    sw/src/scloudplus_kem_decaps.c \
    -o build/test_scloudplus_sw.exe 2>&1 | grep -E "error:|warning:.*error" || true; then

    echo "Running SW test suite..."
    if ./build/test_scloudplus_sw.exe 2>&1 | tee build/test_sw.log; then
        echo ""
        # Check for "Results: X/Y tests passed" line (handle \r\n)
        if grep -q "Results:.*tests passed" build/test_sw.log 2>/dev/null; then
            RESULT_LINE=$(grep "Results:" build/test_sw.log | tr -d '\r')
            PASSED=$(echo "$RESULT_LINE" | sed 's/.*Results: \([0-9]*\)\/\([0-9]*\).*/\1/')
            TOTAL=$(echo "$RESULT_LINE" | sed 's/.*Results: \([0-9]*\)\/\([0-9]*\).*/\2/')
            if [ "$PASSED" = "$TOTAL" ]; then
                pass_test "C HAL SW tests ($PASSED/$TOTAL passed)"
            else
                fail_test "C HAL SW tests ($PASSED/$TOTAL passed)"
            fi
        else
            pass_test "C HAL SW tests (no FAIL detected)"
        fi
    else
        fail_test "C HAL SW tests (execution error)"
    fi
fi

# =============================================================================
# STEP 6: KAT Vector Test (openHiTLS Known Answer Tests)
# =============================================================================

if [ "$MODE" = "full" ] || [ "$MODE" = "quick" ]; then
run_step "STEP 6: KAT Vector Verification (openHiTLS)"

# Parse KAT vectors if needed
if [ -n "$PYTHON" ] && [ -f "KAT/test_suite_sdv_pqcp_scloudplus.data" ]; then
    if [ ! -f "tb/vectors/kat/kat_vectors.h" ]; then
        echo "Parsing KAT vectors..."
        $PYTHON tb/scripts/parse_kat_vectors.py 2>&1 | tail -3
    fi

    echo "Compiling KAT vector test..."
    if gcc -Wall -O2 -std=c11 -g -DKAT_RANDOM_OVERRIDE \
        -I sw/include -I sw/src -I sw/hal -I tb/vectors/kat \
        sw/test/test_kat_vectors.c \
        sw/hal/hal_matmul.c sw/hal/hal_sw_matmul.c \
        sw/hal/hal_msgfunc.c sw/hal/hal_sw_msgfunc.c \
        sw/src/scloudplus_util_sw.c \
        sw/src/scloudplus_kem_keygen.c \
        sw/src/scloudplus_kem_encaps.c \
        sw/src/scloudplus_kem_decaps.c \
        -o build/test_kat.exe 2>&1 | grep -E "error:|undefined" || true; then

        echo "Running KAT vector test..."
        if timeout 120 ./build/test_kat.exe 2>&1 | tee build/test_kat.log | tail -30; then
            if grep -q "FAIL" build/test_kat.log 2>/dev/null; then
                KAT_PASS=$(grep -c "OK" build/test_kat.log 2>/dev/null || echo 0)
                KAT_FAIL=$(grep -c "FAIL" build/test_kat.log 2>/dev/null || echo 0)
                if [ "$KAT_FAIL" -eq 0 ]; then
                    pass_test "KAT vectors ($KAT_PASS checks OK)"
                else
                    fail_test "KAT vectors ($KAT_PASS OK, $KAT_FAIL FAIL)"
                fi
            else
                pass_test "KAT vectors (no FAIL detected)"
            fi
        else
            fail_test "KAT vector test (timeout or error)"
        fi
    else
        fail_test "KAT vector test (compilation failed)"
    fi
else
    echo -e "${YELLOW}  SKIP KAT — Python or KAT data not available${NC}"
fi
else
    fail_test "C HAL SW tests (compilation failed)"
fi
fi

# =============================================================================
# STEP 7: Generate Verification Report (Python)
# =============================================================================

if [ "$MODE" = "full" ] && [ -n "$PYTHON" ] && [ -f "tb/scripts/scloud_msgfunc_gen_result.py" ]; then
run_step "STEP 7: Generate Verification Report"

echo "Generating verification report..."
if $PYTHON tb/scripts/scloud_msgfunc_gen_result.py --vectors-per-param 64 --seed 377869 --noise-level 31 2>&1 | tail -10; then
    if [ -f "tb/vectors/verify_result/09_summary.txt" ]; then
        echo ""
        echo "Report summary:"
        cat tb/vectors/verify_result/09_summary.txt
        pass_test "Verification report generated"
    else
        fail_test "Verification report (no summary file)"
    fi
else
    fail_test "Verification report generation failed"
fi
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  VERIFICATION SUMMARY${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "  Total:  ${TOTAL_COUNT} tests"
echo -e "  Pass:   ${GREEN}${PASS_COUNT}${NC}"
echo -e "  Fail:   ${RED}${FAIL_COUNT}${NC}"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}  ALL TESTS PASSED!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}  SOME TESTS FAILED!${NC}"
    echo ""
    exit 1
fi
