// -----------------------------------------------------------------------------
// dma_scoreboard - cycle-aware reference model of the DMA controller
//
// Inputs : APB transfers, completed AXI bursts, AXI read-address requests.
// Checks :
//   * every AR/AW: channel, address, length (MAX_BURST / REMAIN / 4 KB split),
//     burst type, size, no 4 KB crossing
//   * every W beat equals the corresponding R beat of the same burst, WSTRB
//   * only one burst in flight, round-robin grant order, no grant while
//     CTRL.EN=0, no grant after ABORT, no grant to an idle channel
//   * every APB read (ID, CTRL, INT_*, BUSY, channel registers, STAT) against
//     the model, PSLVERR on unmapped/misaligned addresses
//   * the irq pin every clock cycle
//   * end of test: nothing in flight, every channel idle
//
// Timing model: every architectural state change is recorded with the clock
// edge at which the DUT flops update (dma_tv). A monitor sample taken at edge
// t sees the value from before edge t, so the expected value of anything
// observed at time t is "new value if changed strictly before t, else old
// value". This makes the model independent of the order in which monitors
// deliver same-edge events. Abort completion (one cycle after the burst
// boundary) is scheduled and resolved lazily.
// -----------------------------------------------------------------------------

// Report a mismatch with the caller's file/line and count it
`define SB_ERROR(ID, MSG) \
  begin \
    n_errors_reported++; \
    `uvm_error(ID, MSG) \
  end

