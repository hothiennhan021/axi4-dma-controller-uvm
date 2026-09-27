// -----------------------------------------------------------------------------
// apb_agent_cfg - APB agent configuration
// -----------------------------------------------------------------------------
class apb_agent_cfg extends uvm_object;

  `uvm_object_utils(apb_agent_cfg)

  virtual apb_if         vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // Idle cycles inserted by the driver between two transfers
  int unsigned min_idle = 0;
  int unsigned max_idle = 2;

  // PREADY timeout (cycles) - a hung slave is reported instead of hanging
  int unsigned pready_timeout = 64;

  function new(string name = "apb_agent_cfg");
    super.new(name);
  endfunction

endclass : apb_agent_cfg
