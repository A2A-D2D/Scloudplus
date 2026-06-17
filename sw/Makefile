# SCLOUD+ Software-Hardware Co-Design - Build System
#
# Targets:
#   make              - Build SW functional model and run tests
#   make test         - Build and run tests
#   make clean        - Remove build artifacts
#   make verilator    - Build with Verilator (requires Verilator 5.x installed)
#
# Backends:
#   SW (default)      - Pure C functional model, always available
#   Verilator          - Cycle-accurate Verilog simulation (requires Verilator)

CC       = gcc
CXX      = g++
AR       = ar

CFLAGS   = -Wall -Wextra -O2 -std=c11
CXXFLAGS = -Wall -Wextra -O2 -std=c++17
LDFLAGS  =

# Source directories
HAL_DIR  = hal
SRC_DIR  = src
TEST_DIR = test
INC_DIR  = include

# SW backend sources (C)
HAL_C_SRCS = $(HAL_DIR)/hal_common.c \
             $(HAL_DIR)/hal_matmul.c \
             $(HAL_DIR)/hal_msgfunc.c \
             $(HAL_DIR)/hal_sw_matmul.c \
             $(HAL_DIR)/hal_sw_msgfunc.c

# KEM protocol sources (C)
KEM_C_SRCS = $(SRC_DIR)/scloudplus_util_sw.c \
             $(SRC_DIR)/scloudplus_kem_keygen.c \
             $(SRC_DIR)/scloudplus_kem_encaps.c \
             $(SRC_DIR)/scloudplus_kem_decaps.c

# Test source
TEST_C_SRCS = $(TEST_DIR)/test_hal.c

# All C sources
ALL_C_SRCS = $(HAL_C_SRCS) $(KEM_C_SRCS)
ALL_C_OBJS = $(ALL_C_SRCS:.c=.o)

# Build directories
BUILD_DIR = build
LIB_DIR   = $(BUILD_DIR)/lib
OBJ_DIR   = $(BUILD_DIR)/obj

# Output
LIBHAL    = $(LIB_DIR)/libscloudplus_hal.a
TEST_BIN  = $(BUILD_DIR)/test_hal.exe

# Include paths
INCLUDES  = -I$(INC_DIR) -I$(SRC_DIR) -I$(HAL_DIR) -I.

# =========================================================================
# Default target
# =========================================================================

.PHONY: all
all: $(LIBHAL) $(TEST_BIN)
	@echo "=== Build complete ==="
	@echo "Running tests..."
	@$(TEST_BIN)

# =========================================================================
# Library: libscloudplus_hal.a (all HAL + KEM SW sources)
# =========================================================================

$(LIBHAL): $(ALL_C_OBJS)
	@mkdir -p $(LIB_DIR)
	$(AR) rcs $@ $^

$(OBJ_DIR)/%.o: $(HAL_DIR)/%.c
	@mkdir -p $(OBJ_DIR)/hal
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(OBJ_DIR)/src
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# =========================================================================
# Test binary
# =========================================================================

$(OBJ_DIR)/%.o: $(TEST_DIR)/%.c
	@mkdir -p $(OBJ_DIR)/test
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(TEST_BIN): $(ALL_C_OBJS) $(OBJ_DIR)/test_hal.o
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@ $(LDFLAGS)

# =========================================================================
# Test target
# =========================================================================

.PHONY: test
test: $(TEST_BIN)
	@echo "=== Running SCLOUD+ HAL Tests ==="
	@$(TEST_BIN)
	@echo "=== Tests complete ==="

# =========================================================================
# Verilator target (requires Verilator 5.x)
# =========================================================================

.PHONY: verilator
verilator:
	@echo "=== Building Verilator models ==="
	@echo "This requires Verilator 5.x to be installed."
	@echo "MatMul RTL:"
	cd .. && verilator --cc --exe --build -j \
	    -Wno-fatal -Wno-WIDTH -Wno-LITENDIAN \
	    --top-module scloudplus_matmul_serial \
	    -Irtl/scloudplus \
	    rtl/scloudplus/scloudplus_matmul_serial.v \
	    rtl/scloudplus/scloudplus_bmm_block.v \
	    rtl/scloudplus/scloudplus_bmm_pe.v \
	    rtl/scloudplus/scloudplus_block_add.v \
	    sw/hal/verilator_matmul.cpp \
	    -o ../sw/build/verilator_matmul \
	    -CFLAGS "-I../sw/include" || \
	    echo "Verilator build failed (may need Verilator installed)"
	@echo "MsgFunc RTL:"
	cd .. && verilator --cc --exe --build -j \
	    -Wno-fatal -Wno-WIDTH \
	    --top-module scloud_msgfunc_cfg_reg \
	    -Irtl/msgfunc/param -Irtl/msgfunc/bdd \
	    rtl/msgfunc/param/scloud_msgfunc_cfg_reg.v \
	    rtl/msgfunc/param/scloud_msgfunc_param.v \
	    rtl/msgfunc/bdd/scloud_bdd_recursive.v \
	    sw/hal/verilator_msgfunc.cpp \
	    -o ../sw/build/verilator_msgfunc \
	    -CFLAGS "-I../sw/include" || \
	    echo "Verilator build failed (may need Verilator installed)"

# =========================================================================
# Clean
# =========================================================================

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
	rm -f $(HAL_DIR)/*.o $(SRC_DIR)/*.o $(TEST_DIR)/*.o

# =========================================================================
# Object file rules (generic)
# =========================================================================

# Map source files to obj directory
$(OBJ_DIR)/hal/%.o: $(HAL_DIR)/%.c
	@mkdir -p $(OBJ_DIR)/hal
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(OBJ_DIR)/src/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(OBJ_DIR)/src
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(OBJ_DIR)/test/%.o: $(TEST_DIR)/%.c
	@mkdir -p $(OBJ_DIR)/test
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@
