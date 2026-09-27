# Verification plan - AXI4 DMA controller

## 1. Scope

Block-level verification of `dma_top` (RTL in `rtl/`, spec in
[`spec.md`](spec.md)) with a UVM 1800.2 testbench. The APB port is driven by
an active master agent, the AXI4 port is served by a reactive slave agent with
a memory model, the interrupt pin is checked every cycle.

Out of scope: multi-clock / CDC, reset asserted in the middle of a transfer,
`NUM_CH` values other than 4 (the RTL is parameterised, the testbench is
configured for 4 channels), AXI features the DUT does not use (WRAP bursts,
narrow transfers, exclusive access, out-of-order responses).

## 2. Testbench architecture

```
                  +---------------------------- dma_env -----------------------------+
                  |                                                                  |
 dma_base_test -->|  vsqr (virtual sequencer)                                        |
   vseq           |    |  regmodel (uvm_reg_block, frontdoor via APB)                |
                  |    v                                                             |
                  |  apb_agent (active)                    axi_agent (reactive slave)|
                  |   sqr -> drv --APB--> [ dma_top ] --AXI4--> drv (5 channel       |
                  |           mon            |  irq          threads) + axi_mem      |
                  |            |             |                mon                    |
                  |            +--> uvm_reg_predictor -> regmodel mirror             |
                  |            +------------+                 |                      |
                  |                         v                 v                      |
                  |                   dma_scoreboard  <-------+  (bursts, AR reqs)   |
                  |                    (cycle-aware reference model, irq check)      |
                  |                         | cov events                             |
                  |                         v                                        |
                  |                    dma_coverage (8 covergroups)                  |
                  +------------------------------------------------------------------+
   SVA bound into dma_top: axi4_protocol_sva, apb_protocol_sva, dma_irq_sva
```

| Component | Role |
|---|---|
| `apb_agent` | APB3 master driver (random idle cycles, PREADY timeout), monitor |
| `axi_agent` | AXI4 slave: independent AR/R/AW/W/B threads, random ready-early / delayed READY, random R gaps and B latency, SLVERR/DECERR error regions, memory model with seed-dependent content and peripheral FIFO windows; passive monitor publishing completed bursts and read-address requests |
| `dma_reg_block` | RAL model: global registers + one sub-block per channel mapped with `add_submap`; volatile HW-status fields; CMD excluded from automatic register tests |
| `dma_scoreboard` | reference model of every architectural state bit with the edge at which it changes, see §5 |
| `dma_coverage` | functional coverage (§6), sampled from scoreboard events |
| SVA | AXI4 handshake/stability rules for both directions, burst restrictions, outstanding limits, APB phase rules, irq equation |

## 3. Features and how they are verified

| ID | Feature (spec §) | Check | Stimulus (test) |
|---|---|---|---|
| F01 | Register reset values (§2) | `uvm_reg_hw_reset_seq` | `dma_reg_hw_reset_test` |
| F02 | Register access policies RW/RO/W1C (§2) | `uvm_reg_bit_bash_seq` + reset re-check | `dma_reg_bit_bash_test` |
| F03 | Unmapped/misaligned APB access -> PSLVERR, RDATA=0, no side effect (§2) | scoreboard, SVA `a_prdata_zero_on_err`, sequence readback | `dma_apb_err_test` |
| F04 | Memory-to-memory copy, INCR bursts (§3.2) | scoreboard (AR/AW address, length, W data = R data), end-to-end memory compare | `dma_smoke_test`, `dma_single_ch_test` |
| F05 | Burst length = min(REMAIN, MAX_BURST+1, 4 KB room) (§3.2) | scoreboard `SB_AR`/`SB_AW`, SVA `a_*_4k` | `dma_4k_boundary_test`, `dma_corner_test` (every MAX_BURST) |
| F06 | FIXED bursts / peripheral FIFOs (§3.2) | scoreboard burst type, FIFO sink order check | `dma_fixed_addr_test` |
| F07 | Round-robin arbitration, one burst in flight (§3.2) | scoreboard `SB_RR`, `SB_ARB`, SVA single-outstanding | `dma_multi_ch_test`, `dma_stress_test` |
| F08 | Global enable pauses grants, never a burst in flight (§3.2) | scoreboard `SB_EN`, REMAIN frozen while disabled | `dma_pause_resume_test` |
| F09 | Read/write error responses, ERR/ERR_WR/ERR_RESP/REMAIN (§3.3) | scoreboard (no write burst after read error, STAT), partial-copy check | `dma_error_test`, `dma_stress_test` |
| F10 | Abort at burst boundary, START+ABORT, abort on idle (§3.4) | scoreboard abort timing (`SB_ABORT`), STAT/REMAIN, partial copy | `dma_abort_test`, `dma_stress_test` |
| F11 | START ignored while busy, reprogramming while busy (§3.1) | scoreboard, end-to-end copy of the original transfer | `dma_corner_test`, `dma_stress_test` |
| F12 | LEN=0 (§3.1) | scoreboard (no traffic, DONE, INT) | `dma_corner_test`, `dma_stress_test` |
| F13 | INT_STATUS W1C, set-wins-over-clear, irq masking (§3.5) | per-cycle irq model in scoreboard, SVA `a_irq` | `dma_irq_test` (incl. W1C hammering) |
| F14 | AXI back-pressure on every channel, W before AW, ready-before-valid | SVA stability rules, scoreboard data | `dma_backpressure_test` |
| F15 | 32-bit address wrap between bursts | scoreboard address prediction | `dma_corner_test` |
| F16 | Everything concurrently | all checkers | `dma_stress_test` |

