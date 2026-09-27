// -----------------------------------------------------------------------------
// dma_base_test - builds the environment and runs one virtual sequence
//
// Derived tests only choose the virtual sequence (vseq_type) and optionally
// tweak the configuration in configure(). The test prints
//   "** TEST PASSED **" / "** TEST FAILED **"
// in report_phase; the regression script keys on that line and on the UVM
// error/fatal counts.
// -----------------------------------------------------------------------------
class dma_base_test extends uvm_test;

  `uvm_component_utils(dma_base_test)

  dma_env              env;
  dma_env_cfg          cfg;
  uvm_object_wrapper   vseq_type;
  time                 drain = 2us;
  time                 watchdog = 20ms;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    vseq_type = dma_smoke_vseq::get_type();
  endfunction

  // Hook for derived tests
  virtual function void configure();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual apb_if apb_vif;
    virtual axi_if axi_vif;
    virtual irq_if irq_vif;
    super.build_phase(phase);

    if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", apb_vif)) `uvm_fatal("NOVIF", "apb_vif")
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", axi_vif)) `uvm_fatal("NOVIF", "axi_vif")
    if (!uvm_config_db#(virtual irq_if)::get(this, "", "irq_vif", irq_vif)) `uvm_fatal("NOVIF", "irq_vif")

    cfg             = dma_env_cfg::type_id::create("cfg");
    cfg.apb_cfg     = apb_agent_cfg::type_id::create("apb_cfg");
    cfg.axi_cfg     = axi_slave_cfg::type_id::create("axi_cfg");
    cfg.mem         = axi_mem::type_id::create("mem");
    cfg.apb_cfg.vif = apb_vif;
    cfg.axi_cfg.vif = axi_vif;
    cfg.irq_vif     = irq_vif;
    configure();

    uvm_config_db#(dma_env_cfg)::set(this, "env", "cfg", cfg);
    env = dma_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    if (uvm_report_enabled(UVM_HIGH, UVM_INFO, "TOPO")) uvm_root::get().print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    uvm_sequence_base vseq;
    uvm_object        obj;
    phase.raise_objection(this);
    obj = vseq_type.create_object("vseq");
    if (!$cast(vseq, obj)) `uvm_fatal("VSEQ", "vseq_type is not a sequence")
    `uvm_info("TEST", $sformatf("running %s (memory salt 0x%08h)", vseq.get_type_name(), cfg.mem.salt), UVM_LOW)
    fork
      begin
        vseq.start(env.vsqr);
      end
      begin
        #(watchdog);
        `uvm_fatal("WATCHDOG", $sformatf("test did not finish within %0t", watchdog))
      end
    join_any
    disable fork;
    #(drain);
    phase.drop_objection(this);
  endtask

  virtual function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int n_err = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    if (n_err == 0) `uvm_info("RESULT", "** TEST PASSED **", UVM_NONE)
    else            `uvm_info("RESULT", $sformatf("** TEST FAILED ** (%0d errors)", n_err), UVM_NONE)
  endfunction

endclass : dma_base_test
