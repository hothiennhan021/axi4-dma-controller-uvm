// -----------------------------------------------------------------------------
// dma_env_cfg - environment configuration
// -----------------------------------------------------------------------------
class dma_env_cfg extends uvm_object;

  `uvm_object_utils(dma_env_cfg)

  int unsigned   num_ch        = 4;
  time           clk_period    = 10ns;
  bit            has_coverage  = 1;
  bit            has_scoreboard = 1;

  apb_agent_cfg  apb_cfg;
  axi_slave_cfg  axi_cfg;
  axi_mem        mem;
  virtual irq_if irq_vif;
  virtual rst_if rst_vif;

  function new(string name = "dma_env_cfg");
    super.new(name);
  endfunction

endclass : dma_env_cfg
