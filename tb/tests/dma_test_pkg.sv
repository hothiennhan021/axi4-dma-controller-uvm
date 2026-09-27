// -----------------------------------------------------------------------------
// dma_test_pkg - test library
// -----------------------------------------------------------------------------
package dma_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_pkg::*;
  import axi_pkg::*;
  import dma_ral_pkg::*;
  import dma_env_pkg::*;
  import dma_seq_pkg::*;

  `include "dma_base_test.svh"
  `include "dma_tests.svh"

endpackage : dma_test_pkg
