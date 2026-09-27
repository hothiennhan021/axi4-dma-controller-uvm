// -----------------------------------------------------------------------------
// dma_pkg - shared constants for the AXI4 DMA controller
//
// Register map (APB3, 32-bit registers, byte addresses):
//
//   0x000  ID          RO   {16'hDA0C, VERSION[7:0], NUM_CH[7:0]}
//   0x004  CTRL        RW   [0] EN - global enable (no new bursts are granted while 0)
//   0x008  INT_STATUS  W1C  [NUM_CH-1:0] DONE per channel, [8+NUM_CH-1:8] ERR per channel
//   0x00C  INT_ENABLE  RW   same layout as INT_STATUS; irq = |(INT_STATUS & INT_ENABLE)
//   0x010  BUSY        RO   [NUM_CH-1:0] channel busy
//
//   Channel n, base = 0x100 + 0x20*n
//   +0x00  CFG         RW   [3:0] MAX_BURST (beats-1), [4] SRC_INC, [5] DST_INC
//   +0x04  SRC         RW   [31:2] source address (word aligned, [1:0] read as 0)
//   +0x08  DST         RW   [31:2] destination address
//   +0x0C  LEN         RW   [15:0] transfer length in 32-bit words
//   +0x10  CMD         WO   [0] START, [1] ABORT (self clearing, reads as 0)
//   +0x14  STAT        RO   [0] BUSY, [1] DONE, [2] ERR, [3] ABORTED,
//                           [5:4] ERR_RESP, [6] ERR_WR, [31:16] REMAIN
//
// Any access to an unmapped or misaligned address completes with PSLVERR=1,
// has no side effect and reads as 0.
// -----------------------------------------------------------------------------
package dma_pkg;

  // Not every constant is used by every module (some are for documentation
  // and for the testbench).
  /* verilator lint_off UNUSEDPARAM */

  localparam logic [15:0] DMA_ID_MAGIC = 16'hDA0C;
  localparam logic [7:0]  DMA_VERSION  = 8'h01;

  // Global registers
  localparam logic [11:0] REG_ID         = 12'h000;
  localparam logic [11:0] REG_CTRL       = 12'h004;
  localparam logic [11:0] REG_INT_STATUS = 12'h008;
  localparam logic [11:0] REG_INT_ENABLE = 12'h00C;
  localparam logic [11:0] REG_BUSY       = 12'h010;

  // Channel register window
  localparam logic [11:0] CH_BASE   = 12'h100;
  localparam logic [11:0] CH_STRIDE = 12'h020;
  localparam int unsigned MAX_CH    = 8;       // register map room

  // Channel register offsets (within the 32-byte channel window)
  localparam logic [4:0] CH_CFG  = 5'h00;
  localparam logic [4:0] CH_SRC  = 5'h04;
  localparam logic [4:0] CH_DST  = 5'h08;
  localparam logic [4:0] CH_LEN  = 5'h0C;
  localparam logic [4:0] CH_CMD  = 5'h10;
  localparam logic [4:0] CH_STAT = 5'h14;

  // Reset value of CH_CFG: 16-beat bursts, incrementing source and destination
  localparam logic [5:0] CFG_RESET = 6'h3F;

  // Interrupt bit layout
  localparam int unsigned INT_ERR_LSB = 8;

  // AXI encodings
  localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
  localparam logic [1:0] AXI_BURST_INCR  = 2'b01;
  localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
  localparam logic [1:0] AXI_RESP_EXOKAY = 2'b01;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
  localparam logic [1:0] AXI_RESP_DECERR = 2'b11;
  localparam logic [2:0] AXI_SIZE_4B     = 3'b010;

  // Maximum burst length supported by the engine (AXI4 INCR allows 256,
  // FIXED allows 16; the engine buffers one burst internally).
  localparam int unsigned MAX_BEATS = 16;

  /* verilator lint_on UNUSEDPARAM */

endpackage : dma_pkg
