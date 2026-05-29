# Makefile for TinyTapeout GF180 UART CocoTB testbench
# Usage:
#   make              — run with Icarus Verilog (default)
#   make SIM=verilator — run with Verilator
#   make clean        — remove build artefacts

SIM        ?= icarus
TOPLEVEL_LANG ?= verilog

# ── Source files ────────────────────────────────────────────
VERILOG_SOURCES  = $(PWD)/../src/project.v
VERILOG_SOURCES += $(PWD)/tb.v

# ── CocoTB settings ─────────────────────────────────────────
TOPLEVEL  = tb               # must match module name in tb.v
MODULE    = test             # Python test file (test.py)

# Pass CLKS_PER_BIT parameter to Icarus
ifeq ($(SIM), icarus)
    COMPILE_ARGS += -P tb.dut.CLKS_PER_BIT=16
endif

# ── Include CocoTB Makefile ─────────────────────────────────
include $(shell cocotb-config --makefiles)/Makefile.sim
