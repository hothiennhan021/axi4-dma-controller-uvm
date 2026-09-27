// -----------------------------------------------------------------------------
// axi_monitor - passive AXI4 monitor
//
// ap        : completed bursts (READ after the last R beat, WRITE after B)
// ar_req_ap : read address requests, published in the first cycle ARVALID is
//             sampled high (used for arbitration / abort timing checks)
//
// Bus-level checks performed here (the SVA checker covers cycle rules):
//   * R/B beats must belong to an outstanding request with the same ID
//   * RLAST / WLAST must mark exactly the AxLEN+1-th beat
// -----------------------------------------------------------------------------
class axi_monitor extends uvm_monitor;

  `uvm_component_utils(axi_monitor)

  uvm_analysis_port #(axi_txn) ap;
  uvm_analysis_port #(axi_txn) ar_req_ap;

  axi_slave_cfg  cfg;
  virtual axi_if vif;

  protected axi_txn rd_q[$];        // accepted AR, waiting for R beats
  protected axi_txn aw_q[$];        // accepted AW, waiting for B
  protected axi_txn wbursts[$];     // complete W bursts, waiting for B
  protected axi_txn wcur;           // W beats of the burst in progress
  protected bit     ar_pending, aw_pending;
  protected time    ar_t_req, aw_t_req;
  protected int unsigned ar_wait, aw_wait;
  protected bit     wcur_before_aw;

  int unsigned n_rd, n_wr, n_rd_beats, n_wr_beats;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap        = new("ap", this);
    ar_req_ap = new("ar_req_ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi_slave_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "axi_slave_cfg not found")
    vif = cfg.vif;
  endfunction

  virtual task run_phase(uvm_phase phase);
    wcur = null;
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) begin
        rd_q.delete(); aw_q.delete(); wbursts.delete();
        wcur = null; ar_pending = 0; aw_pending = 0;
        continue;
      end
      sample_ar();
      sample_r();
      sample_aw();
      sample_w();
      sample_b();
    end
  endtask

  protected function void sample_ar();
    axi_txn t;
    if (vif.arvalid !== 1'b1) return;
    if (!ar_pending) begin
      ar_pending = 1;
      ar_t_req   = $time;
      ar_wait    = 0;
      t        = axi_txn::type_id::create("ar_req");
      t.kind   = AXI_AR_REQ;
      t.id     = vif.arid;
      t.addr   = vif.araddr;
      t.len    = vif.arlen;
      t.size   = vif.arsize;
      t.burst  = vif.arburst;
      t.t_req  = $time;
      ar_req_ap.write(t);
    end
    if (vif.arready === 1'b1) begin
      t           = axi_txn::type_id::create("rd");
      t.kind      = AXI_READ;
      t.id        = vif.arid;
      t.addr      = vif.araddr;
      t.len       = vif.arlen;
      t.size      = vif.arsize;
      t.burst     = vif.arburst;
      t.t_req     = ar_t_req;
      t.t_addr    = $time;
      t.addr_wait = ar_wait;
      rd_q.push_back(t);
      ar_pending  = 0;
    end else begin
      ar_wait++;
    end
  endfunction

  protected function void sample_r();
    int idx;
    axi_txn t;
    if (!(vif.rvalid === 1'b1 && vif.rready === 1'b1)) return;
    idx = -1;
    foreach (rd_q[i]) if (rd_q[i].id == vif.rid) begin idx = i; break; end
    if (idx < 0) begin
      `uvm_error("AXI_MON_R", $sformatf("R beat with RID=%0d but no outstanding read", vif.rid))
      return;
    end
    t = rd_q[idx];
    t.data.push_back(vif.rdata);
    t.resp.push_back(vif.rresp);
    if (t.data.size() == t.beats() && vif.rlast !== 1'b1)
      `uvm_error("AXI_MON_RLAST", $sformatf("RLAST missing on beat %0d: %s", t.data.size(), t.convert2string()))
    if (vif.rlast === 1'b1) begin
      if (t.data.size() != t.beats())
        `uvm_error("AXI_MON_RLAST", $sformatf("RLAST on beat %0d, expected %0d: %s",
                                              t.data.size(), t.beats(), t.convert2string()))
      t.t_end = $time;
      rd_q.delete(idx);
      n_rd++;
      n_rd_beats += t.data.size();
      `uvm_info("AXI_MON", t.convert2string(), UVM_HIGH)
      ap.write(t);
    end
  endfunction

  protected function void sample_aw();
    axi_txn t;
    if (vif.awvalid !== 1'b1) return;
    if (!aw_pending) begin
      aw_pending = 1;
      aw_t_req   = $time;
      aw_wait    = 0;
    end
    if (vif.awready === 1'b1) begin
      t           = axi_txn::type_id::create("wr");
      t.kind      = AXI_WRITE;
      t.id        = vif.awid;
      t.addr      = vif.awaddr;
      t.len       = vif.awlen;
      t.size      = vif.awsize;
      t.burst     = vif.awburst;
      t.t_req     = aw_t_req;
      t.t_addr    = $time;
      t.addr_wait = aw_wait;
      aw_q.push_back(t);
      aw_pending  = 0;
    end else begin
      aw_wait++;
    end
  endfunction

  protected function void sample_w();
    if (!(vif.wvalid === 1'b1 && vif.wready === 1'b1)) return;
    if (wcur == null) begin
      wcur = axi_txn::type_id::create("wbeats");
      // AW of this burst not accepted yet (sample_aw ran first this edge)
      wcur_before_aw = (aw_q.size() <= wbursts.size());
    end
    wcur.data.push_back(vif.wdata);
    wcur.strb.push_back(vif.wstrb);
    if (vif.wlast === 1'b1) begin
      wcur.w_before_aw = wcur_before_aw;
      wbursts.push_back(wcur);
      wcur = null;
    end
  endfunction

  protected function void sample_b();
    axi_txn t, wb;
    if (!(vif.bvalid === 1'b1 && vif.bready === 1'b1)) return;
    if (aw_q.size() == 0 || wbursts.size() == 0) begin
      `uvm_error("AXI_MON_B", $sformatf("B response (BID=%0d) without a complete AW+W burst", vif.bid))
      return;
    end
    t  = aw_q.pop_front();
    wb = wbursts.pop_front();
    if (vif.bid != t.id)
      `uvm_error("AXI_MON_BID", $sformatf("BID=%0d does not match AWID=%0d", vif.bid, t.id))
    if (wb.data.size() != t.beats())
      `uvm_error("AXI_MON_WLAST", $sformatf("WLAST after %0d beats, expected %0d: %s",
                                            wb.data.size(), t.beats(), t.convert2string()))
    t.data        = wb.data;
    t.strb        = wb.strb;
    t.w_before_aw = wb.w_before_aw;
    t.resp.push_back(vif.bresp);
    t.t_end = $time;
    n_wr++;
    n_wr_beats += t.data.size();
    `uvm_info("AXI_MON", t.convert2string(), UVM_HIGH)
    ap.write(t);
  endfunction

  virtual function void check_phase(uvm_phase phase);
    if (rd_q.size() != 0)    `uvm_error("AXI_MON_EOT", $sformatf("%0d read burst(s) outstanding at end of test", rd_q.size()))
    if (aw_q.size() != 0)    `uvm_error("AXI_MON_EOT", $sformatf("%0d write burst(s) without B at end of test", aw_q.size()))
    if (wbursts.size() != 0) `uvm_error("AXI_MON_EOT", $sformatf("%0d W burst(s) without B at end of test", wbursts.size()))
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("AXI_MON", $sformatf("observed %0d read bursts (%0d beats), %0d write bursts (%0d beats)",
                                   n_rd, n_rd_beats, n_wr, n_wr_beats), UVM_LOW)
  endfunction

endclass : axi_monitor
