// -----------------------------------------------------------------------------
// dma_virtual_sequencer - handles the virtual sequences need
// -----------------------------------------------------------------------------
class dma_virtual_sequencer extends uvm_sequencer;

  `uvm_component_utils(dma_virtual_sequencer)

  apb_sequencer  apb_sqr;
  dma_reg_block  regmodel;
  axi_mem        mem;
  axi_slave_cfg  axi_cfg;
  dma_env_cfg    cfg;
  virtual irq_if irq_vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : dma_virtual_sequencer