`uvm_analysis_imp_decl(_apb)
`uvm_analysis_imp_decl(_axi)
`uvm_analysis_imp_decl(_arreq)

// Timed value: current and previous value plus the edge of the last change
class dma_tv #(type T = bit [31:0]);
  T    cur;
  T    prev;
  time t_chg;

  function new(T init);
    cur   = init;
    prev  = init;
    t_chg = 0;
  endfunction

  function void set(T v, time t);
    if (t != t_chg) prev = cur;   // several updates in one edge keep the old value
    cur   = v;
    t_chg = t;
  endfunction

  // Value seen by a sample taken at edge t
  function T at(time t);
    return (t > t_chg) ? cur : prev;
  endfunction
endclass : dma_tv


// Architectural state of one channel
class dma_ch_model;
  int unsigned idx;

  // descriptor latched at START
  bit [31:0] cur_src, cur_dst;
  bit [15:0] rem;
  bit [3:0]  max_burst;
  bit        src_inc, dst_inc;

  // sticky status
  bit        s_done, s_err, s_aborted, s_err_wr;
  bit [1:0]  s_err_resp;

  dma_tv #(bit)        busy;
  dma_tv #(bit)        abort_pend;
  dma_tv #(bit [31:0]) stat;
  time                 t_abort;

  // burst in flight
  bit          inflight;
  bit          rd_done;
  axi_txn      rd_burst;
  int unsigned exp_beats;
  bit          lim_len, lim_max, lim_4k;

  // scheduled abort completion
  bit          abort_sched;
  bit          abort_cancellable;
  time         t_abort_fin;

  // statistics
  int unsigned n_start, n_done, n_err, n_abort, n_bursts, n_words;

  function new(int unsigned i);
    idx        = i;
    busy       = new(1'b0);
    abort_pend = new(1'b0);
    stat       = new(32'h0);
    max_burst  = 4'hF;
    src_inc    = 1'b1;
    dst_inc    = 1'b1;
  endfunction

  function bit [31:0] stat_word();
    return {rem, 9'b0, s_err_wr, s_err_resp, s_aborted, s_err, s_done, busy.cur};
  endfunction

  function void update_stat(time t);
    stat.set(stat_word(), t);
  endfunction
endclass : dma_ch_model


class dma_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(dma_scoreboard)

  uvm_analysis_imp_apb   #(apb_seq_item, dma_scoreboard) apb_export;
  uvm_analysis_imp_axi   #(axi_txn,      dma_scoreboard) axi_export;
  uvm_analysis_imp_arreq #(axi_txn,      dma_scoreboard) arreq_export;
  uvm_analysis_port      #(dma_cov_evt)                  cov_ap;

  dma_env_cfg    cfg;
  virtual irq_if irq_vif;

  protected int unsigned num_ch;
  protected time         T;
  protected bit [31:0]   int_mask;

  // model state
  protected dma_ch_model         ch[];
  protected dma_tv #(bit)        en;
  protected dma_tv #(bit [31:0]) int_status;
  protected dma_tv #(bit [31:0]) int_enable;
  protected bit [31:0]           int_set_mask;
  protected time                 int_set_t;
  protected bit [5:0]            sh_cfg[];
  protected bit [31:0]           sh_src[], sh_dst[];
  protected bit [15:0]           sh_len[];
  protected int unsigned         last_grant;
  protected bit                  engine_busy;
  protected int unsigned         engine_ch;
  protected time                 last_burst_end;
  protected bit [31:0]           irq_srcs_q;

  // statistics
  int unsigned n_apb_checked, n_reads_checked, n_bursts_checked, n_beats_checked;
  int unsigned n_rr_checked, n_irq_cycles, n_errors_reported;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    apb_export   = new("apb_export", this);
    axi_export   = new("axi_export", this);
    arreq_export = new("arreq_export", this);
    cov_ap       = new("cov_ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(dma_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "dma_env_cfg not found")
    irq_vif = cfg.irq_vif;
    num_ch  = cfg.num_ch;
    T       = cfg.clk_period;
    int_mask = ((32'h1 << num_ch) - 1) | (((32'h1 << num_ch) - 1) << 8);
    ch = new[num_ch];
    foreach (ch[i]) ch[i] = new(i);
    sh_cfg = new[num_ch];
    sh_src = new[num_ch];
    sh_dst = new[num_ch];
    sh_len = new[num_ch];
    foreach (sh_cfg[i]) begin
      sh_cfg[i] = 6'h3F;
      sh_src[i] = 0;
      sh_dst[i] = 0;
      sh_len[i] = 0;
    end
    en         = new(1'b0);
    int_status = new(32'h0);
    int_enable = new(32'h0);
    last_grant = num_ch - 1;
  endfunction

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  protected function void emit(dma_cov_evt e);
    cov_ap.write(e);
  endfunction

  protected function dma_cov_evt new_evt(dma_ev_kind_e k, int unsigned c);
    dma_cov_evt e = dma_cov_evt::type_id::create("cov_evt");
    e.kind = k;
    e.ch   = c;
    return e;
  endfunction

  protected function void int_set(bit [31:0] mask, time t);
    if (int_set_t != t) begin
      int_set_t    = t;
      int_set_mask = '0;
    end
    int_set_mask |= mask;
    int_status.set(int_status.cur | mask, t);
  endfunction

  // A channel whose busy flag falls at edge t ignores commands at edge t
  protected function bit finishing_at(int unsigned c, time t);
    return (ch[c].busy.t_chg == t) && (ch[c].busy.cur == 1'b0) && (ch[c].busy.prev == 1'b1);
  endfunction

  // Apply scheduled abort completions whose edge has passed
  protected function void resolve(time now);
    foreach (ch[c]) begin
      dma_ch_model m = ch[c];
      if (m.abort_sched && now > m.t_abort_fin) begin
        m.abort_sched = 0;
        if (m.busy.cur) begin
          m.busy.set(1'b0, m.t_abort_fin);
          m.abort_pend.set(1'b0, m.t_abort_fin);
          m.s_aborted = 1'b1;
          m.update_stat(m.t_abort_fin);
          m.n_abort++;
          begin
            dma_cov_evt e = new_evt(EV_FINISH, c);
            e.fin = FIN_ABORT;
            emit(e);
          end
          `uvm_info("SB", $sformatf("ch%0d aborted @%0t, REMAIN=%0d", c, m.t_abort_fin, m.rem), UVM_MEDIUM)
        end
      end
    end
  endfunction

  protected function void schedule_abort(int unsigned c, time t_fin, bit cancellable);
    ch[c].abort_sched       = 1'b1;
    ch[c].abort_cancellable = cancellable;
    ch[c].t_abort_fin       = t_fin;
  endfunction

  protected function void finish_done(int unsigned c, time t);
    dma_ch_model m = ch[c];
    dma_cov_evt  e;
    m.busy.set(1'b0, t);
    m.abort_pend.set(1'b0, t);
    m.abort_sched = 1'b0;
    m.s_done = 1'b1;
    m.update_stat(t);
    m.n_done++;
    int_set(32'h1 << c, t);
    e = new_evt(EV_FINISH, c);
    e.fin = FIN_DONE;
    emit(e);
    `uvm_info("SB", $sformatf("ch%0d done @%0t", c, t), UVM_MEDIUM)
  endfunction

  protected function void finish_err(int unsigned c, bit is_wr, bit [1:0] resp, time t);
    dma_ch_model m = ch[c];
    dma_cov_evt  e;
    m.busy.set(1'b0, t);
    m.abort_pend.set(1'b0, t);
    m.abort_sched = 1'b0;
    m.s_err      = 1'b1;
    m.s_err_wr   = is_wr;
    m.s_err_resp = resp;
    m.update_stat(t);
    m.n_err++;
    int_set(32'h1 << (8 + c), t);
    e = new_evt(EV_FINISH, c);
    e.fin = is_wr ? FIN_ERR_WR : FIN_ERR_RD;
    emit(e);
    `uvm_info("SB", $sformatf("ch%0d error (%s resp=%0d) @%0t", c, is_wr ? "write" : "read", resp, t), UVM_MEDIUM)
  endfunction

  // Expected beats of the next burst of channel c (and why it was cut)
  protected function int unsigned next_beats(int unsigned c, output bit lim_len, output bit lim_max,
                                             output bit lim_4k);
    dma_ch_model m = ch[c];
    int unsigned b, src_room, dst_room;
    b        = m.max_burst + 1;
    lim_len  = 0;
    lim_max  = 0;
    lim_4k   = 0;
    src_room = 1024 - m.cur_src[11:2];
    dst_room = 1024 - m.cur_dst[11:2];
    if (m.rem <= b) begin
      b = m.rem;
      lim_len = 1;
    end else begin
      lim_max = 1;
    end
    if (m.src_inc && b > src_room) begin
      b = src_room; lim_4k = 1; lim_len = 0; lim_max = 0;
    end
    if (m.dst_inc && b > dst_room) begin
      b = dst_room; lim_4k = 1; lim_len = 0; lim_max = 0;
    end
    return b;
  endfunction

  protected function bit crosses_4k(bit [31:0] a, bit [7:0] len, bit [1:0] burst);
    if (burst != 2'b01) return 1'b0;
    return (int'(a[11:0]) + (int'(len) + 1) * 4) > 4096;
  endfunction

  // ---------------------------------------------------------------------------
  // APB
  // ---------------------------------------------------------------------------
  protected function void decode(bit [11:0] a, output bit ok, output bit is_ch,
                                 output int unsigned c, output bit [4:0] off, output int unsigned region);
    ok     = 0;
    is_ch  = 0;
    c      = a[7:5];
    off    = a[4:0];
    region = 2;
    if (a[1:0] != 0) begin
      region = 3;
      return;
    end
    if (a[11:8] == 4'h0) begin
      if (a[7:0] inside {8'h00, 8'h04, 8'h08, 8'h0C, 8'h10}) begin
        ok = 1; region = 0;
      end
    end else if (a[11:8] == 4'h1 && c < num_ch) begin
      if (off inside {5'h00, 5'h04, 5'h08, 5'h0C, 5'h10, 5'h14}) begin
        ok = 1; is_ch = 1; region = 1;
      end
    end
  endfunction

  function void write_apb(apb_seq_item t);
    time         now = $time;
    bit          ok, is_ch;
    int unsigned c, region;
    bit [4:0]    off;
    dma_cov_evt  e;

    resolve(now);
    n_apb_checked++;
    decode(t.addr, ok, is_ch, c, off, region);

    e         = new_evt(EV_APB, c);
    e.region  = region;
    e.write   = t.write;
    e.slverr  = t.slverr;
    e.reg_off = off;
    emit(e);

    if (!ok) begin
      if (!t.slverr) `SB_ERROR("SB_APB", $sformatf("missing PSLVERR on unmapped access: %s", t.convert2string()))
      if (!t.write && t.data != 0) `SB_ERROR("SB_APB", $sformatf("unmapped read returned non-zero: %s", t.convert2string()))
      return;
    end
    if (t.slverr) `SB_ERROR("SB_APB", $sformatf("unexpected PSLVERR: %s", t.convert2string()))

    if (t.write) apb_write(t, is_ch, c, off, now);
    else         apb_read_check(t, is_ch, c, off, now);
  endfunction

  protected function void apb_write(apb_seq_item t, bit is_ch, int unsigned c, bit [4:0] off, time now);
    if (!is_ch) begin
      case (t.addr[7:0])
        8'h04: en.set(t.data[0], now);
        8'h08: begin
          bit [31:0] clr = t.data & int_mask;
          if (int_set_t == now) clr &= ~int_set_mask;   // hardware set wins
          int_status.set(int_status.cur & ~clr, now);
        end
        8'h0C: int_enable.set(t.data & int_mask, now);
        default: ;   // ID / BUSY are read-only
      endcase
      return;
    end
    case (off)
      5'h00: sh_cfg[c] = t.data[5:0];
      5'h04: sh_src[c] = {t.data[31:2], 2'b00};
      5'h08: sh_dst[c] = {t.data[31:2], 2'b00};
      5'h0C: sh_len[c] = t.data[15:0];
      5'h10: command(c, t.data[0], t.data[1], now);
      default: ;   // STAT is read-only
    endcase
  endfunction

  protected function void command(int unsigned c, bit do_start, bit do_abort, time now);
    dma_ch_model m = ch[c];
    dma_cov_evt  e;
    bit          busy_now = m.busy.at(now);

    if (do_start) begin
      if (!busy_now) begin
        accept_start(c, do_abort, now);
        return;
      end
      e = new_evt(EV_START_IGNORED, c);
      emit(e);
      `uvm_info("SB", $sformatf("ch%0d START ignored (busy) @%0t", c, now), UVM_MEDIUM)
    end
    if (do_abort) begin
      if (!busy_now || finishing_at(c, now)) begin
        e = new_evt(EV_ABORT_IGNORED, c);
        emit(e);
        return;
      end
      e          = new_evt(EV_ABORT, c);
      e.inflight = m.inflight;
      e.en       = en.at(now);
      emit(e);
      if (m.abort_pend.cur) return;       // already pending
      m.abort_pend.set(1'b1, now);
      m.t_abort = now;
      if (!m.inflight) schedule_abort(c, now + T, 1'b1);
      `uvm_info("SB", $sformatf("ch%0d ABORT accepted @%0t (inflight=%0b)", c, now, m.inflight), UVM_MEDIUM)
    end
  endfunction

  protected function void accept_start(int unsigned c, bit with_abort, time now);
    dma_ch_model m = ch[c];
    dma_cov_evt  e;
    m.max_burst  = sh_cfg[c][3:0];
    m.src_inc    = sh_cfg[c][4];
    m.dst_inc    = sh_cfg[c][5];
    m.cur_src    = sh_src[c];
    m.cur_dst    = sh_dst[c];
    m.rem        = sh_len[c];
    m.s_done     = 0;
    m.s_err      = 0;
    m.s_aborted  = 0;
    m.s_err_wr   = 0;
    m.s_err_resp = 0;
    m.inflight   = 0;
    m.rd_done    = 0;
    m.n_start++;

    e            = new_evt(EV_START, c);
    e.len        = sh_len[c];
    e.max_burst  = m.max_burst;
    e.src_inc    = m.src_inc;
    e.dst_inc    = m.dst_inc;
    e.with_abort = with_abort;
    emit(e);
    `uvm_info("SB", $sformatf("ch%0d START @%0t src=0x%08h dst=0x%08h len=%0d max_burst=%0d src_inc=%0b dst_inc=%0b%s",
                              c, now, m.cur_src, m.cur_dst, m.rem, m.max_burst, m.src_inc, m.dst_inc,
                              with_abort ? " +ABORT" : ""), UVM_MEDIUM)

    if (m.rem == 0) begin
      m.s_done = 1;
      m.update_stat(now);
      m.n_done++;
      int_set(32'h1 << c, now);
      e     = new_evt(EV_FINISH, c);
      e.fin = FIN_DONE;
      emit(e);
      return;
    end
    m.busy.set(1'b1, now);
    m.update_stat(now);
    if (with_abort) begin
      m.abort_pend.set(1'b1, now);
      m.t_abort = now;
      schedule_abort(c, now + T, 1'b1);
    end
  endfunction

  protected function bit [31:0] expected_read(bit [11:0] a, bit is_ch, int unsigned c, bit [4:0] off,
                                              time now);
    bit [31:0] v = 0;
    if (!is_ch) begin
      case (a[7:0])
        8'h00: v = {16'hDA0C, 8'h01, 8'(num_ch)};
        8'h04: v = {31'b0, en.at(now)};
        8'h08: v = int_status.at(now);
        8'h0C: v = int_enable.at(now);
        8'h10: foreach (ch[k]) v[k] = ch[k].busy.at(now);
        default: v = 0;
      endcase
    end else begin
      case (off)
        5'h00: v = {26'b0, sh_cfg[c]};
        5'h04: v = sh_src[c];
        5'h08: v = sh_dst[c];
        5'h0C: v = {16'b0, sh_len[c]};
        5'h10: v = 0;
        5'h14: v = ch[c].stat.at(now);
        default: v = 0;
      endcase
    end
    return v;
  endfunction

  protected function void apb_read_check(apb_seq_item t, bit is_ch, int unsigned c, bit [4:0] off, time now);
    bit [31:0] exp = expected_read(t.addr, is_ch, c, off, now);
    n_reads_checked++;
    if (t.data !== exp)
      `SB_ERROR("SB_REG", $sformatf("read 0x%03h: DUT=0x%08h model=0x%08h (diff 0x%08h)",
                                   t.addr, t.data, exp, t.data ^ exp))
  endfunction

  // ---------------------------------------------------------------------------
  // AXI read-address request (first cycle ARVALID is high)
  // ---------------------------------------------------------------------------
  function void write_arreq(axi_txn t);
    time         now = $time;
    time         tg;
    int unsigned c, exp_c, n_req, b;
    bit          found, l_len, l_max, l_4k;
    dma_ch_model m;
    dma_cov_evt  e;

    resolve(now);
    c  = t.id;
    tg = now - T;                          // grant edge

    if (c >= num_ch) begin
      `SB_ERROR("SB_ARB", $sformatf("ARID=%0d is not a channel: %s", t.id, t.convert2string()))
      return;
    end
    m = ch[c];

    if (engine_busy)
      `SB_ERROR("SB_ARB", $sformatf("AR for ch%0d while a burst of ch%0d is in flight", c, engine_ch))
    if (tg <= last_burst_end && last_burst_end != 0)
      `SB_ERROR("SB_ARB", $sformatf("ch%0d granted @%0t before the previous burst ended @%0t", c, tg, last_burst_end))
    if (!m.busy.at(tg))
      `SB_ERROR("SB_ARB", $sformatf("AR for idle channel %0d: %s", c, t.convert2string()))
    if (m.abort_pend.at(tg))
      `SB_ERROR("SB_ABORT", $sformatf("ch%0d granted @%0t after ABORT @%0t", c, tg, m.t_abort))
    if (!en.at(tg))
      `SB_ERROR("SB_EN", $sformatf("ch%0d granted @%0t while CTRL.EN=0", c, tg))

    // Round robin: first requester after the last grant
    n_req = 0;
    found = 0;
    exp_c = c;
    for (int unsigned i = 1; i <= num_ch; i++) begin
      int unsigned k = (last_grant + i) % num_ch;
      if (ch[k].busy.at(tg) && !ch[k].abort_pend.at(tg)) begin
        n_req++;
        if (!found) begin
          found = 1;
          exp_c = k;
        end
      end
    end
    n_rr_checked++;
    if (found && exp_c != c)
      `SB_ERROR("SB_RR", $sformatf("round-robin violation: granted ch%0d, expected ch%0d (last grant ch%0d)",
                                  c, exp_c, last_grant))
    last_grant = c;

    // Burst shape
    b = next_beats(c, l_len, l_max, l_4k);
    if (t.addr != m.cur_src)
      `SB_ERROR("SB_AR", $sformatf("ch%0d ARADDR=0x%08h expected 0x%08h", c, t.addr, m.cur_src))
    if (t.len != 8'(b - 1))
      `SB_ERROR("SB_AR", $sformatf("ch%0d ARLEN=%0d expected %0d (rem=%0d max_burst=%0d src=0x%08h dst=0x%08h)",
                                  c, t.len, b - 1, m.rem, m.max_burst, m.cur_src, m.cur_dst))
    if (t.size != 3'd2)
      `SB_ERROR("SB_AR", $sformatf("ch%0d ARSIZE=%0d expected 2", c, t.size))
    if (t.burst != (m.src_inc ? 2'b01 : 2'b00))
      `SB_ERROR("SB_AR", $sformatf("ch%0d ARBURST=%0d expected %0d", c, t.burst, m.src_inc ? 1 : 0))
    if (crosses_4k(t.addr, t.len, t.burst))
      `SB_ERROR("SB_4K", $sformatf("read burst crosses a 4KB boundary: %s", t.convert2string()))

    m.inflight  = 1;
    m.rd_done   = 0;
    m.exp_beats = b;
    m.lim_len   = l_len;
    m.lim_max   = l_max;
    m.lim_4k    = l_4k;
    engine_busy = 1;
    engine_ch   = c;
    // A cancellable (not in flight) abort is superseded: the burst granted in
    // the abort cycle completes first.
    if (m.abort_sched && m.abort_cancellable) m.abort_sched = 0;

    e       = new_evt(EV_GRANT, c);
    e.n_req = n_req;
    emit(e);
  endfunction

  // ---------------------------------------------------------------------------
  // Completed AXI bursts
  // ---------------------------------------------------------------------------
  function void write_axi(axi_txn t);
    time         now = $time;
    int unsigned c;
    dma_ch_model m;
    dma_cov_evt  e;

    resolve(now);
    c = t.id;
    if (c >= num_ch) begin
      `SB_ERROR("SB_AXI", $sformatf("burst with ID %0d is not a channel: %s", t.id, t.convert2string()))
      return;
    end
    m = ch[c];
    n_bursts_checked++;

    e             = new_evt(EV_BURST, c);
    e.is_write    = (t.kind == AXI_WRITE);
    e.beats       = t.beats();
    e.burst       = t.burst;
    e.resp        = t.first_error();
    e.lim_len     = m.lim_len;
    e.lim_max     = m.lim_max;
    e.lim_4k      = m.lim_4k;
    e.addr_wait   = t.addr_wait;
    e.w_before_aw = t.w_before_aw;
    emit(e);

    if (t.kind == AXI_READ) begin
      if (!engine_busy || engine_ch != c || !m.inflight || m.rd_done) begin
        `SB_ERROR("SB_AXI", $sformatf("unexpected read burst: %s", t.convert2string()))
        return;
      end
      if (t.data.size() != m.exp_beats)
        `SB_ERROR("SB_AXI", $sformatf("ch%0d read burst has %0d beats, expected %0d", c, t.data.size(), m.exp_beats))
      if (t.has_error()) begin
        m.inflight     = 0;
        engine_busy    = 0;
        last_burst_end = now;
        finish_err(c, 1'b0, t.first_error(), now);
      end else begin
        m.rd_burst = t;
        m.rd_done  = 1;
      end
      return;
    end

    // WRITE
    if (!engine_busy || engine_ch != c || !m.inflight || !m.rd_done) begin
      `SB_ERROR("SB_AXI", $sformatf("unexpected write burst: %s", t.convert2string()))
      return;
    end
    if (t.addr != m.cur_dst)
      `SB_ERROR("SB_AW", $sformatf("ch%0d AWADDR=0x%08h expected 0x%08h", c, t.addr, m.cur_dst))
    if (t.len != 8'(m.exp_beats - 1))
      `SB_ERROR("SB_AW", $sformatf("ch%0d AWLEN=%0d expected %0d", c, t.len, m.exp_beats - 1))
    if (t.size != 3'd2)
      `SB_ERROR("SB_AW", $sformatf("ch%0d AWSIZE=%0d expected 2", c, t.size))
    if (t.burst != (m.dst_inc ? 2'b01 : 2'b00))
      `SB_ERROR("SB_AW", $sformatf("ch%0d AWBURST=%0d expected %0d", c, t.burst, m.dst_inc ? 1 : 0))
    if (crosses_4k(t.addr, t.len, t.burst))
      `SB_ERROR("SB_4K", $sformatf("write burst crosses a 4KB boundary: %s", t.convert2string()))
    if (t.data.size() != m.rd_burst.data.size()) begin
      `SB_ERROR("SB_DATA", $sformatf("ch%0d write burst has %0d beats, read burst had %0d",
                                    c, t.data.size(), m.rd_burst.data.size()))
    end else begin
      foreach (t.data[i]) begin
        n_beats_checked++;
        if (t.data[i] != m.rd_burst.data[i]) begin
          `SB_ERROR("SB_DATA", $sformatf("ch%0d beat %0d: WDATA=0x%08h, read data was 0x%08h (AW 0x%08h)",
                                        c, i, t.data[i], m.rd_burst.data[i], t.addr))
          break;
        end
      end
    end
    foreach (t.strb[i]) if (t.strb[i] != 4'hF) begin
      `SB_ERROR("SB_DATA", $sformatf("ch%0d beat %0d: WSTRB=0x%0h expected 0xF", c, i, t.strb[i]))
      break;
    end

    m.inflight     = 0;
    m.rd_done      = 0;
    engine_busy    = 0;
    last_burst_end = now;

    if (t.resp[0][1]) begin
      finish_err(c, 1'b1, t.resp[0], now);
      return;
    end

    if (m.src_inc) m.cur_src += 32'(m.exp_beats) * 4;
    if (m.dst_inc) m.cur_dst += 32'(m.exp_beats) * 4;
    m.rem -= 16'(m.exp_beats);
    m.n_bursts++;
    m.n_words += m.exp_beats;
    if (m.rem == 0) begin
      finish_done(c, now);
    end else begin
      m.update_stat(now);
      if (m.abort_pend.cur) schedule_abort(c, now + T, 1'b0);
    end
  endfunction

  // ---------------------------------------------------------------------------
  // irq pin: checked every cycle
  // ---------------------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
    int unsigned n_bad;
    n_bad = 0;
    if (irq_vif == null) return;
    forever begin
      @(posedge irq_vif.clk);
      if (irq_vif.rst_n !== 1'b1) continue;
      begin
        time now = $time;
        bit  exp_irq = |(int_status.at(now) & int_enable.at(now));
        n_irq_cycles++;
        if (irq_vif.irq !== exp_irq) begin
          n_bad++;
          if (n_bad <= 5)
            `SB_ERROR("SB_IRQ", $sformatf("irq=%b expected %b (INT_STATUS=0x%08h INT_ENABLE=0x%08h)",
                                         irq_vif.irq, exp_irq, int_status.at(now), int_enable.at(now)))
        end
        // coverage: sample the interrupt causes whenever the set of enabled
        // pending sources changes while irq is asserted
        if (irq_vif.irq === 1'b1 && (int_status.at(now) & int_enable.at(now)) != irq_srcs_q) begin
          dma_cov_evt e = new_evt(EV_IRQ, 0);
          e.int_status = int_status.at(now);
          e.int_enable = int_enable.at(now);
          emit(e);
        end
        irq_srcs_q = (irq_vif.irq === 1'b1) ? (int_status.at(now) & int_enable.at(now)) : 32'h0;
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // End of test
  // ---------------------------------------------------------------------------
  virtual function void check_phase(uvm_phase phase);
    resolve($time + T);
    if (engine_busy)
      `SB_ERROR("SB_EOT", $sformatf("burst of ch%0d still in flight at end of test", engine_ch))
    foreach (ch[c]) begin
      if (ch[c].busy.cur)
        `SB_ERROR("SB_EOT", $sformatf("ch%0d still busy at end of test (REMAIN=%0d)", c, ch[c].rem))
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    string s;
    s = $sformatf("\n  APB transfers checked : %0d (%0d register reads compared)", n_apb_checked, n_reads_checked);
    s = {s, $sformatf("\n  AXI bursts checked    : %0d (%0d data beats compared)", n_bursts_checked, n_beats_checked)};
    s = {s, $sformatf("\n  grants checked (RR)   : %0d", n_rr_checked)};
    s = {s, $sformatf("\n  irq cycles checked    : %0d", n_irq_cycles)};
    foreach (ch[c])
      s = {s, $sformatf("\n  ch%0d: start=%0d done=%0d err=%0d abort=%0d bursts=%0d words=%0d",
                        c, ch[c].n_start, ch[c].n_done, ch[c].n_err, ch[c].n_abort,
                        ch[c].n_bursts, ch[c].n_words)};
    s = {s, $sformatf("\n  scoreboard errors     : %0d", n_errors_reported)};
    `uvm_info("SB", s, UVM_LOW)
  endfunction

endclass : dma_scoreboard
