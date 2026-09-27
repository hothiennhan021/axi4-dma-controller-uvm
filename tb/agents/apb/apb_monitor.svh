// -----------------------------------------------------------------------------
// apb_monitor - publishes every completed APB transfer
// A transfer completes at the rising edge where PSEL & PENABLE & PREADY.
// -----------------------------------------------------------------------------
class apb_monitor extends uvm_monitor;

  `uvm_component_utils(apb_monitor)

  uvm_analysis_port #(apb_seq_item) ap;
  apb_agent_cfg  cfg;
  virtual apb_if vif;

  int unsigned n_wr, n_rd, n_err;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(apb_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "apb_agent_cfg not found")
    vif = cfg.vif;
  endfunction

  virtual task run_phase(uvm_phase phase);
    apb_seq_item t;
    int unsigned waits;
    waits = 0;
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) begin
        waits = 0;
        continue;
      end
      if (vif.psel === 1'b1 && vif.penable === 1'b1) begin
        if (vif.pready === 1'b1) begin
          t             = apb_seq_item::type_id::create("apb_mon_item");
          t.addr        = vif.paddr;
          t.write       = vif.pwrite;
          t.data        = vif.pwrite ? vif.pwdata : vif.prdata;
          t.slverr      = (vif.pslverr === 1'b1);
          t.wait_cycles = waits;
          if (t.write) n_wr++; else n_rd++;
          if (t.slverr) n_err++;
          `uvm_info("APB_MON", t.convert2string(), UVM_HIGH)
          ap.write(t);
          waits = 0;
        end else begin
          waits++;
        end
      end
    end
  endtask

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("APB_MON", $sformatf("observed %0d writes, %0d reads, %0d PSLVERR", n_wr, n_rd, n_err),
              UVM_LOW)
  endfunction

endclass : apb_monitor
