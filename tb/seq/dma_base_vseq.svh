// -----------------------------------------------------------------------------
// dma_base_vseq - register/driver helpers shared by all virtual sequences
//
// All register traffic goes through the register model (frontdoor, APB).
// The scoreboard independently checks every access, so helpers here only
// check what a test needs to decide its next step, plus the end-to-end memory
// contents (check_copy), which does not depend on any monitor.
// -----------------------------------------------------------------------------
class dma_base_vseq extends uvm_sequence;

  `uvm_object_utils(dma_base_vseq)
  `uvm_declare_p_sequencer(dma_virtual_sequencer)

  dma_reg_block  rm;
  axi_mem        mem;
  axi_slave_cfg  axi_cfg;
  int unsigned   num_ch;
  virtual irq_if irq_vif;

  // default poll timeout in clock cycles
  int unsigned   timeout_cycles = 400000;

  function new(string name = "dma_base_vseq");
    super.new(name);
  endfunction

  virtual task pre_start();
    rm      = p_sequencer.regmodel;
    mem     = p_sequencer.mem;
    axi_cfg = p_sequencer.axi_cfg;
    num_ch  = p_sequencer.cfg.num_ch;
    irq_vif = p_sequencer.irq_vif;
  endtask

  // ---------------------------------------------------------------------------
  // Register access
  // ---------------------------------------------------------------------------
  task wr(uvm_reg rg, uvm_reg_data_t v);
    uvm_status_e status;
    rg.write(status, v, UVM_FRONTDOOR, .parent(this));
    if (status != UVM_IS_OK) `uvm_error("REG_WR", $sformatf("write %s failed", rg.get_full_name()))
  endtask

  task rd(uvm_reg rg, output uvm_reg_data_t v);
    uvm_status_e status;
    rg.read(status, v, UVM_FRONTDOOR, .parent(this));
    if (status != UVM_IS_OK) `uvm_error("REG_RD", $sformatf("read %s failed", rg.get_full_name()))
  endtask

  task wait_cycles(int unsigned n);
    repeat (n) @(posedge irq_vif.clk);
  endtask

  task set_enable(bit en);
    wr(rm.CTRL, en);
  endtask

  task set_int_enable(bit [31:0] mask);
    wr(rm.INT_ENABLE, mask);
  endtask

  task clear_int(bit [31:0] mask);
    wr(rm.INT_STATUS, mask);
  endtask

  function bit [31:0] all_int_mask();
    return ((32'h1 << num_ch) - 1) | (((32'h1 << num_ch) - 1) << 8);
  endfunction

  // ---------------------------------------------------------------------------
  // Transfers
  // ---------------------------------------------------------------------------
  function dma_xfer new_xfer(int unsigned c);
    dma_xfer x = dma_xfer::type_id::create($sformatf("xfer_ch%0d", c));
    x.ch = c;
    return x;
  endfunction

  function dma_xfer rand_xfer(int unsigned c);
    dma_xfer x = new_xfer(c);
    if (!x.randomize() with { len inside {[1:256]}; }) `uvm_fatal("RAND", "dma_xfer randomization failed")
    return x;
  endfunction

  task program_channel(dma_xfer x);
    wr(rm.ch[x.ch].CFG, x.cfg_word());
    wr(rm.ch[x.ch].SRC, x.src);
    wr(rm.ch[x.ch].DST, x.dst);
    wr(rm.ch[x.ch].LEN, x.len);
  endtask

  // Capture the data the transfer is expected to deliver (call right before START)
  function void snapshot(dma_xfer x);
    int unsigned n0;
    x.exp_data.delete();
    x.src_fifo = mem.is_fifo(x.src);
    x.dst_fifo = mem.is_fifo(x.dst);
    n0 = mem.fifo_reads(x.src);
    for (int unsigned i = 0; i < x.len; i++) begin
      if (x.src_fifo && !x.src_inc) x.exp_data.push_back(mem.fifo_value(x.src, n0 + i));
      else                          x.exp_data.push_back(mem.peek(x.src + (x.src_inc ? 32'(i) * 4 : 0)));
    end
    x.sink0    = mem.sink_size(x.dst);
    x.guard_lo = mem.peek(x.dst - 4);
    x.guard_hi = mem.peek(x.dst + (x.dst_inc ? 32'(x.len) * 4 : 32'd4));
  endfunction

  task start_channel(int unsigned c, bit with_abort = 0);
    wr(rm.ch[c].CMD, {with_abort, 1'b1});
  endtask

  task abort_channel(int unsigned c);
    wr(rm.ch[c].CMD, 2'b10);
  endtask

  task read_stat(int unsigned c, output bit [31:0] stat);
    uvm_reg_data_t v;
    rd(rm.ch[c].STAT, v);
    stat = v[31:0];
  endtask

  // Poll CHn_STAT.BUSY until clear
  task wait_channel_idle(int unsigned c, output bit [31:0] stat);
    int unsigned waited = 0;
    forever begin
      read_stat(c, stat);
      if (!stat[0]) return;
      if (waited > timeout_cycles) begin
        `uvm_error("TIMEOUT", $sformatf("ch%0d still busy after %0d cycles, STAT=0x%08h", c, waited, stat))
        return;
      end
      begin
        int unsigned d = $urandom_range(40, 4);
        wait_cycles(d);
        waited += d;
      end
    end
  endtask

  // Poll the global BUSY register until all channels are idle
  task wait_all_idle();
    uvm_reg_data_t v;
    int unsigned   waited = 0;
    forever begin
      rd(rm.BUSY, v);
      if (v == 0) return;
      if (waited > timeout_cycles) begin
        `uvm_error("TIMEOUT", $sformatf("channels still busy after %0d cycles, BUSY=0x%0h", waited, v))
        return;
      end
      wait_cycles(20);
      waited += 20;
    end
  endtask

  // Wait for the irq pin
  task wait_irq(output bit seen, input int unsigned max_cycles = 0);
    int unsigned lim = (max_cycles == 0) ? timeout_cycles : max_cycles;
    seen = 0;
    for (int unsigned i = 0; i < lim; i++) begin
      if (irq_vif.irq === 1'b1) begin
        seen = 1;
        return;
      end
      @(posedge irq_vif.clk);
    end
  endtask

  // ---------------------------------------------------------------------------
  // End-to-end memory check (independent of the monitors)
  //   words = number of words that must have been delivered (default: all)
  // ---------------------------------------------------------------------------
  function void check_copy(dma_xfer x, int words = -1);
    int unsigned n = (words < 0) ? x.len : words;
    int unsigned bad = 0;
    if (n > x.exp_data.size()) n = x.exp_data.size();
    if (x.dst_fifo && !x.dst_inc) begin
      if (mem.sink_size(x.dst) != x.sink0 + n)
        `uvm_error("COPY", $sformatf("%s: FIFO sink got %0d words, expected %0d",
                                     x.convert2string(), mem.sink_size(x.dst) - x.sink0, n))
      for (int unsigned i = 0; i < n && bad < 4; i++) begin
        bit [31:0] got = mem.sink_word(x.dst, x.sink0 + i);
        if (got != x.exp_data[i]) begin
          bad++;
          `uvm_error("COPY", $sformatf("%s: FIFO word %0d = 0x%08h, expected 0x%08h",
                                       x.convert2string(), i, got, x.exp_data[i]))
        end
      end
    end else if (!x.dst_inc) begin
      if (n > 0 && mem.peek(x.dst) != x.exp_data[n - 1])
        `uvm_error("COPY", $sformatf("%s: fixed destination holds 0x%08h, expected last word 0x%08h",
                                     x.convert2string(), mem.peek(x.dst), x.exp_data[n - 1]))
    end else begin
      for (int unsigned i = 0; i < n && bad < 4; i++) begin
        bit [31:0] a   = x.dst + 32'(i) * 4;
        bit [31:0] got = mem.peek(a);
        if (got != x.exp_data[i]) begin
          bad++;
          `uvm_error("COPY", $sformatf("%s: word %0d @0x%08h = 0x%08h, expected 0x%08h",
                                       x.convert2string(), i, a, got, x.exp_data[i]))
        end
      end
      // words past the delivered ones must not have been written by this transfer
      if (n == x.len && mem.peek(x.dst + 32'(x.len) * 4) != x.guard_hi)
        `uvm_error("COPY", $sformatf("%s: word after the destination buffer was overwritten", x.convert2string()))
    end
    if (!x.dst_fifo && mem.peek(x.dst - 4) != x.guard_lo)
      `uvm_error("COPY", $sformatf("%s: word before the destination buffer was overwritten", x.convert2string()))
  endfunction

  // Program, start, wait, check status and data
  task run_xfer(dma_xfer x, bit use_irq = 0);
    bit [31:0] stat;
    bit        seen;
    program_channel(x);
    snapshot(x);
    `uvm_info("VSEQ", {"transfer ", x.convert2string()}, UVM_MEDIUM)
    start_channel(x.ch);
    if (use_irq) begin
      wait_irq(seen);
      if (!seen) `uvm_error("IRQ", $sformatf("no irq for %s", x.convert2string()))
    end
    wait_channel_idle(x.ch, stat);
    if (stat[3:1] != 3'b001 || stat[31:16] != 0)
      `uvm_error("STAT", $sformatf("%s finished with STAT=0x%08h (expected DONE, REMAIN=0)", x.convert2string(), stat))
    check_copy(x);
  endtask

  // After an error or abort: check that exactly LEN-REMAIN words were delivered
  task check_partial(dma_xfer x, bit [31:0] stat);
    int unsigned remain = stat[31:16];
    if (remain > x.len) begin
      `uvm_error("STAT", $sformatf("%s: REMAIN=%0d > LEN", x.convert2string(), remain))
      return;
    end
    check_copy(x, x.len - remain);
  endtask

endclass : dma_base_vseq
