// -----------------------------------------------------------------------------
// Test library - one test per virtual sequence (see docs/verification_plan.md)
// -----------------------------------------------------------------------------

`define DMA_TEST(TNAME, VSEQ) \
  class TNAME extends dma_base_test; \
    `uvm_component_utils(TNAME) \
    function new(string name, uvm_component parent); \
      super.new(name, parent); \
      vseq_type = VSEQ::get_type(); \
    endfunction \
  endclass

`DMA_TEST(dma_reg_hw_reset_test,  dma_reg_hw_reset_vseq)
`DMA_TEST(dma_reg_bit_bash_test,  dma_reg_bit_bash_vseq)
`DMA_TEST(dma_smoke_test,         dma_smoke_vseq)
`DMA_TEST(dma_single_ch_test,     dma_single_ch_vseq)
`DMA_TEST(dma_multi_ch_test,      dma_multi_ch_vseq)
`DMA_TEST(dma_4k_boundary_test,   dma_4k_boundary_vseq)
`DMA_TEST(dma_fixed_addr_test,    dma_fixed_addr_vseq)
`DMA_TEST(dma_error_test,         dma_error_vseq)
`DMA_TEST(dma_abort_test,         dma_abort_vseq)
`DMA_TEST(dma_pause_resume_test,  dma_pause_resume_vseq)
`DMA_TEST(dma_irq_test,           dma_irq_vseq)
`DMA_TEST(dma_backpressure_test,  dma_backpressure_vseq)
`DMA_TEST(dma_corner_test,        dma_corner_vseq)
`DMA_TEST(dma_apb_err_test,       dma_apb_err_vseq)
`DMA_TEST(dma_stress_test,        dma_stress_vseq)

`undef DMA_TEST
