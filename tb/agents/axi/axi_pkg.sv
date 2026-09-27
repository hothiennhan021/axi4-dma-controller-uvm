// -----------------------------------------------------------------------------
// axi_pkg - AXI4 slave UVM agent with memory model
// -----------------------------------------------------------------------------
package axi_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axi_txn.svh"
  `include "axi_slave_cfg.svh"
  `include "axi_mem.svh"
  `include "axi_slave_driver.svh"
  `include "axi_monitor.svh"
  `include "axi_agent.svh"

endpackage : axi_pkg
