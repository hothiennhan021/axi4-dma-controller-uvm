// -----------------------------------------------------------------------------
// dma_env_pkg - environment: scoreboard, coverage, virtual sequencer, env
// -----------------------------------------------------------------------------
`include "dma_tb_defines.svh"

package dma_env_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_pkg::*;
  import axi_pkg::*;
  import dma_ral_pkg::*;

  `include "dma_env_cfg.svh"
  `include "dma_cov_evt.svh"
  `include "dma_scoreboard.svh"
  `include "dma_coverage.svh"
  `include "dma_virtual_sequencer.svh"
  `include "dma_env.svh"

endpackage : dma_env_pkg
