# Scloud+ Software Makefile
# Builds the HAL library, KEM application, and test harness.
#
# Targets:
#   make            - Build SW-only test executable
#   make verilator  - Build Verilator HW-accelerated test (requires Verilator 5.x)
#   make clean      - Remove all build artifacts

CC       = gcc
CXX      = g++
AR       = ar
CFLAGS   = -Wall -Wextra -O2 -std=c11 -g
CXXFLAGS = -Wall -Wextra -O2 -std=c++11 -g

ROOT     = ..
HAL_DIR  = hal
INC_DIR  = include
SRC_DIR  = src
TEST_DIR = test
BUILD_DIR = build
OBJ_DIR   = $(BUILD_DIR)/obj

INCLUDES = -I$(INC_DIR) -I$(SRC_DIR) -I$(HAL_DIR)

# Source files
HAL_C_SRCS = $(HAL_DIR)/hal_matmul.c $(HAL_DIR)/hal_sw_matmul.c \
             $(HAL_DIR)/hal_msgfunc.c $(HAL_DIR)/hal_sw_msgfunc.c
SRC_C_SRCS = $(SRC_DIR)/scloudplus_kem_keygen.c \
             $(SRC_DIR)/scloudplus_kem_encaps.c \
             $(SRC_DIR)/scloudplus_kem_decaps.c \
             $(SRC_DIR)/scloudplus_util_sw.c
TEST_C_SRCS = $(TEST_DIR)/test_scloudplus.c

ALL_C_SRCS = $(HAL_C_SRCS) $(SRC_C_SRCS) $(TEST_C_SRCS)

# Object files
HAL_OBJS  = $(patsubst $(HAL_DIR)/%.c,$(OBJ_DIR)/hal_%.o,$(HAL_C_SRCS))
SRC_OBJS  = $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(SRC_C_SRCS))
TEST_OBJS = $(patsubst $(TEST_DIR)/%.c,$(OBJ_DIR)/%.o,$(TEST_C_SRCS))

ALL_OBJS = $(HAL_OBJS) $(SRC_OBJS) $(TEST_OBJS)

TEST_BIN = $(BUILD_DIR)/test_scloudplus.exe

# =========================================================================
# Default: SW-only build
# =========================================================================

.PHONY: all clean verilator

all: $(TEST_BIN)

$(TEST_BIN): $(ALL_OBJS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $^ -o $@
	@echo "=== SW-only build complete: $(TEST_BIN) ==="

$(OBJ_DIR)/hal_%.o: $(HAL_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(OBJ_DIR)/%.o: $(TEST_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# =========================================================================
# Verilator HW-accelerated build
# =========================================================================

# All RTL source files needed
RTL_SCLOUDPLUS = rtl/scloudplus/scloudplus_matmul_serial.v \
                 rtl/scloudplus/scloudplus_bmm_block.v \
                 rtl/scloudplus/scloudplus_bmm_pe.v \
                 rtl/scloudplus/scloudplus_block_add.v

RTL_MSGFUNC = rtl/msgfunc/bdd/scloud_bdd_recursive.v \
              rtl/msgfunc/bdd/scloud_bdd_seq_rt.v \
              rtl/msgfunc/param/scloud_msgfunc_param.v \
              rtl/msgfunc/rce/scloud_msgfunc_rce_accel.v

# SW C sources (relative to repo root for Verilator)
VLT_C_SRCS = sw/hal/hal_matmul.c sw/hal/hal_sw_matmul.c \
             sw/hal/hal_msgfunc.c sw/hal/hal_sw_msgfunc.c \
             sw/src/scloudplus_kem_keygen.c sw/src/scloudplus_kem_encaps.c \
             sw/src/scloudplus_kem_decaps.c sw/src/scloudplus_util_sw.c \
             sw/test/test_scloudplus.c

# Verilator CPP files
VLT_CPP = sw/hal/verilator_matmul.cpp sw/hal/verilator_msgfunc.cpp

# Verilator flags
VLT_FLAGS = -Wno-fatal -Wno-WIDTH -Wno-LITENDIAN -Wno-UNOPTFLAT -Wno-COMBDLY
VLT_CFLAGS = -Isw/include -Isw/src -Isw/hal \
             -Irtl/scloudplus -Irtl/msgfunc/bdd -Irtl/msgfunc/param -Irtl/msgfunc/rce \
             -DUSE_VERILATOR

VLT_BUILD_DIR = sw/build/verilator
VLT_TEST_BIN  = ../sw/build/test_scloudplus_vlt

verilator:
	@echo "=== Building Verilator HW-accelerated test ==="
	@echo "This requires Verilator 5.x installed and in PATH."
	@mkdir -p $(BUILD_DIR)/verilator
	cd $(ROOT) && verilator --cc --exe --build -j \
	  $(VLT_FLAGS) \
	  --top-module scloudplus_matmul_serial \
	  -Irtl/scloudplus \
	  -Irtl/msgfunc/bdd \
	  -Irtl/msgfunc/param \
	  -Irtl/msgfunc/rce \
	  $(RTL_SCLOUDPLUS) \
	  $(RTL_MSGFUNC) \
	  $(VLT_CPP) \
	  $(VLT_C_SRCS) \
	  --Mdir $(VLT_BUILD_DIR) \
	  -o $(VLT_TEST_BIN) \
	  -CFLAGS "$(VLT_CFLAGS)"
	@echo "=== Verilator build complete: $(TEST_BIN) ==="

# =========================================================================
# Clean
# =========================================================================

clean:
	rm -rf $(BUILD_DIR)
	@echo "=== Clean complete ==="
