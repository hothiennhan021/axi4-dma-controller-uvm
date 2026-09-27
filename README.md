# AXI4 DMA Controller - UVM Verification Environment

[![ci](https://github.com/hothiennhan021/axi4-dma-controller-uvm/actions/workflows/ci.yml/badge.svg)](https://github.com/hothiennhan021/axi4-dma-controller-uvm/actions/workflows/ci.yml)

A 4-channel memory-to-memory DMA controller (APB3 configuration port, AXI4
burst master) and a complete UVM 1800.2 verification environment for it:
register model, reactive AXI4 slave with memory model, a cycle-exact reference
model, SVA, functional/code coverage, a formal bounded proof and a
bug-injection campaign that shows the testbench actually catches bugs.

Everything runs on open-source tools - **Verilator 5 + Accellera UVM
2020.3.1** for simulation, slang for strict SystemVerilog elaboration, Yosys
for synthesis and SymbiYosys for formal - so it can be reproduced in CI
without a commercial simulator license.

## Results

<!-- RESULTS:BEGIN -->
| Metric | Value |
|---|---|
| Tests | 15 |
| Regression | 75 runs (15 tests x 5 seeds), **75/75 pass** |
| Functional coverage | **100.0%** (8 covergroups, 35 coverpoints/crosses, 226 bins) |
| SVA cover properties | 11/11 hit |
| RTL line coverage | **100.0%** (150/150) |
| RTL toggle coverage | 80.7% - the untoggled bits are structurally constant (reserved register bits, unused upper INT/BUSY bits, AxLEN[7:4], AxSIZE, WSTRB, upper ID bits) |
| Scoreboard checks | every APB read, every AXI burst and data beat, every grant, the irq pin on every cycle |
| Formal (SymbiYosys) | BMC depth 40: all 26 AXI4/APB assertions hold under protocol assumptions; 4/4 cover statements reached |
| RTL lint | Verilator `-Wall` clean for NUM_CH = 2, 3, 4, 8; slang `-Wextra -Werror` clean |
| Synthesis (Yosys) | `check -assert` clean; 1305 flip-flops (512 in the burst buffer), ~5.0k cells |
| Bug injection | **14/14** injected RTL bugs detected by simulation, 5/14 also by formal (table below) |
<!-- RESULTS:END -->

### Bug-injection campaign

`scripts/bug_hunt.py` injects realistic design bugs one at a time, rebuilds,
reruns the regression and the formal check, and fails if any bug escapes.

<!-- BUGS:BEGIN -->
Simulation detected 14/14 injected bugs; formal BMC (protocol properties only) detected 5/14.

| ID | Injected bug | Failing tests | Formal BMC | First simulation error |
|---|---|---|---|---|
| BUG-01 | [Burst length ignores the destination 4 KB boundary (AW bursts may cross 4 KB)](docs/bug_reports/BUG-01.md) | 12 (`dma_4k_boundary_test`, `dma_abort_test`, ...) | caught | `UVM_ERROR [SB_AR] ch2 ARLEN=10 expected 4 (rem=294 max_burst=10 src=0x12aa43d4 dst=0x8226dfec)` |
| BUG-02 | [Arbiter degenerates to fixed priority (channel 0 always wins)](docs/bug_reports/BUG-02.md) | 7 (`dma_backpressure_test`, `dma_corner_test`, ...) | - | `UVM_ERROR [SB_RR] round-robin violation: granted ch0, expected ch3 (last grant ch2)` |
| BUG-03 | [ABORT terminates the channel while its burst is still in flight](docs/bug_reports/BUG-03.md) | 2 (`dma_abort_test`, `dma_stress_test`) | - | `UVM_ERROR [SB_REG] read 0x114: DUT=0x04050008 model=0x04050001 (diff 0x00000009)` |
| BUG-04 | [W1C to INT_STATUS clears every pending bit, not only the bits written as 1](docs/bug_reports/BUG-04.md) | 2 (`dma_irq_test`, `dma_stress_test`) | - | `UVM_ERROR [SB_REG] read 0x008: DUT=0x00000000 model=0x00000001 (diff 0x00000001)` |
| BUG-05 | [Read error does not suppress the write burst (garbage written to the destination)](docs/bug_reports/BUG-05.md) | 3 (`dma_error_test`, `dma_irq_test`, ...) | - | `UVM_ERROR [SB_AXI] unexpected write burst: AXI_WRITE id=3 addr=0x83d41e1c len=13 size=2 burst= INCR beats=14` |
| BUG-06 | [AWBURST is always INCR, even for a fixed (FIFO) destination](docs/bug_reports/BUG-06.md) | 2 (`dma_fixed_addr_test`, `dma_stress_test`) | caught | `UVM_ERROR [SB_AW] ch2 AWBURST=1 expected 0` |
| BUG-07 | [WLAST asserted one beat early on bursts longer than 8 beats](docs/bug_reports/BUG-07.md) | 13 (`dma_4k_boundary_test`, `dma_abort_test`, ...) | caught | `UVM_ERROR [AXI_SLV_WLAST] WLAST after 15 beats but AWLEN=15 (16 beats): AXI_WRITE id=0 addr=0x80026d30 len=15 size=2 burst= INCR beats=0` |
| BUG-08 | [CTRL.EN is ignored by the arbiter (channels run while disabled)](docs/bug_reports/BUG-08.md) | 4 (`dma_abort_test`, `dma_corner_test`, ...) | - | `UVM_ERROR [SB_EN] ch2 granted @65355000 while CTRL.EN=0` |
| BUG-09 | [START while busy restarts the channel when no burst is in flight](docs/bug_reports/BUG-09.md) | 2 (`dma_corner_test`, `dma_stress_test`) | - | `UVM_ERROR [SB_AR] ch1 ARADDR=0x11cc3488 expected 0x112e4718` |
| BUG-10 | [Channel offset 0x18 decoded as a register (no PSLVERR)](docs/bug_reports/BUG-10.md) | 1 (`dma_apb_err_test`) | - | `UVM_ERROR [SB_APB] missing PSLVERR on unmapped access: WR addr=0x118 data=0x2b2b6c4c` |
| BUG-11 | [Write data pointer advances without WREADY (data lost under back-pressure)](docs/bug_reports/BUG-11.md) | 13 (`dma_4k_boundary_test`, `dma_abort_test`, ...) | caught | `UVM_ERROR [AXI_SVA] W payload changed while waiting for WREADY` |
| BUG-12 | [Channel reports DONE one word early when the last burst is longer than one beat](docs/bug_reports/BUG-12.md) | 11 (`dma_4k_boundary_test`, `dma_abort_test`, ...) | - | `UVM_ERROR [SB_IRQ] irq=1 expected 0 (INT_STATUS=0x00000000 INT_ENABLE=0x00000f0f)` |
| BUG-13 | [Software W1C wins over a hardware set in the same cycle (interrupt lost)](docs/bug_reports/BUG-13.md) | 1 (`dma_irq_test`) | - | `UVM_ERROR [SB_IRQ] irq=0 expected 1 (INT_STATUS=0x00000001 INT_ENABLE=0x00000f0f)` |
| BUG-14 | [Off-by-one in the source 4 KB room computation](docs/bug_reports/BUG-14.md) | 9 (`dma_4k_boundary_test`, `dma_backpressure_test`, ...) | caught | `UVM_ERROR [SB_AR] ch2 ARLEN=1 expected 2 (rem=62 max_burst=2 src=0x127c8ff4 dst=0x8223d50c)` |

Full table: [`docs/bug_hunt_results.md`](docs/bug_hunt_results.md).
<!-- BUGS:END -->

## Design under test

`rtl/dma_top.sv` - spec in [`docs/spec.md`](docs/spec.md).

```
             APB3 slave                              AXI4 master
  CPU ---> dma_apb_regs ---> dma_channel x4 ---> dma_rr_arbiter ---> dma_axi_engine ---> memory
           (CFG/SRC/DST/LEN,  (working copy of     (round robin,      (AR -> 16-word buffer
            CMD, STAT, INT)    the descriptor,      burst granularity)  -> AW/W -> B,
                               status)                                   4 KB split)
                                                                    irq = |(INT_STATUS & INT_ENABLE)
```

* per channel: source/destination address, length in words, max burst
  length (1-16 beats), incrementing or fixed (FIFO) addressing
* bursts never cross a 4 KB boundary: `beats = min(REMAIN, MAX_BURST+1, 4 KB room of SRC, 4 KB room of DST)`
* SLVERR/DECERR handling (a read error suppresses the write), abort at burst
  boundary, global enable/pause, LEN=0, START ignored while busy, W1C
  interrupts where a hardware set wins over a same-cycle clear
* PSLVERR on unmapped/misaligned APB accesses

## Testbench

```
 dma_base_test ── vseq ─► dma_virtual_sequencer
                              │ regmodel (uvm_reg_block, sub-block per channel, frontdoor via APB)
 ┌──────────────────────────── dma_env ─────────────────────────────────────────┐
 │  apb_agent (active)  ──APB──►  dma_top  ──AXI4──►  axi_agent (reactive slave) │
 │     mon │                        │ irq                 mon │   + axi_mem       │
 │         ├─► uvm_reg_predictor ─► mirror                    │                   │
 │         └──────────► dma_scoreboard ◄──────────────────────┘                   │
 │                       (cycle-exact model, irq check) ──cov events──► coverage │
 └───────────────────────────────────────────────────────────────────────────────┘
   SVA bound into dma_top: AXI4 protocol (both directions), APB, irq
```

| Component | Highlights |
|---|---|
| `tb/agents/apb` | APB3 master: random idle cycles and back-to-back transfers, PREADY timeout |
| `tb/agents/axi` | AXI4 slave with five independent channel threads, random ready-early / delayed READY, R gaps, B latency, SLVERR/DECERR error regions, seed-dependent memory content, peripheral FIFO windows for FIXED bursts |
| `tb/ral` | register model with hierarchical sub-blocks (`add_submap`), volatile HW status fields, W1C, WO command register excluded from the automatic register tests, explicit predictor |
| `tb/env/dma_scoreboard.svh` | reference model that stores every architectural bit with the clock edge it changes at - so every register read, every arbitration decision and the irq pin can be compared exactly, independent of monitor ordering |
| `tb/env/dma_coverage.svh` | 8 covergroups sampled from scoreboard events (why a burst was cut, abort in flight vs. waiting, requesting set at each grant, ...) |
| `tb/sva` | AXI4 handshake/stability rules, 4 KB, outstanding limits, APB phases, irq equation; failures go through `uvm_error` |
| `tb/seq` | transfer descriptor with per-channel address windows, base virtual sequence with register helpers and an end-to-end memory check (source snapshot + guard words) |
| `formal/` | SymbiYosys harness: free APB master / AXI slave under protocol assumptions, AXI master rules as assertions |

Verification plan with the feature -> check -> test mapping and the coverage
model: [`docs/verification_plan.md`](docs/verification_plan.md). Design and
testbench decisions (and Verilator notes): [`docs/design_decisions.md`](docs/design_decisions.md).

### Tests

| Test | What it does |
|---|---|
| `dma_reg_hw_reset_test` | UVM built-in reset-value check |
| `dma_reg_bit_bash_test` | UVM built-in bit-bash, then restore and re-check |
| `dma_smoke_test` | one transfer, irq, W1C |
| `dma_single_ch_test` | sequential random transfers on random channels |
| `dma_multi_ch_test` | four concurrent random transfers, several rounds |
| `dma_4k_boundary_test` | addresses just below 4 KB boundaries |
| `dma_fixed_addr_test` | FIFO->memory, memory->FIFO, FIFO->FIFO, fixed memory source |
| `dma_error_test` | SLVERR/DECERR on read/write at a random word, one failing channel among running ones, restart |
| `dma_abort_test` | abort at random times, while paused, with a burst in flight and EN=0, START+ABORT, abort on idle |
| `dma_pause_resume_test` | START while disabled, run/freeze/run |
| `dma_irq_test` | every INT_ENABLE combination, partial W1C, multiple sources, W1C hammering |
| `dma_backpressure_test` | long random delays, always ready, always late |
| `dma_corner_test` | LEN=0/1/65535, every LEN class x MAX_BURST class, START while busy, reprogram while busy, 32-bit address wrap |
| `dma_apb_err_test` | random unmapped/misaligned accesses, CMD reads as 0 |
| `dma_stress_test` | all channels + random errors, aborts, spurious STARTs, EN toggling, W1C, INT_ENABLE changes |

## Running

Requirements: Verilator >= 5.036 (tested with 5.053), `z3` on `PATH`
(Verilator's constraint solver), Python 3, git. The
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) provides all
of them plus slang, Yosys and SymbiYosys.

```bash
make uvm                                  # fetch Accellera UVM 2020.3.1 into third_party/
make build                                # ~3 min: one binary for all tests
make run TEST=dma_stress_test SEED=7      # one test (VERBOSITY=UVM_MEDIUM for the model trace)
make regress SEEDS=3                      # all tests x seeds + merged coverage -> build/regress/summary.md
make lint slang synth formal              # static checks, synthesis, formal
make bugs                                 # bug-injection campaign (~1 h)
```

`WAVES=1` builds with VCD tracing (`make run ... WAVES=1` writes `waves.vcd`).

Vivado XSim users: `python sim/xsim/run_xsim.py --regress` compiles against
Vivado's UVM 1.2 (the code is written to the common UVM 1.2 / 1800.2 API and
passes slang's strict elaboration, but only the Verilator flow runs in CI).

## Repository layout

```
rtl/        DUT (dma_top, dma_apb_regs, dma_channel, dma_rr_arbiter, dma_axi_engine, dma_pkg)
tb/         agents/{apb,axi}, ral/, env/, seq/, tests/, sva/, top/
formal/     SymbiYosys harness and script
sim/        filelist, Verilator DPI glue + coverage config, XSim script
scripts/    run_regression.py, coverage_report.py, bug_hunt.py
docs/       spec, verification plan, design decisions, bug-hunt results
.github/    CI: lint, slang, synth, formal, build, regression
```

## Limitations / next steps

* One burst in flight: throughput is roughly half of the bus bandwidth;
  overlapping the next read with the current write is the natural extension.
* No mid-transfer reset test, `NUM_CH` fixed to 4 in the testbench.
* Toggle coverage is reported for review, not closed (see the table above).
