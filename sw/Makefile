# Matrix-multiplication-only software model build.

CC       = gcc
AR       = ar
CFLAGS   = -Wall -Wextra -O2 -std=c11

HAL_DIR  = hal
INC_DIR  = include
BUILD_DIR = build
OBJ_DIR   = $(BUILD_DIR)/obj
LIB_DIR   = $(BUILD_DIR)/lib

SRCS = $(HAL_DIR)/hal_matmul.c $(HAL_DIR)/hal_sw_matmul.c
OBJS = $(OBJ_DIR)/hal_matmul.o $(OBJ_DIR)/hal_sw_matmul.o
LIB  = $(LIB_DIR)/libscloudplus_matmul.a

INCLUDES = -I$(INC_DIR) -I$(HAL_DIR)

.PHONY: all clean verilator

all: $(LIB)

$(LIB): $(OBJS)
	@mkdir -p $(LIB_DIR)
	$(AR) rcs $@ $^

$(OBJ_DIR)/%.o: $(HAL_DIR)/%.c
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

verilator:
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
	  -CFLAGS "-I../sw/include"

clean:
	rm -rf $(BUILD_DIR)
