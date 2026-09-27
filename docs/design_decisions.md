# Design and testbench decisions

## RTL

**One burst in flight.** The engine reads one burst into a 16-word buffer,
then writes it. This keeps the datapath and the error semantics simple (a read
error never produces a partial write) at the cost of throughput: roughly
`2*beats + ~6` cycles per burst with an ideal slave. Pipelining the next read
under the current write is the obvious next step and is listed in the README.

**Working copies of the descriptor.** START copies CFG/SRC/DST/LEN into the
channel, so software can prepare the next transfer while the current one runs.
The alternative (locking the registers while busy) needs a PSLVERR policy and
a special predictor in the register model.

**Abort at burst boundary.** Tearing down a burst in the middle is not legal
on AXI (the slave expects all W beats), so ABORT only blocks new grants; the
channel reports ABORTED one cycle after the burst in flight completes. When
that burst was the last one the transfer is complete and DONE wins.

**Burst length rule.** `min(REMAIN, MAX_BURST+1, 4 KB room of SRC, 4 KB room
of DST)` - the same length is used for the read and the write burst so the
buffer never holds more than one burst and FIXED/INCR combinations are
symmetric.

**Interrupt set wins over clear.** Losing an interrupt because software
happened to clear another event in the same cycle is a classic bug; the
INT_STATUS update is `(status & ~clr) | set`.

**AXI outputs from flops only.** VALIDs are decoded from the FSM state and
per-burst pending flags, payloads come from registers or the buffer, so the
master has no input-to-output combinational path.

## Testbench

**Timed reference model instead of tolerance windows.** Many DMA
scoreboards only compare data and accept "eventually" for status. Here every
architectural bit is stored with the edge at which it changes and every APB
read, every grant and the irq pin on every cycle are compared exactly. The
trick that makes this robust is the sampling rule ("a monitor sample at edge
*t* sees values from before *t*"), which removes any dependency on the order
in which analysis ports deliver same-edge events.

**The scoreboard is the coverage source.** Why a burst was cut (length,
MAX_BURST or 4 KB), whether an ABORT hit a burst in flight, how many channels
were requesting at a grant - only the model knows. It publishes
`dma_cov_evt` objects and `dma_coverage` stays a pure subscriber.

**Reactive AXI slave without a sequencer.** Responses are fully determined by
the memory model and the configuration object (delays, error regions, FIFO
windows), which tests change at run time. A response sequence would add
indirection without adding controllability.

**Memory content from a hash.** Never-written words read as
`hash(address ^ seed_salt)`: every source buffer is unique and reproducible
without initialisation traffic, and the salt changes with the seed.

**FIFO windows.** A FIXED burst to a plain memory word would only prove the
last word landed. FIFO windows turn reads into a stream and writes into a sink
queue, so FIXED transfers are checked beat by beat and in order.

**End-to-end check independent of the monitors.** Every sequence snapshots
the expected data before START and compares the destination memory (plus a
guard word before and after) at the end, so a monitor bug cannot hide a DUT
bug.

**Register model.** Hardware-updated fields are volatile (not compared by the
RAL mirror); the scoreboard checks them. CMD is write-only with side effects
and is excluded from the built-in register tests via the `NO_REG_TESTS`
resource. Prediction is explicit (`uvm_reg_predictor` on the APB monitor), so
the mirror also follows accesses that do not go through the register model.

**SVA report through `uvm_error`.** Assertion failures then count in the UVM
report on every simulator, so a test cannot pass with a failing assertion.

## Simulator notes (Verilator 5.05x)

* Constrained randomisation needs `z3` (or `cvc5`) on `PATH` at run time;
  without it every `randomize()` with constraints fails.
* The UVM DPI is compiled without the HDL backdoor (`UVM_HDL_NO_DPI`, see
  `sim/verilator/uvm_dpi_verilator.cc`); nothing in this testbench uses
  backdoor register access.
* `soft` constraints are honoured whenever satisfiable - including when an
  inline range merely *allows* values outside the soft range. The transfer
  descriptor therefore has no soft length default; every sequence states its
  length range explicitly.
* The generated C++ for the UVM class library is large; building it at `-O0`
  in 16 translation units takes about 3 minutes on 2 cores / 8 GB instead of
  more than 15 at `-Os` in 2 units (memory thrashing). Run time is dominated
  by UVM either way.
