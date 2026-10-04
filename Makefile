# -----------------------------------------------------------------------------
# axi4-dma-controller-uvm - Verilator flow
#
#   make uvm                 fetch Accellera UVM 2020.3.1 into third_party/
#   make build [NUM_CH=n]    compile RTL + testbench (one binary, all tests);
#                            NUM_CH=2..8 builds a separate model in build_ch<n>/
#   make run TEST=<t> SEED=<n> [VERBOSITY=UVM_MEDIUM] [WAVES=1]
#   make regress [SEEDS=3]   all tests x seeds, merged coverage report
#   make lint                Verilator -Wall lint of the RTL (NUM_CH = 2, 3, 4, 8)
#   make slang               strict IEEE-1800 elaboration of RTL + testbench (slang)
#   make synth               Yosys synthesis of the RTL (synthesizability check)
#   make formal              SymbiYosys unbounded proof (PDR) of the AXI/APB rules + covers
#   make bugs                bug-injection campaign (each bug must be caught)
#   make clean
#
# Tools: Verilator >= 5.036 (tested 5.053), z3 on PATH (constraint solver used
# by Verilator's randomize()), Python 3. slang / yosys for the optional checks.
# -----------------------------------------------------------------------------

SHELL      := /bin/bash
ROOT       := $(abspath .)
UVM_HOME   ?= $(ROOT)/third_party/uvm-core
UVM_TAG    ?= 2020.3.1
NUM_CH     ?= 4
BUILD_DIR  ?= $(ROOT)/build$(if $(filter-out 4,$(NUM_CH)),_ch$(NUM_CH),)
JOBS       ?= $(shell nproc 2>/dev/null || echo 2)

TEST       ?= dma_smoke_test
SEED       ?= 1
VERBOSITY  ?= UVM_LOW
COV        ?= 1
WAVES      ?= 0
SEEDS      ?= 3
PLUSARGS   ?=
# C++ build of the generated model: the UVM class code dominates compile time
# and memory; -O0 in 16 translation units keeps a 2-core / 8 GB machine
# responsive (simulation speed is dominated by UVM, not by the -O level).
OPT        ?= -O0
OUTPUT_GROUPS ?= 16

OBJ_DIR    := $(BUILD_DIR)/obj
BIN        := $(OBJ_DIR)/Vtb_top
RUN_DIR    := $(BUILD_DIR)/runs/$(TEST)_s$(SEED)

RTL_SRCS   := $(shell sed -n 's/^\(rtl\/.*\.sv\)$$/\1/p' sim/filelist.f)
TB_SRCS    := $(shell find tb -name '*.sv' -o -name '*.svh')

VERILATOR  ?= verilator
VFLAGS     := --binary -j $(JOBS) --vpi --assert --timescale 1ns/1ps \
              -Wno-fatal -Wno-lint -Wno-style \
              +define+UVM_HDL_NO_DPI +define+DMA_NUM_CH=$(NUM_CH) \
              +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm_pkg.sv \
              -f sim/filelist.f --top-module tb_top \
              -CFLAGS -I$(UVM_HOME)/src/dpi $(ROOT)/sim/verilator/uvm_dpi_verilator.cc \
              -Mdir $(OBJ_DIR) -o Vtb_top \
              --output-groups $(OUTPUT_GROUPS) -MAKEFLAGS "OPT_FAST=$(OPT) OPT_SLOW=$(OPT)"
ifeq ($(COV),1)
VFLAGS     += --coverage-line --coverage-toggle --coverage-user sim/verilator/coverage.vlt
endif
ifeq ($(WAVES),1)
VFLAGS     += --trace-vcd
endif

.PHONY: all uvm build run regress lint slang synth formal bugs clean help

all: build

help:
	@sed -n '2,17p' Makefile

$(UVM_HOME)/src/uvm_pkg.sv:
	git clone --depth 1 --branch $(UVM_TAG) https://github.com/accellera-official/uvm-core.git $(UVM_HOME)

uvm: $(UVM_HOME)/src/uvm_pkg.sv

$(BIN): $(RTL_SRCS) $(TB_SRCS) sim/filelist.f sim/verilator/uvm_dpi_verilator.cc sim/verilator/coverage.vlt | $(UVM_HOME)/src/uvm_pkg.sv
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VFLAGS) 2>&1 | tee $(BUILD_DIR)/build.log
	@test -x $(BIN)

build: $(BIN)

run: $(BIN)
	@mkdir -p $(RUN_DIR)
	cd $(RUN_DIR) && $(BIN) +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED) \
	    +UVM_VERBOSITY=$(VERBOSITY) +UVM_NO_RELNOTES $(if $(filter 1,$(WAVES)),+WAVES,) \
	    +verilator+coverage+file+coverage.dat $(PLUSARGS) 2>&1 | tee sim.log
	@grep -q "\*\* TEST PASSED \*\*" $(RUN_DIR)/sim.log

regress: $(BIN)
	python3 scripts/run_regression.py --bin $(BIN) --seeds $(SEEDS) --out $(BUILD_DIR)/regress

lint:
	@for n in 2 3 4 8; do \
	  echo "lint NUM_CH=$$n"; \
	  $(VERILATOR) --lint-only -Wall -GNUM_CH=$$n $(RTL_SRCS) --top-module dma_top || exit 1; \
	done

slang: | $(UVM_HOME)/src/uvm_pkg.sv
	slang --top dma_top -Wextra -Werror $(RTL_SRCS)
	slang --top tb_top --timescale 1ns/1ps \
	    +define+UVM_HDL_NO_DPI +define+DMA_NUM_CH=$(NUM_CH) +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm_pkg.sv -f sim/filelist.f

synth:
	@mkdir -p $(BUILD_DIR)
	yosys -m slang -q -l $(BUILD_DIR)/synth.log -p "read_slang $(RTL_SRCS) --top dma_top; \
	    synth -top dma_top; check -assert; tee -o $(BUILD_DIR)/synth_stat.txt stat"
	@grep -A3 "cells" $(BUILD_DIR)/synth_stat.txt | head -4

formal:
	cd formal && sby -f dma.sby prove cover

bugs: $(BIN)
	python3 scripts/bug_hunt.py --seeds 2 --docs

clean:
	rm -rf $(BUILD_DIR)
