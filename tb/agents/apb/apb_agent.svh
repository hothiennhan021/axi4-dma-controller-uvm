// -----------------------------------------------------------------------------
// apb_agent - APB3 master agent (active) / monitor only (passive)
// -----------------------------------------------------------------------------
typedef uvm_sequencer #(apb_seq_item) apb_sequencer;

class apb_agent extends uvm_agent;

  `uvm_component_utils(apb_agent)

  apb_agent_cfg cfg;
  apb_sequencer sqr;
  apb_driver    drv;
  apb_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(apb_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "apb_agent_cfg not found")
    if (cfg.vif == null) `uvm_fatal("NOVIF", "apb_agent_cfg.vif is null")
    uvm_config_db#(apb_agent_cfg)::set(this, "*", "cfg", cfg);
    mon = apb_monitor::type_id::create("mon", this);
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr = apb_sequencer::type_id::create("sqr", this);
      drv = apb_driver::type_id::create("drv", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : apb_agent
