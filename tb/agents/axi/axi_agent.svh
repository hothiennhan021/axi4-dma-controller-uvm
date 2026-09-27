// -----------------------------------------------------------------------------
// axi_agent - AXI4 slave agent (responder + monitor)
// -----------------------------------------------------------------------------
class axi_agent extends uvm_agent;

  `uvm_component_utils(axi_agent)

  axi_slave_cfg    cfg;
  axi_mem          mem;
  axi_slave_driver drv;
  axi_monitor      mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "axi_slave_cfg not found")
    if (cfg.vif == null) `uvm_fatal("NOVIF", "axi_slave_cfg.vif is null")
    if (!uvm_config_db#(axi_mem)::get(this, "", "mem", mem))
      `uvm_fatal("NOMEM", "axi_mem not found")
    uvm_config_db#(axi_slave_cfg)::set(this, "*", "cfg", cfg);
    uvm_config_db#(axi_mem)::set(this, "*", "mem", mem);
    mon = axi_monitor::type_id::create("mon", this);
    if (cfg.is_active == UVM_ACTIVE) drv = axi_slave_driver::type_id::create("drv", this);
  endfunction

endclass : axi_agent
