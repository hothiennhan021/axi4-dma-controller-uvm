// -----------------------------------------------------------------------------
// Testbench-wide compile-time configuration
//   DMA_NUM_CH : number of DMA channels of the DUT instance (2..8), default 4.
//                Override with +define+DMA_NUM_CH=<n> (make ... NUM_CH=<n>).
// -----------------------------------------------------------------------------
`ifndef DMA_TB_DEFINES_SVH
`define DMA_TB_DEFINES_SVH

`ifndef DMA_NUM_CH
  `define DMA_NUM_CH 4
`endif

`endif
