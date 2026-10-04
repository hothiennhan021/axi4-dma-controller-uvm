// -----------------------------------------------------------------------------
// dma_coverage - functional coverage model (see docs/verification_plan.md)
// Samples dma_cov_evt objects published by the scoreboard.
// -----------------------------------------------------------------------------
class dma_coverage extends uvm_subscriber #(dma_cov_evt);

  `uvm_component_utils(dma_coverage)

  dma_env_cfg cfg;

  // ---------------------------------------------------------------------------
  // Transfer configuration at START
  // ---------------------------------------------------------------------------
  covergroup cg_start with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_ch: coverpoint e.ch { bins ch[] = {[0:`DMA_NUM_CH-1]}; }
    cp_len: coverpoint e.len {
      bins zero      = {0};
      bins one       = {1};
      bins short_len = {[2:15]};
      bins exact16   = {16};
      bins mid_len   = {[17:64]};
      bins long_len  = {[65:1023]};
      bins huge      = {[1024:65535]};
    }
    cp_max_burst: coverpoint e.max_burst {
      bins single = {0};
      bins small_b = {[1:6]};
      bins eight  = {7};
      bins large_b = {[8:14]};
      bins full   = {15};
    }
    cp_src_inc: coverpoint e.src_inc;
    cp_dst_inc: coverpoint e.dst_inc;
    cp_with_abort: coverpoint e.with_abort;
    x_inc: cross cp_src_inc, cp_dst_inc;
    x_len_burst: cross cp_len, cp_max_burst {
      ignore_bins zero_len = binsof(cp_len.zero);
      ignore_bins one_len  = binsof(cp_len.one);
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Completed bursts
  // ---------------------------------------------------------------------------
  covergroup cg_burst with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_dir: coverpoint e.is_write { bins rd = {0}; bins wr = {1}; }
    cp_beats: coverpoint e.beats { bins b[] = {[1:16]}; }
    cp_type: coverpoint e.burst { bins fixed = {2'b00}; bins incr = {2'b01}; }
    cp_resp: coverpoint e.resp { bins okay = {2'b00}; bins slverr = {2'b10}; bins decerr = {2'b11}; }
    cp_cut: coverpoint {e.lim_4k, e.lim_max, e.lim_len} {
      bins by_len = {3'b001};
      bins by_max = {3'b010};
      bins by_4k  = {3'b100};
    }
    cp_addr_wait: coverpoint e.addr_wait {
      bins none  = {0};
      bins short_w = {[1:2]};
      bins long_w  = {[3:$]};
    }
    cp_ch: coverpoint e.ch { bins ch[] = {[0:`DMA_NUM_CH-1]}; }
    x_dir_resp: cross cp_dir, cp_resp;
    x_dir_type: cross cp_dir, cp_type;
    x_type_beats: cross cp_type, cp_beats;
    x_cut_dir: cross cp_cut, cp_dir;
  endgroup

  covergroup cg_wr_order with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_w_before_aw: coverpoint e.w_before_aw { bins aw_first = {0}; bins w_first = {1}; }
  endgroup

  // ---------------------------------------------------------------------------
  // Arbitration
  // ---------------------------------------------------------------------------
  covergroup cg_grant with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_ch: coverpoint e.ch { bins ch[] = {[0:`DMA_NUM_CH-1]}; }
    cp_n_req: coverpoint e.n_req { bins n[] = {[1:`DMA_NUM_CH]}; }
    x_ch_nreq: cross cp_ch, cp_n_req;
  endgroup

  // ---------------------------------------------------------------------------
  // Channel completion and commands
  // ---------------------------------------------------------------------------
  covergroup cg_finish with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_ch: coverpoint e.ch { bins ch[] = {[0:`DMA_NUM_CH-1]}; }
    cp_fin: coverpoint e.fin {
      bins done   = {FIN_DONE};
      bins err_rd = {FIN_ERR_RD};
      bins err_wr = {FIN_ERR_WR};
      bins abort  = {FIN_ABORT};
    }
    x_ch_fin: cross cp_ch, cp_fin;
  endgroup

  covergroup cg_cmd with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_kind: coverpoint e.kind {
      bins start_ignored = {EV_START_IGNORED};
      bins abort_ignored = {EV_ABORT_IGNORED};
      bins abort         = {EV_ABORT};
    }
    cp_abort_ctx: coverpoint {e.inflight, e.en} iff (e.kind == EV_ABORT) {
      bins waiting_paused  = {2'b00};
      bins waiting_enabled = {2'b01};
      bins inflight_paused = {2'b10};
      bins inflight_en     = {2'b11};
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Register interface
  // ---------------------------------------------------------------------------
  covergroup cg_apb with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_region: coverpoint e.region {
      bins global_r   = {0};
      bins channel_r  = {1};
      bins unmapped   = {2};
      bins misaligned = {3};
    }
    cp_write: coverpoint e.write;
    cp_ch_reg: coverpoint e.reg_off iff (e.region == 1) {
      bins cfg  = {5'h00};
      bins src  = {5'h04};
      bins dst  = {5'h08};
      bins len  = {5'h0C};
      bins cmd  = {5'h10};
      bins stat = {5'h14};
    }
    x_region_dir: cross cp_region, cp_write;
    x_chreg_dir: cross cp_ch_reg, cp_write;
  endgroup

  // ---------------------------------------------------------------------------
  // Interrupt
  // ---------------------------------------------------------------------------
  covergroup cg_irq with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_cause: coverpoint {|(e.int_status[15:8] & e.int_enable[15:8]), |(e.int_status[7:0] & e.int_enable[7:0])} {
      bins done_only = {2'b01};
      bins err_only  = {2'b10};
      bins both      = {2'b11};
    }
    cp_masked_pending: coverpoint (|(e.int_status & ~e.int_enable)) {
      bins none   = {0};
      bins masked = {1};
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Reset in the middle of operation
  // ---------------------------------------------------------------------------
  covergroup cg_reset with function sample(dma_cov_evt e);
    option.per_instance = 1;
    cp_phase: coverpoint e.phase {
      bins engine_idle = {0};
      bins read_burst  = {1};
      bins write_burst = {2};
    }
    cp_busy: coverpoint e.n_busy {
      bins none = {0};
      bins one  = {1};
      bins many = {[2:`DMA_NUM_CH]};
    }
    cp_when: coverpoint e.mid_cycle { bins on_edge = {0}; bins between_edges = {1}; }
    cp_en: coverpoint e.en;
    x_phase_when: cross cp_phase, cp_when;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_start    = new();
    cg_burst    = new();
    cg_wr_order = new();
    cg_grant    = new();
    cg_finish   = new();
    cg_cmd      = new();
    cg_apb      = new();
    cg_irq      = new();
    cg_reset    = new();
  endfunction

  virtual function void write(dma_cov_evt t);
    case (t.kind)
      EV_START:         cg_start.sample(t);
      EV_BURST: begin
        cg_burst.sample(t);
        if (t.is_write) cg_wr_order.sample(t);
      end
      EV_GRANT:         cg_grant.sample(t);
      EV_FINISH:        cg_finish.sample(t);
      EV_START_IGNORED,
      EV_ABORT_IGNORED,
      EV_ABORT:         cg_cmd.sample(t);
      EV_APB:           cg_apb.sample(t);
      EV_IRQ:           cg_irq.sample(t);
      EV_RESET:         cg_reset.sample(t);
      default: ;
    endcase
  endfunction

  function real total();
    real s;
    s = cg_start.get_inst_coverage() + cg_burst.get_inst_coverage() + cg_wr_order.get_inst_coverage() +
        cg_grant.get_inst_coverage() + cg_finish.get_inst_coverage() + cg_cmd.get_inst_coverage() +
        cg_apb.get_inst_coverage() + cg_irq.get_inst_coverage() + cg_reset.get_inst_coverage();
    return s / 9.0;
  endfunction

  virtual function void report_phase(uvm_phase phase);
    string s;
    s = $sformatf("\n  cg_start    %6.2f%%", cg_start.get_inst_coverage());
    s = {s, $sformatf("\n  cg_burst    %6.2f%%", cg_burst.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_wr_order %6.2f%%", cg_wr_order.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_grant    %6.2f%%", cg_grant.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_finish   %6.2f%%", cg_finish.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_cmd      %6.2f%%", cg_cmd.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_apb      %6.2f%%", cg_apb.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_irq      %6.2f%%", cg_irq.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_reset    %6.2f%%", cg_reset.get_inst_coverage())};
    s = {s, $sformatf("\n  average     %6.2f%%", total())};
    `uvm_info("COV", s, UVM_LOW)
  endfunction

endclass : dma_coverage
