// -----------------------------------------------------------------------------
// dma_vseq_lib - virtual sequences (one per test scenario)
// -----------------------------------------------------------------------------

// Built-in UVM register tests ---------------------------------------------------
class dma_reg_hw_reset_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_reg_hw_reset_vseq)
  function new(string name = "dma_reg_hw_reset_vseq");
    super.new(name);
  endfunction
  virtual task body();
    uvm_reg_hw_reset_seq seq = uvm_reg_hw_reset_seq::type_id::create("hw_reset_seq");
    seq.model = rm;
    seq.start(null, this);
  endtask
endclass

class dma_reg_bit_bash_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_reg_bit_bash_vseq)
  function new(string name = "dma_reg_bit_bash_vseq");
    super.new(name);
  endfunction
  virtual task body();
    uvm_reg_bit_bash_seq bb = uvm_reg_bit_bash_seq::type_id::create("bit_bash_seq");
    uvm_reg_hw_reset_seq rs = uvm_reg_hw_reset_seq::type_id::create("hw_reset_seq");
    bb.model = rm;
    bb.start(null, this);
    // Bit-bash leaves registers at arbitrary values; walk them back to reset
    // through the front door and check the mirror again.
    rm.reset();
    wr(rm.CTRL, 0);
    wr(rm.INT_ENABLE, 0);
    foreach (rm.ch[c]) begin
      wr(rm.ch[c].CFG, 6'h3F);
      wr(rm.ch[c].SRC, 0);
      wr(rm.ch[c].DST, 0);
      wr(rm.ch[c].LEN, 0);
    end
    rs.model = rm;
    rs.start(null, this);
  endtask
endclass

// Smoke ------------------------------------------------------------------------
class dma_smoke_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_smoke_vseq)
  function new(string name = "dma_smoke_vseq");
    super.new(name);
  endfunction
  virtual task body();
    dma_xfer       x;
    uvm_reg_data_t v;
    bit            seen;
    set_enable(1);
    set_int_enable(all_int_mask());
    x = new_xfer(0);
    if (!x.randomize() with { len == 64; max_burst == 15; src_inc == 1; dst_inc == 1; edge_4k == 0; })
      `uvm_fatal("RAND", "randomization failed")
    run_xfer(x, 1);
    rd(rm.INT_STATUS, v);
    if (v != 32'h1) `uvm_error("SMOKE", $sformatf("INT_STATUS=0x%0h, expected 0x1", v))
    clear_int(32'h1);
    wait_cycles(2);
    if (irq_vif.irq !== 1'b0) `uvm_error("SMOKE", "irq still high after W1C")
    rd(rm.INT_STATUS, v);
    if (v != 0) `uvm_error("SMOKE", $sformatf("INT_STATUS=0x%0h after clear", v))
  endtask
endclass

// Sequential random transfers on random channels ----------------------------------
class dma_single_ch_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_single_ch_vseq)
  int unsigned n_xfers = 24;
  function new(string name = "dma_single_ch_vseq");
    super.new(name);
  endfunction
  virtual task body();
    set_enable(1);
    set_int_enable(all_int_mask());
    repeat (n_xfers) begin
      dma_xfer x = new_xfer($urandom_range(num_ch - 1, 0));
      if (!x.randomize() with { len inside {[1:400]}; }) `uvm_fatal("RAND", "randomization failed")
      run_xfer(x, $urandom_range(1, 0));
      clear_int(all_int_mask());
    end
  endtask
endclass

// All channels concurrently -------------------------------------------------------
class dma_multi_ch_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_multi_ch_vseq)
  int unsigned n_rounds = 6;
  int unsigned max_len  = 300;
  function new(string name = "dma_multi_ch_vseq");
    super.new(name);
  endfunction
  virtual task body();
    set_enable(1);
    set_int_enable(all_int_mask());
    repeat (n_rounds) begin
      dma_xfer   x[];
      bit [31:0] stat;
      int        order[$];
      x = new[num_ch];
      foreach (x[c]) begin
        x[c] = new_xfer(c);
        if (!x[c].randomize() with { len inside {[1:max_len]}; })
          `uvm_fatal("RAND", "randomization failed")
        program_channel(x[c]);
        snapshot(x[c]);
        order.push_back(c);
      end
      order.shuffle();
      foreach (order[i]) begin
        start_channel(order[i]);
        wait_cycles($urandom_range(20, 0));
      end
      foreach (x[c]) begin
        wait_channel_idle(c, stat);
        if (stat[3:1] != 3'b001) `uvm_error("STAT", $sformatf("%s STAT=0x%08h", x[c].convert2string(), stat))
        check_copy(x[c]);
      end
      clear_int(all_int_mask());
    end
  endtask
endclass

// 4 KB boundary splitting -------------------------------------------------------------
class dma_4k_boundary_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_4k_boundary_vseq)
  function new(string name = "dma_4k_boundary_vseq");
    super.new(name);
  endfunction
  virtual task body();
    set_enable(1);
    repeat (30) begin
      dma_xfer x = new_xfer($urandom_range(num_ch - 1, 0));
      if (!x.randomize() with {
            len inside {[1:96]};
            src_inc == 1; dst_inc == 1;
            src[11:0] inside {[12'hF80:12'hFFC]};
            dst[11:0] dist {[12'hF80:12'hFFC] :/ 3, [12'h000:12'hF7C] :/ 1};
          }) `uvm_fatal("RAND", "randomization failed")
      run_xfer(x);
    end
    // Source and destination at different distances from their boundaries
    // with full-length bursts: every burst is cut by whichever comes first.
    for (int unsigned k = 0; k < 8; k++) begin
      dma_xfer x = new_xfer(k % num_ch);
      if (!x.randomize() with {
            len == 200; max_burst == 15; src_inc == 1; dst_inc == 1;
            src[11:0] == 12'hFFC - 12'(4 * k);
            dst[11:0] == 12'hFC0 + 12'(4 * k);
          }) `uvm_fatal("RAND", "randomization failed")
      run_xfer(x);
    end
  endtask
