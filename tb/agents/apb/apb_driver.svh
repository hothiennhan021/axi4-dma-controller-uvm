// -----------------------------------------------------------------------------
// apb_driver - APB3 master driver
//
// SETUP phase : PSEL=1, PENABLE=0, address/control/write data valid
// ACCESS phase: PENABLE=1 until PREADY is sampled high
// The response (PRDATA/PSLVERR) is written back into the request item, which
// is what the register layer's adapter reads (provides_responses = 0).
// -----------------------------------------------------------------------------
class apb_driver extends uvm_driver #(apb_seq_item);

  `uvm_component_utils(apb_driver)

  apb_agent_cfg  cfg;
  virtual apb_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(apb_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "apb_agent_cfg not found")
    vif = cfg.vif;
  endfunction

  virtual task run_phase(uvm_phase phase);
    idle_bus();
    @(posedge vif.clk iff vif.rst_n === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      seq_item_port.item_done();
    end
  endtask

  protected function void idle_bus();
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b0;
    vif.paddr   <= '0;
    vif.pwdata  <= '0;
  endfunction

  protected time t_last_done = -1;

  protected task drive(apb_seq_item t);
    int unsigned idle, waits;
    idle = $urandom_range(cfg.max_idle, cfg.min_idle);
    // A new item in the same time step as the previous ACCESS completed and
    // no idle cycle requested: go straight to SETUP (back-to-back transfer,
    // PSEL stays high).
    if (!(idle == 0 && $time == t_last_done)) begin
      repeat (idle) @(posedge vif.clk);
      @(posedge vif.clk);
    end
    // SETUP
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;
    vif.pwrite  <= t.write;
    vif.paddr   <= t.addr;
    vif.pwdata  <= t.write ? t.data : 32'h0;
    // ACCESS
    @(posedge vif.clk);
    vif.penable <= 1'b1;
    waits = 0;
    forever begin
      @(posedge vif.clk);
      if (vif.pready === 1'b1) break;
      if (++waits > cfg.pready_timeout) begin
        `uvm_error("APB_TIMEOUT", $sformatf("PREADY not seen within %0d cycles: %s",
                                            cfg.pready_timeout, t.convert2string()))
        break;
      end
    end
    if (!t.write) t.data = vif.prdata;
    t.slverr = (vif.pslverr === 1'b1);
    idle_bus();
    t_last_done = $time;
    `uvm_info("APB_DRV", t.convert2string(), UVM_HIGH)
  endtask

endclass : apb_driver
