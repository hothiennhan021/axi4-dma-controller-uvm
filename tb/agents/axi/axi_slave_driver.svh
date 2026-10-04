// -----------------------------------------------------------------------------
// axi_slave_driver - reactive AXI4 slave backed by axi_mem
//
// Five independent threads, one per AXI channel:
//   AR -> (mailbox) -> R      AW -> (mailbox) -+
//                             W  -> (mailbox) -+-> B (memory updated here)
// READY timing is randomised per handshake (ready-early or delayed), R beats
// get random gaps, B gets a random latency. Read/write error regions from
// axi_slave_cfg turn beats into SLVERR/DECERR responses; a write burst that
// hits an error region is not committed to memory.
//
// There is no sequencer: responses are fully determined by the memory model
// and the configuration object, which tests modify at run time.
// -----------------------------------------------------------------------------
class axi_slave_driver extends uvm_component;

  `uvm_component_utils(axi_slave_driver)

  axi_slave_cfg  cfg;
  axi_mem        mem;
  virtual axi_if vif;

  protected mailbox #(axi_txn) rd_mbx;
  protected mailbox #(axi_txn) aw_mbx;
  protected mailbox #(axi_txn) wb_mbx;   // W beats of one burst (data/strb only)
  int unsigned n_resets;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rd_mbx = new();
    aw_mbx = new();
    wb_mbx = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "axi_slave_cfg not found")
    if (!uvm_config_db#(axi_mem)::get(this, "", "mem", mem))
      `uvm_fatal("NOMEM", "axi_mem not found")
    vif = cfg.vif;
  endfunction

  // The channel threads run until reset is asserted; then every pending
  // request and response is dropped, the outputs go idle and the threads
  // restart after reset is released.
  virtual task run_phase(uvm_phase phase);
    forever begin
      idle_outputs();
      rd_mbx = new();
      aw_mbx = new();
      wb_mbx = new();
      @(posedge vif.clk iff vif.rst_n === 1'b1);
      fork
        begin
          fork
            ar_thread();
            r_thread();
            aw_thread();
            w_thread();
            b_thread();
          join
        end
        begin
          @(negedge vif.rst_n);
        end
      join_any
      disable fork;
      n_resets++;
    end
  endtask

  protected function void idle_outputs();
    vif.arready <= 1'b0;
    vif.awready <= 1'b0;
    vif.wready  <= 1'b0;
    vif.rvalid  <= 1'b0;
    vif.rid     <= '0;
    vif.rdata   <= '0;
    vif.rresp   <= '0;
    vif.rlast   <= 1'b0;
    vif.bvalid  <= 1'b0;
    vif.bid     <= '0;
    vif.bresp   <= '0;
  endfunction

  protected function bit ready_early();
    return ($urandom_range(99, 0) < cfg.pct_ready_early);
  endfunction

  protected function int unsigned pick(int unsigned lo, int unsigned hi);
    if (hi <= lo) return lo;
    return $urandom_range(hi, lo);
  endfunction

  // ---------------------------------------------------------------------------
  // Read address
  // ---------------------------------------------------------------------------
  protected task ar_thread();
    axi_txn t;
    forever begin
      if (ready_early()) begin
        vif.arready <= 1'b1;
        do @(posedge vif.clk); while (vif.arvalid !== 1'b1);
      end else begin
        vif.arready <= 1'b0;
        do @(posedge vif.clk); while (vif.arvalid !== 1'b1);
        repeat (pick(cfg.ar_delay_min, cfg.ar_delay_max)) @(posedge vif.clk);
        vif.arready <= 1'b1;
        @(posedge vif.clk);
      end
      // Handshake at this edge
      t       = axi_txn::type_id::create("rd");
      t.kind  = AXI_READ;
      t.id    = vif.arid;
      t.addr  = vif.araddr;
      t.len   = vif.arlen;
      t.size  = vif.arsize;
      t.burst = vif.arburst;
      rd_mbx.put(t);
      vif.arready <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Read data
  // ---------------------------------------------------------------------------
  protected task r_thread();
    axi_txn t;
    bit [31:0] a;
    bit [1:0]  rsp;
    forever begin
      rd_mbx.get(t);
      for (int unsigned i = 0; i < t.beats(); i++) begin
        int unsigned gap = pick(cfg.r_gap_min, cfg.r_gap_max);
        if (gap > 0) begin
          vif.rvalid <= 1'b0;
          repeat (gap) @(posedge vif.clk);
        end
        a   = t.beat_addr(i);
        rsp = cfg.resp_for(a, 1'b1);
        vif.rvalid <= 1'b1;
        vif.rid    <= t.id;
        vif.rdata  <= (rsp == 2'b00) ? mem.bus_read(a) : 32'hDEAD_BEEF;
        vif.rresp  <= rsp;
        vif.rlast  <= (i == t.beats() - 1);
        do @(posedge vif.clk); while (vif.rready !== 1'b1);
      end
      vif.rvalid <= 1'b0;
      vif.rlast  <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Write address
  // ---------------------------------------------------------------------------
  protected task aw_thread();
    axi_txn t;
    forever begin
      if (ready_early()) begin
        vif.awready <= 1'b1;
        do @(posedge vif.clk); while (vif.awvalid !== 1'b1);
      end else begin
        vif.awready <= 1'b0;
        do @(posedge vif.clk); while (vif.awvalid !== 1'b1);
        repeat (pick(cfg.aw_delay_min, cfg.aw_delay_max)) @(posedge vif.clk);
        vif.awready <= 1'b1;
        @(posedge vif.clk);
      end
      t       = axi_txn::type_id::create("wr");
      t.kind  = AXI_WRITE;
      t.id    = vif.awid;
      t.addr  = vif.awaddr;
      t.len   = vif.awlen;
      t.size  = vif.awsize;
      t.burst = vif.awburst;
      aw_mbx.put(t);
      vif.awready <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Write data
  // ---------------------------------------------------------------------------
  protected task w_thread();
    axi_txn beats;
    beats = axi_txn::type_id::create("wbeats");
    forever begin
      if (ready_early()) begin
        vif.wready <= 1'b1;
        do @(posedge vif.clk); while (vif.wvalid !== 1'b1);
      end else begin
        vif.wready <= 1'b0;
        do @(posedge vif.clk); while (vif.wvalid !== 1'b1);
        repeat (pick(cfg.w_delay_min, cfg.w_delay_max)) @(posedge vif.clk);
        vif.wready <= 1'b1;
        @(posedge vif.clk);
      end
      beats.data.push_back(vif.wdata);
      beats.strb.push_back(vif.wstrb);
      if (vif.wlast === 1'b1) begin
        wb_mbx.put(beats);
        beats = axi_txn::type_id::create("wbeats");
      end
      vif.wready <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Write response (commits the burst to memory)
  // ---------------------------------------------------------------------------
  protected task b_thread();
    axi_txn aw, wb;
    bit [1:0] rsp;
    forever begin
      aw_mbx.get(aw);
      wb_mbx.get(wb);
      if (wb.data.size() != aw.beats())
        `uvm_error("AXI_SLV_WLAST", $sformatf("WLAST after %0d beats but AWLEN=%0d (%0d beats): %s",
                                              wb.data.size(), aw.len, aw.beats(), aw.convert2string()))
      rsp = 2'b00;
      foreach (wb.data[i]) begin
        bit [1:0] r = cfg.resp_for(aw.beat_addr(i), 1'b0);
        if (rsp == 2'b00 && r != 2'b00) rsp = r;
      end
      if (rsp == 2'b00) begin
        foreach (wb.data[i]) mem.bus_write(aw.beat_addr(i), wb.data[i], wb.strb[i]);
      end
      repeat (pick(cfg.b_delay_min, cfg.b_delay_max)) @(posedge vif.clk);
      vif.bvalid <= 1'b1;
      vif.bid    <= aw.id;
      vif.bresp  <= rsp;
      do @(posedge vif.clk); while (vif.bready !== 1'b1);
      vif.bvalid <= 1'b0;
    end
  endtask

endclass : axi_slave_driver
