# DMA controller - design specification

`dma_top` is a 4-channel (parameter `NUM_CH`, 2..8) memory-to-memory DMA
controller. Software programs it through an APB3 slave port; data moves
through an AXI4 master port. One interrupt line reports completion and errors.

```
            APB3 slave                         AXI4 master (32-bit data)
  psel/penable/pwrite/paddr/pwdata --+     +--> AR  --+
  prdata/pready/pslverr <------------+     |    R   <-+   one burst in flight:
                                     |     |    AW  --+   read burst -> buffer -> write burst
                            +--------v-----+-+  W   --+
                            | dma_apb_regs   |  B   <-+
                            +--------+-------+
          CFG/SRC/DST/LEN/START/ABORT|   ^ STAT
                     +---------------v---+-----------+
                     | dma_channel x NUM_CH           |  working copies of
                     |  busy, abort_pend, cur_src,    |  the descriptor
                     |  cur_dst, rem, sticky status   |
                     +---------------+---------------+
                                req  |  ^ burst result
                     +---------------v--+   +----------------+
                     | dma_rr_arbiter   +-->| dma_axi_engine |
                     +------------------+   +----------------+
                     irq = |(INT_STATUS & INT_ENABLE)
```

## 1. Interfaces

| Port group | Notes |
|---|---|
| `clk`, `rst_n` | single clock; `rst_n` asynchronous assert, synchronous de-assert expected |
| APB3 slave | 12-bit address, 32-bit data, zero wait states (`PREADY` tied high), `PSLVERR` on unmapped/misaligned accesses |
| AXI4 master | `ID_W`-bit IDs (ID = channel number), 32-bit address and data, `AxSIZE`=4 bytes, `AxLEN` <= 15, `AxBURST` INCR or FIXED, `WSTRB`=`0xF`. The subset used has no `AxLOCK/AxCACHE/AxPROT/AxQOS` (tie them off at the interconnect if needed). |
| `irq` | active-high level interrupt |

## 2. Register map

All registers are 32 bits. Reserved bits read as 0, writes to them are ignored.

| Offset | Name | Access | Reset | Fields |
|---|---|---|---|---|
| 0x000 | ID | RO | `0xDA0C_01xx` | `[7:0]` NUM_CH, `[15:8]` VERSION, `[31:16]` magic `0xDA0C` |
| 0x004 | CTRL | RW | 0 | `[0]` EN - global enable |
| 0x008 | INT_STATUS | W1C | 0 | `[NUM_CH-1:0]` DONE, `[8+NUM_CH-1:8]` ERR |
| 0x00C | INT_ENABLE | RW | 0 | same layout as INT_STATUS |
| 0x010 | BUSY | RO | 0 | `[NUM_CH-1:0]` channel busy |
| 0x100+0x20*n | CHn_CFG | RW | 0x3F | `[3:0]` MAX_BURST (beats-1), `[4]` SRC_INC, `[5]` DST_INC |
| +0x04 | CHn_SRC | RW | 0 | `[31:2]` source byte address (word aligned) |
| +0x08 | CHn_DST | RW | 0 | `[31:2]` destination byte address |
| +0x0C | CHn_LEN | RW | 0 | `[15:0]` length in 32-bit words |
| +0x10 | CHn_CMD | WO | - | `[0]` START, `[1]` ABORT (write 1; read as 0) |
| +0x14 | CHn_STAT | RO | 0 | `[0]` BUSY, `[1]` DONE, `[2]` ERR, `[3]` ABORTED, `[5:4]` ERR_RESP, `[6]` ERR_WR, `[31:16]` REMAIN |

Accesses to any other address (including offsets 0x18/0x1C of a channel
window, channels `>= NUM_CH` and `PADDR[1:0] != 0`) complete with `PSLVERR=1`,
read as 0 and have no side effect.

## 3. Operation

### 3.1 Starting a transfer
Software writes CFG/SRC/DST/LEN, then `CMD.START=1`.
* START is accepted only while the channel is idle; it is silently ignored
  while the channel is busy.
* On an accepted START the descriptor is copied into working registers and
  DONE/ERR/ABORTED/ERR_RESP/ERR_WR are cleared. Software may immediately
  reprogram CFG/SRC/DST/LEN for the next transfer; the running transfer is not
  affected and the registers read back the new values.
* `LEN=0` completes immediately: DONE=1, `INT_STATUS.DONE[n]=1`, no bus traffic.
* The channel stays busy until it completes, fails or is aborted.

### 3.2 Bursts and arbitration
Channels are served round-robin at burst granularity (after channel *k* the
search starts at *k+1*), only while `CTRL.EN=1`. START is accepted while
`EN=0`; the channel waits. Clearing EN never interrupts a burst already in
flight.

For each grant the engine computes

```
beats = min(REMAIN,
            MAX_BURST + 1,
            (4096 - SRC[11:0]) / 4   if SRC_INC,
            (4096 - DST[11:0]) / 4   if DST_INC)
```

so no INCR burst crosses a 4 KB boundary, issues one read burst
(`ARBURST = SRC_INC ? INCR : FIXED`), buffers the data, then issues one write
burst of the same length (`AWBURST = DST_INC ? INCR : FIXED`) with AWVALID and
WVALID raised together, and waits for B. Only one burst is in flight at a
time. After an OKAY write response SRC/DST advance by `4*beats` (when
incrementing; 32-bit wrap-around) and REMAIN decreases by `beats`.

### 3.3 Completion and errors
* Last burst OKAY: BUSY=0, DONE=1, `INT_STATUS.DONE[n]` set - in the cycle of
  the B handshake.
* Any R beat with RRESP = SLVERR/DECERR: the remaining R beats are accepted,
  the write burst is **not** issued, the channel stops with ERR=1, ERR_WR=0,
  ERR_RESP = first error response, `INT_STATUS.ERR[n]` set - in the cycle of
  the last R beat.
* BRESP = SLVERR/DECERR: ERR=1, ERR_WR=1, ERR_RESP=BRESP - in the cycle of the
  B handshake.
* On an error REMAIN and the working addresses are not advanced for the
  failed burst, so `LEN - REMAIN` words were delivered successfully.

### 3.4 Abort
`CMD.ABORT=1` is accepted while the channel is busy and not finishing in the
same cycle (it is ignored on an idle channel). The channel receives no further
grants; a burst already in flight completes normally, then the channel stops
one cycle later with ABORTED=1 (no interrupt). If that burst was the last one
the channel reports DONE instead. START and ABORT written together start the
channel and abort it before its first burst (ABORTED=1, REMAIN=LEN).

### 3.5 Interrupts
`INT_STATUS` bits are set by hardware and cleared by writing 1. A hardware set
and a software clear of the same bit in the same cycle leave the bit set.
`irq = |(INT_STATUS & INT_ENABLE)`.

## 4. Timing summary

| Event | Visible to software / on irq |
|---|---|
| START accepted (APB access phase, edge *t*) | BUSY=1 after *t* |
| grant | one cycle after the engine becomes idle, earliest one cycle after START |
| last B handshake (edge *t*) | BUSY=0, DONE=1, INT_STATUS set after *t* |
| ABORT with no burst in flight (edge *t*) | ABORTED after *t*+1 |
| ABORT with burst in flight, burst ends at edge *t* | ABORTED after *t*+1 |