endclass

// FIXED bursts / peripheral FIFOs ------------------------------------------------------
class dma_fixed_addr_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_fixed_addr_vseq)
  function new(string name = "dma_fixed_addr_vseq");
    super.new(name);
  endfunction
  virtual task body();
    set_enable(1);
    for (int unsigned c = 0; c < num_ch; c++)
      mem.add_fifo_window(dma_xfer::fifo_base(c), dma_xfer::fifo_base(c) + 32'hFF);
    repeat (6) begin
      for (int unsigned mode = 0; mode < 4; mode++) begin
        dma_xfer x = new_xfer($urandom_range(num_ch - 1, 0));
        bit [31:0] port = dma_xfer::fifo_base(x.ch) + 32'(4 * $urandom_range(15, 0));
        // FIFO ports live outside the channel memory windows
        x.c_edge_addr.constraint_mode(0);
        if (mode == 0 || mode == 2) x.c_src_win.constraint_mode(0);
        if (mode == 1 || mode == 2) x.c_dst_win.constraint_mode(0);
        case (mode)
          // peripheral FIFO -> memory
          0: if (!x.randomize() with { src == port; src_inc == 0; dst_inc == 1; len inside {[1:120]}; })
               `uvm_fatal("RAND", "randomization failed")
          // memory -> peripheral FIFO
          1: if (!x.randomize() with { dst == port; src_inc == 1; dst_inc == 0; len inside {[1:120]}; })
               `uvm_fatal("RAND", "randomization failed")
          // FIFO -> FIFO
          2: if (!x.randomize() with { src == port; dst == port + 32'h80; src_inc == 0; dst_inc == 0;
                                       len inside {[1:60]}; })
               `uvm_fatal("RAND", "randomization failed")
          // fixed plain-memory source (same word repeated) -> memory
          default: if (!x.randomize() with { src_inc == 0; dst_inc == 1; len inside {[1:60]}; })
               `uvm_fatal("RAND", "randomization failed")
        endcase
        run_xfer(x);
      end
    end
  endtask
endclass

// Error responses ---------------------------------------------------------------------------
class dma_error_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_error_vseq)
  function new(string name = "dma_error_vseq");
    super.new(name);
  endfunction

  // Run x with an error region placed k words into the source or destination
  task run_err_xfer(dma_xfer x, bit on_write, bit [1:0] resp);
    bit [31:0] stat, a;
    uvm_reg_data_t v;
    int unsigned k = $urandom_range(x.len - 1, 0);
    a = on_write ? x.dst + 32'(k) * 4 : x.src + 32'(k) * 4;
    void'(axi_cfg.add_err_region(a, a + 3, resp, !on_write, on_write));
    program_channel(x);
    snapshot(x);
    start_channel(x.ch);
    wait_channel_idle(x.ch, stat);
    axi_cfg.clear_err_regions();
    if (stat[3:1] != 3'b010 || stat[5:4] != resp || stat[6] != on_write)
      `uvm_error("ERR", $sformatf("%s error@word %0d (%s resp=%0d): STAT=0x%08h",
                                  x.convert2string(), k, on_write ? "write" : "read", resp, stat))
    rd(rm.INT_STATUS, v);
    if (!v[8 + x.ch]) `uvm_error("ERR", $sformatf("INT_STATUS.ERR[%0d] not set (0x%0h)", x.ch, v))
    if (v[x.ch])      `uvm_error("ERR", $sformatf("INT_STATUS.DONE[%0d] set on error (0x%0h)", x.ch, v))
    check_partial(x, stat);
    clear_int(all_int_mask());
  endtask

  virtual task body();
    set_enable(1);
    set_int_enable(all_int_mask());
    repeat (16) begin
      dma_xfer x = new_xfer($urandom_range(num_ch - 1, 0));
      if (!x.randomize() with { len inside {[2:200]}; }) `uvm_fatal("RAND", "randomization failed")
      run_err_xfer(x, $urandom_range(1, 0), $urandom_range(1, 0) ? 2'b10 : 2'b11);
    end
    // One channel fails while the others keep running
    begin
      dma_xfer   x[];
      bit [31:0] stat;
      int unsigned bad = $urandom_range(num_ch - 1, 0);
      x = new[num_ch];
      foreach (x[c]) begin
        x[c] = new_xfer(c);
        if (!x[c].randomize() with { len inside {[64:200]}; }) `uvm_fatal("RAND", "randomization failed")
        program_channel(x[c]);
        snapshot(x[c]);
      end
      void'(axi_cfg.add_err_region(x[bad].src + 32'h40, x[bad].src + 32'h43, 2'b10, 1, 0));
      foreach (x[c]) start_channel(c);
      foreach (x[c]) begin
        wait_channel_idle(c, stat);
        if (c == bad) begin
          if (!stat[2]) `uvm_error("ERR", $sformatf("ch%0d expected ERR, STAT=0x%08h", c, stat))
          check_partial(x[c], stat);
        end else begin
          if (stat[3:1] != 3'b001) `uvm_error("ERR", $sformatf("ch%0d disturbed by ch%0d error, STAT=0x%08h", c, bad, stat))
          check_copy(x[c]);
        end
      end
      axi_cfg.clear_err_regions();
      clear_int(all_int_mask());
    end
    // A channel that failed can be restarted
    begin
      dma_xfer x = rand_xfer(0);
      run_xfer(x);
    end
  endtask
endclass

// Abort -----------------------------------------------------------------------------------------
class dma_abort_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_abort_vseq)
  function new(string name = "dma_abort_vseq");
    super.new(name);
  endfunction

  task abort_case(int unsigned c, int unsigned delay, bit paused);
    dma_xfer   x = new_xfer(c);
    bit [31:0] stat;
    if (!x.randomize() with { len inside {[300:1500]}; }) `uvm_fatal("RAND", "randomization failed")
    if (paused) set_enable(0);
    program_channel(x);
    snapshot(x);
    start_channel(c);
    wait_cycles(delay);
    abort_channel(c);
    if (paused) begin
      wait_cycles(5);
      set_enable(1);
    end
    wait_channel_idle(c, stat);
    if (stat[3] == stat[1] || stat[2])
      `uvm_error("ABORT", $sformatf("%s aborted after %0d cycles: STAT=0x%08h", x.convert2string(), delay, stat))
    if (stat[3] && stat[31:16] == 0)
      `uvm_error("ABORT", $sformatf("ABORTED with REMAIN=0: STAT=0x%08h", stat))
    check_partial(x, stat);
    // the channel is usable again
    x = rand_xfer(c);
    x.len = 16'($urandom_range(40, 1));
    run_xfer(x);
  endtask

  virtual task body();
    bit [31:0] stat;
    set_enable(1);
    repeat (12) abort_case($urandom_range(num_ch - 1, 0), $urandom_range(600, 0), 0);
    repeat (3)  abort_case($urandom_range(num_ch - 1, 0), $urandom_range(10, 0), 1);
    // ABORT while a (slow) burst is in flight and CTRL.EN has just been
    // cleared: the burst drains, then the channel reports ABORTED
    repeat (3) begin
      dma_xfer x = new_xfer(0);
      if (!x.randomize() with { len inside {[100:300]}; max_burst == 15; }) `uvm_fatal("RAND", "randomization failed")
      axi_cfg.set_delays(8, 16, 0);
      program_channel(x);
      snapshot(x);
      start_channel(0);
      wait_cycles($urandom_range(60, 10));
      set_enable(0);
      abort_channel(0);
      set_enable(1);
      wait_channel_idle(0, stat);
      axi_cfg.set_delays(0, 3, 30);
      if (!stat[3] && !stat[1]) `uvm_error("ABORT", $sformatf("abort while paused: STAT=0x%08h", stat))
      check_partial(x, stat);
    end
    // START and ABORT in the same write: nothing is transferred
    begin
      dma_xfer x = rand_xfer(1);
      program_channel(x);
      snapshot(x);
      start_channel(1, 1);
      wait_channel_idle(1, stat);
      if (stat[3:1] != 3'b100 || stat[31:16] != x.len)
        `uvm_error("ABORT", $sformatf("START+ABORT: STAT=0x%08h (len=%0d)", stat, x.len))
    end
    // ABORT on an idle channel is ignored
    abort_channel(num_ch - 1);
    read_stat(num_ch - 1, stat);
  endtask
endclass

// Global enable -----------------------------------------------------------------------------------
class dma_pause_resume_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_pause_resume_vseq)
  function new(string name = "dma_pause_resume_vseq");
    super.new(name);
  endfunction
  virtual task body();
    dma_xfer       x[];
    bit [31:0]     stat, s1, s2;
    uvm_reg_data_t v;
    set_enable(0);
    x = new[num_ch];
    foreach (x[c]) begin
      x[c] = new_xfer(c);
      if (!x[c].randomize() with { len inside {[200:600]}; }) `uvm_fatal("RAND", "randomization failed")
      program_channel(x[c]);
      snapshot(x[c]);
      start_channel(c);
    end
    wait_cycles(200);
    rd(rm.BUSY, v);
    if (v != (1 << num_ch) - 1) `uvm_error("PAUSE", $sformatf("BUSY=0x%0h while disabled", v))
    foreach (x[c]) begin
      read_stat(c, stat);
      if (stat[31:16] != x[c].len) `uvm_error("PAUSE", $sformatf("ch%0d moved data while disabled", c))
    end
    // run / freeze / run
    repeat (4) begin
      set_enable(1);
      wait_cycles($urandom_range(300, 50));
      set_enable(0);
      wait_cycles(300);              // the burst in flight drains
      read_stat(0, s1);
      wait_cycles(150);
      read_stat(0, s2);
      if (s1 != s2) `uvm_error("PAUSE", $sformatf("ch0 progressed while disabled: 0x%08h -> 0x%08h", s1, s2))
    end
    set_enable(1);
    foreach (x[c]) begin
      wait_channel_idle(c, stat);
      if (stat[3:1] != 3'b001) `uvm_error("PAUSE", $sformatf("ch%0d STAT=0x%08h", c, stat))
      check_copy(x[c]);
    end
  endtask
endclass

// Interrupts ----------------------------------------------------------------------------------------
class dma_irq_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_irq_vseq)
  function new(string name = "dma_irq_vseq");
    super.new(name);
  endfunction

  task one(int unsigned c, bit fail, bit [31:0] ie);
    dma_xfer       x = new_xfer(c);
    bit [31:0]     stat;
    uvm_reg_data_t v;
    bit            exp_irq;
    if (!x.randomize() with { len inside {[4:40]}; }) `uvm_fatal("RAND", "randomization failed")
    set_int_enable(ie);
    if (fail) void'(axi_cfg.add_err_region(x.src, x.src + 3, 2'b10, 1, 0));
    program_channel(x);
    snapshot(x);
    start_channel(c);
    wait_channel_idle(c, stat);
    axi_cfg.clear_err_regions();
    wait_cycles(1);
    exp_irq = fail ? ie[8 + c] : ie[c];
    if (irq_vif.irq !== exp_irq)
      `uvm_error("IRQ", $sformatf("ch%0d %s, INT_ENABLE=0x%0h: irq=%b expected %b", c, fail ? "error" : "done",
                                  ie, irq_vif.irq, exp_irq))
    // writing zeros clears nothing, writing the wrong bit clears nothing
    clear_int(0);
    clear_int(fail ? (32'h1 << c) : (32'h1 << (8 + c)));
    rd(rm.INT_STATUS, v);
    if (v != (fail ? (32'h1 << (8 + c)) : (32'h1 << c)))
      `uvm_error("IRQ", $sformatf("INT_STATUS=0x%0h before clear", v))
    clear_int(v);
    wait_cycles(1);
    if (irq_vif.irq !== 1'b0) `uvm_error("IRQ", "irq still high after W1C")
  endtask

  virtual task body();
    set_enable(1);
    for (int unsigned c = 0; c < num_ch; c++) begin
      one(c, 0, 0);                                  // masked
      one(c, 0, 32'h1 << c);                         // own DONE
      one(c, 0, all_int_mask() & ~(32'h1 << c));      // everything but own DONE
      one(c, 1, 32'h1 << (8 + c));                   // own ERR
      one(c, 1, 32'h1 << c);                         // DONE only -> error masked
      one(c, 1, all_int_mask());
    end
    // several sources pending, cleared one at a time
    begin
      dma_xfer   x[];
      bit [31:0] stat;
      uvm_reg_data_t v;
      set_int_enable(all_int_mask());
      x = new[num_ch];
      foreach (x[c]) begin
        x[c] = new_xfer(c);
        if (!x[c].randomize() with { len inside {[8:64]}; }) `uvm_fatal("RAND", "randomization failed")
        program_channel(x[c]);
        start_channel(c);
      end
      wait_all_idle();
      for (int unsigned c = 0; c < num_ch; c++) begin
        rd(rm.INT_STATUS, v);
        if (irq_vif.irq !== 1'b1) `uvm_error("IRQ", "irq low with pending sources")
        clear_int(32'h1 << c);
      end
      wait_cycles(1);
      if (irq_vif.irq !== 1'b0) `uvm_error("IRQ", "irq high after clearing all sources")
    end
    // W1C hammering while channels complete: a clear in the same cycle as a
    // hardware set must not lose the new interrupt (checked every cycle by the
    // scoreboard's irq model)
    begin
      bit stop = 0;
      set_int_enable(all_int_mask());
      fork
        begin
          while (!stop) clear_int(all_int_mask());
        end
        begin
          repeat (6) begin
            for (int unsigned c = 0; c < num_ch; c++) begin
              dma_xfer x = new_xfer(c);
              if (!x.randomize() with { len inside {[1:24]}; }) `uvm_fatal("RAND", "randomization failed")
              program_channel(x);
              start_channel(c);
            end
            wait_all_idle();
          end
          stop = 1;
        end
      join
      clear_int(all_int_mask());
    end
  endtask
endclass

// Heavy AXI back-pressure ------------------------------------------------------------------------------
class dma_backpressure_vseq extends dma_multi_ch_vseq;
  `uvm_object_utils(dma_backpressure_vseq)
  function new(string name = "dma_backpressure_vseq");
    super.new(name);
  endfunction
  virtual task body();
    axi_cfg.set_delays(0, 12, 10);
    n_rounds = 3;
    super.body();
    axi_cfg.set_delays(0, 0, 100);    // always ready: back-to-back beats
    n_rounds = 3;
    super.body();
    axi_cfg.set_delays(3, 20, 0);     // always late
    n_rounds = 2;
    max_len  = 100;
    super.body();
  endtask
endclass

// Corner cases ----------------------------------------------------------------------------------------------
class dma_corner_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_corner_vseq)
  function new(string name = "dma_corner_vseq");
    super.new(name);
  endfunction
  virtual task body();
    dma_xfer       x, y;
    bit [31:0]     stat;
    uvm_reg_data_t v;
    bit            seen;
    set_enable(1);
    set_int_enable(all_int_mask());

    // LEN = 0: DONE immediately, no bus traffic
    x = new_xfer(1);
    if (!x.randomize() with { len == 0; }) `uvm_fatal("RAND", "randomization failed")
    program_channel(x);
    start_channel(1);
    read_stat(1, stat);
    if (stat[3:0] != 4'b0010) `uvm_error("CORNER", $sformatf("LEN=0: STAT=0x%08h", stat))
    wait_irq(seen, 5);
    if (!seen) `uvm_error("CORNER", "LEN=0: no irq")
    clear_int(all_int_mask());

    // single word, single-beat bursts, every MAX_BURST value
    x = new_xfer(num_ch - 1);
    if (!x.randomize() with { len == 1; }) `uvm_fatal("RAND", "randomization failed")
    run_xfer(x);
    for (int unsigned mb = 0; mb < 16; mb++) begin
      x = new_xfer(mb % num_ch);
      if (!x.randomize() with { max_burst == 4'(mb); len inside {[1:50]}; edge_4k == 0; })
        `uvm_fatal("RAND", "randomization failed")
      run_xfer(x);
    end

    // every LEN class against every MAX_BURST class
    begin
      int unsigned lens[5];
      int unsigned mbs[5];
      lens = '{0, 16, 0, 0, 1024};
      mbs  = '{0, 0, 7, 0, 15};
      for (int unsigned li = 0; li < 5; li++) begin
        for (int unsigned mi = 0; mi < 5; mi++) begin
          int unsigned l, m;
          case (li)
            0: l = $urandom_range(15, 2);
            2: l = $urandom_range(64, 17);
            3: l = $urandom_range(300, 65);
            default: l = lens[li];
          endcase
          case (mi)
            1: m = $urandom_range(6, 1);
            3: m = $urandom_range(14, 8);
            default: m = mbs[mi];
          endcase
          x = new_xfer((li + mi) % num_ch);
          if (!x.randomize() with { len == 16'(l); max_burst == 4'(m); }) `uvm_fatal("RAND", "randomization failed")
          run_xfer(x);
        end
      end
      clear_int(all_int_mask());
    end

    // START while busy is ignored; reprogramming while busy does not disturb the
    // running transfer, and the new values read back
    x = new_xfer(0);
    if (!x.randomize() with { len == 700; max_burst == 3; }) `uvm_fatal("RAND", "randomization failed")
    program_channel(x);
    snapshot(x);
    start_channel(0);
    wait_cycles(50);
    y = new_xfer(0);
    if (!y.randomize() with { len == 5; }) `uvm_fatal("RAND", "randomization failed")
    program_channel(y);
    start_channel(0);                                   // ignored
    rd(rm.ch[0].SRC, v);
    if (v != y.src) `uvm_error("CORNER", "SRC readback after reprogramming")
    wait_channel_idle(0, stat);
    if (stat[3:1] != 3'b001) `uvm_error("CORNER", $sformatf("reprogram-while-busy: STAT=0x%08h", stat))
    check_copy(x);
    // the new programming is used by the next START
    snapshot(y);
    start_channel(0);
    wait_channel_idle(0, stat);
    check_copy(y);

    // START while busy but with no burst in flight (paused, and while other
    // channels own the engine) is ignored as well
    for (int unsigned k = 0; k < 2; k++) begin
      dma_xfer z[];
      z = new[num_ch];
      if (k == 0) set_enable(0);
      foreach (z[c]) begin
        z[c] = new_xfer(c);
        if (!z[c].randomize() with { len inside {[150:300]}; }) `uvm_fatal("RAND", "randomization failed")
        program_channel(z[c]);
        snapshot(z[c]);
        start_channel(c);
      end
      wait_cycles(30);
      foreach (z[c]) begin
        y = new_xfer(c);
        if (!y.randomize() with { len inside {[1:8]}; }) `uvm_fatal("RAND", "randomization failed")
        program_channel(y);
        start_channel(c);                               // ignored
      end
      if (k == 0) set_enable(1);
      foreach (z[c]) begin
        wait_channel_idle(c, stat);
        if (stat[3:1] != 3'b001 || stat[31:16] != 0)
          `uvm_error("CORNER", $sformatf("START while busy disturbed ch%0d: STAT=0x%08h", c, stat))
        check_copy(z[c]);
      end
    end
    clear_int(all_int_mask());

    // 32-bit address wrap: source ends at 0xFFFF_FFFC and continues at 0x0
    x = new_xfer(num_ch - 1);
    x.src_inc   = 1;
    x.dst_inc   = 1;
    x.max_burst = 15;
    x.src       = 32'hFFFF_FFF0;
    x.dst       = dma_xfer::dst_base(num_ch - 1) + 32'h100;
    x.len       = 12;
    run_xfer(x);

    // maximum LEN (65535 words = 4096 bursts, REMAIN counts through every bit)
    x = new_xfer(1);
    if (!x.randomize() with { len == 16'hFFFF; max_burst == 15; edge_4k == 0; }) `uvm_fatal("RAND", "randomization failed")
    axi_cfg.set_delays(0, 0, 100);
    run_xfer(x, 1);
    axi_cfg.set_delays(0, 3, 30);
    clear_int(all_int_mask());
  endtask
endclass

// APB error handling ----------------------------------------------------------------------------------------------
class dma_apb_err_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_apb_err_vseq)
  function new(string name = "dma_apb_err_vseq");
    super.new(name);
  endfunction
  virtual task body();
    uvm_reg_data_t v;
    // program something recognisable first
    wr(rm.ch[0].SRC, 32'h1234_5678);
    wr(rm.CTRL, 1);
    repeat (120) begin
      apb_rw_seq s = apb_rw_seq::type_id::create("s");
      int unsigned kind = $urandom_range(4, 0);
      s.aligned = 1;
      case (kind)
        0: s.addr = 12'h014 + 12'(4 * $urandom_range(58, 0));             // global hole 0x014-0x0FC
        1: if (num_ch < 8) s.addr = 12'h100 + 12'(num_ch * 32) + 12'($urandom_range((8 - num_ch) * 8 - 1, 0) * 4); // absent channels
           else            s.addr = 12'h200 + 12'(4 * $urandom_range(895, 0));
        2: s.addr = 12'h200 + 12'(4 * $urandom_range(895, 0));            // 0x200-0xFFC
        3: s.addr = 12'h100 + 12'(32 * $urandom_range(num_ch - 1, 0)) + 12'h18 + 12'(4 * $urandom_range(1, 0)); // channel holes
        default: begin                                                    // misaligned
          s.aligned = 0;
          s.addr = 12'($urandom_range(4095, 0)) | 12'($urandom_range(3, 1));
        end
      endcase
      s.write = $urandom_range(1, 0);
      s.data  = $urandom();
      s.start(p_sequencer.apb_sqr, this);
      if (!s.slverr) `uvm_error("APB_ERR", $sformatf("no PSLVERR for 0x%03h", s.addr))
      if (!s.write && s.rdata != 0) `uvm_error("APB_ERR", $sformatf("read 0x%03h returned 0x%08h", s.addr, s.rdata))
      if ($urandom_range(3, 0) == 0) begin
        // interleave legal accesses
        rd(rm.ch[$urandom_range(num_ch - 1, 0)].CFG, v);
        rd(rm.ID, v);
      end
    end
    // CMD is write-only: a read is legal and returns 0 (raw APB access, the
    // register model does not read write-only registers)
    for (int unsigned c = 0; c < num_ch; c++) begin
      apb_rw_seq s = apb_rw_seq::type_id::create("s_cmd");
      s.addr  = 12'h110 + 12'(32 * c);
      s.write = 0;
      s.data  = 0;
      s.start(p_sequencer.apb_sqr, this);
      if (s.slverr || s.rdata != 0) `uvm_error("APB_ERR", $sformatf("CH%0d_CMD read: slverr=%0b data=0x%08h", c, s.slverr, s.rdata))
    end
    rd(rm.ch[0].SRC, v);
    if (v != 32'h1234_5678) `uvm_error("APB_ERR", "SRC changed by an unmapped write")
    rd(rm.CTRL, v);
    if (v != 1) `uvm_error("APB_ERR", "CTRL changed by an unmapped write")
    // a transfer still works afterwards
    begin
      dma_xfer x = rand_xfer(0);
      run_xfer(x);
    end
  endtask
endclass

// Everything at once -------------------------------------------------------------------------------------------------
class dma_stress_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_stress_vseq)
  int unsigned n_per_ch = 10;
  protected bit stop_bg;
  protected int unsigned busy_threads;
  function new(string name = "dma_stress_vseq");
    super.new(name);
  endfunction

  task channel_thread(int unsigned c);
    for (int unsigned n = 0; n < n_per_ch; n++) begin
      dma_xfer       x = new_xfer(c);
      bit [31:0]     stat;
      axi_err_region reg_h;
      int unsigned   what = $urandom_range(9, 0);
      reg_h = null;
      x.c_inc.constraint_mode(0);
      if (!x.randomize() with {
            len dist {[1:16] :/ 2, [17:200] :/ 5, [201:900] :/ 2, 0 := 1};
            src_inc dist {1 := 8, 0 := 2};
            dst_inc dist {1 := 8, 0 := 2};
          }) `uvm_fatal("RAND", "randomization failed")
      if (what == 0 && x.len > 1) begin
        bit [31:0] a = x.src + 32'(4 * $urandom_range(x.len - 1, 0));
        if (!x.src_inc) a = x.src;
        reg_h = axi_cfg.add_err_region(a, a + 3, $urandom_range(1, 0) ? 2'b10 : 2'b11, 1, 0);
      end
      program_channel(x);
      snapshot(x);
      start_channel(c);
      if (what == 1) begin
        wait_cycles($urandom_range(400, 0));
        abort_channel(c);
      end else if (what == 2) begin
        wait_cycles($urandom_range(100, 0));
        start_channel(c);                   // START while (probably) busy: ignored
      end
      wait_channel_idle(c, stat);
      if (stat[1]) check_copy(x);
      else         check_partial(x, stat);
      if (reg_h != null) axi_cfg.remove_err_region(reg_h);
      wait_cycles($urandom_range(50, 0));
    end
  endtask

  task bg_thread();
    while (!stop_bg) begin
      int unsigned k = $urandom_range(9, 0);
      wait_cycles($urandom_range(300, 20));
      if (stop_bg) break;
      case (k)
        0, 1: begin
          set_enable(0);
          wait_cycles($urandom_range(100, 1));
          set_enable(1);
        end
        2, 3, 4: clear_int($urandom());
        5: set_int_enable($urandom() & all_int_mask());
        default: begin
          uvm_reg_data_t v;
          rd(rm.BUSY, v);
          rd(rm.INT_STATUS, v);
        end
      endcase
    end
    set_enable(1);
  endtask

  virtual task body();
    set_enable(1);
    set_int_enable(all_int_mask());
    axi_cfg.set_delays(0, 4, 40);
    stop_bg = 0;
    fork
      bg_thread();
      begin
        for (int unsigned c = 0; c < num_ch; c++) begin
          automatic int unsigned cc = c;
          fork
            channel_thread(cc);
          join_none
        end
        wait fork;
        stop_bg = 1;
      end
    join
    clear_int(all_int_mask());
  endtask
endclass

// Reset in the middle of operation ---------------------------------------------------------------------
class dma_reset_vseq extends dma_base_vseq;
  `uvm_object_utils(dma_reset_vseq)
  int unsigned n_iter = 12;
  function new(string name = "dma_reset_vseq");
    super.new(name);
  endfunction

  virtual task body();
    uvm_reg_data_t v;
    for (int unsigned it = 0; it < n_iter; it++) begin
      int unsigned mode   = it % 4;      // 0/3: on an edge or between edges, 1: right after START, 2: during an APB access
      int unsigned hold   = $urandom_range(12, 1);
      int unsigned n_act  = (it % 5 == 4) ? 0 : $urandom_range(num_ch, 1);
      bit          en_on  = (it % 6 != 5);

      axi_cfg.set_delays(0, $urandom_range(8, 0), $urandom_range(80, 10));
      set_int_enable(all_int_mask());
      set_enable(en_on);
      for (int unsigned c = 0; c < n_act; c++) begin
        dma_xfer x = new_xfer(c);
        if (!x.randomize() with { len inside {[100:900]}; }) `uvm_fatal("RAND", "randomization failed")
        program_channel(x);
        start_channel(c);
      end
      if (mode == 3 && n_act > 0) abort_channel(0);
      wait_cycles(mode == 1 ? $urandom_range(3, 0) : $urandom_range(600, 5));

      `uvm_info("VSEQ", $sformatf("reset #%0d: %0d channel(s) started, EN=%0b, mode %0d, %0d cycle(s)",
                                  it, n_act, en_on, mode, hold), UVM_LOW)
      if (mode == 2) begin
        fork
          begin
            apb_rw_seq s = apb_rw_seq::type_id::create("s_during_reset");
            s.addr  = 12'h114;
            s.write = 0;
            s.data  = 0;
            s.start(p_sequencer.apb_sqr, this);   // may be cut by the reset: result ignored
          end
          apply_reset(hold, 1'b1);
        join
      end else begin
        apply_reset(hold, $urandom_range(1, 0));
      end

      // every register is back at its reset value (the scoreboard compares
      // each read against its own reset model as well)
      begin
        uvm_reg_hw_reset_seq rs = uvm_reg_hw_reset_seq::type_id::create("hw_reset_seq");
        rs.model = rm;
        rs.start(null, this);
      end
      if (irq_vif.irq !== 1'b0) `uvm_error("RESET", "irq high after reset")
      rd(rm.BUSY, v);
      if (v != 0) `uvm_error("RESET", $sformatf("BUSY=0x%0h after reset", v))

      // and the controller works normally afterwards
      axi_cfg.set_delays(0, 3, 30);
      set_enable(1);
      begin
        dma_xfer x = rand_xfer($urandom_range(num_ch - 1, 0));
        run_xfer(x);
      end
    end
  endtask
endclass