## 4. Tests

| Test | Description |
|---|---|
| `dma_reg_hw_reset_test` | built-in reset-value sequence |
| `dma_reg_bit_bash_test` | built-in bit-bash, then restore and re-check reset values |
| `dma_smoke_test` | one 64-word transfer, irq, W1C |
| `dma_single_ch_test` | 24 sequential random transfers on random channels |
| `dma_multi_ch_test` | 6 rounds of 4 concurrent random transfers |
| `dma_4k_boundary_test` | addresses just below 4 KB boundaries, staggered src/dst |
| `dma_fixed_addr_test` | FIFO->memory, memory->FIFO, FIFO->FIFO, fixed plain memory |
| `dma_error_test` | SLVERR/DECERR on read and write at random word, one failing channel among running ones, restart after error |
| `dma_abort_test` | abort after random delay, abort while paused, START+ABORT, abort on idle channel, restart |
| `dma_pause_resume_test` | START while disabled, run/freeze/run cycles |
| `dma_irq_test` | every INT_ENABLE combination per channel, partial W1C, several pending sources, W1C hammering |
| `dma_backpressure_test` | long random delays, always-ready, always-late |
| `dma_corner_test` | LEN=0/1, all MAX_BURST values, START while busy (in flight / paused / other channel owning the engine), reprogram while busy, address wrap, 4096-word transfer |
| `dma_apb_err_test` | 120 random unmapped/misaligned accesses interleaved with legal ones |
| `dma_stress_test` | 4 channel threads (random config incl. FIXED, LEN=0, errors, aborts, spurious STARTs) + background EN toggling / W1C / INT_ENABLE changes |

## 5. Checking strategy

The scoreboard keeps, for every piece of architectural state (channel busy,
abort pending, STAT word, INT_STATUS, INT_ENABLE, CTRL.EN), the current value,
the previous value and the clock edge at which it changed. Monitors sample
right after a rising edge, i.e. they observe the values from *before* that
edge, so the value expected by any observation at time *t* is "new if the
change happened strictly before *t*". This makes the model independent of the
order in which the APB and AXI monitors deliver events of the same edge and
lets it compare **every** register read and the irq pin on **every** cycle
exactly, without tolerance windows.

Per burst it predicts channel, address, length (and why it was cut), burst
type and data; per read-address request it checks the arbitration decision
against the requesting set at the grant edge, the EN and abort state. Abort
completion is scheduled one cycle after the burst boundary and resolved
lazily (a grant in the same edge as the ABORT write legitimately wins).

Independent of all monitors, every sequence compares the destination memory
(or FIFO sink) with a snapshot of the source taken before START, including
guard words around the destination buffer.

## 6. Functional coverage model

| Covergroup | Items |
|---|---|
| `cg_start` | channel, LEN bins (0, 1, 2-15, 16, 17-64, 65-1023, >=1024), MAX_BURST bins, SRC_INC x DST_INC, LEN x MAX_BURST, START+ABORT |
| `cg_burst` | direction, beats 1..16, FIXED/INCR, response OKAY/SLVERR/DECERR per direction, reason the burst was cut (length / MAX_BURST / 4 KB) per direction, address-channel wait bins, burst type x beats |
| `cg_wr_order` | first W beat before / after AW handshake |
| `cg_grant` | granted channel x number of requesting channels |
| `cg_finish` | channel x {done, read error, write error, aborted} |
| `cg_cmd` | START ignored, ABORT ignored, ABORT {waiting, in flight} x {enabled, paused} |
| `cg_apb` | region (global/channel/unmapped/misaligned) x direction, channel register x direction |
| `cg_irq` | cause (done/err/both), masked sources pending |

SVA cover properties add protocol situations (AR wait, 16-beat burst, burst
ending exactly at 4 KB, back-to-back R beats, W before AW, error responses...).

## 7. Closure criteria

* All tests pass on every seed of the regression (`make regress SEEDS=N`).
* Functional coverage 100% of the bins that are reachable (holes explained).
* RTL line coverage 100%, toggle coverage reviewed.
* Every injected bug of `scripts/bug_hunt.py` detected by at least one test.
