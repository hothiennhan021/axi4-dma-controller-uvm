// -----------------------------------------------------------------------------
// dma_cov_evt - functional-coverage event emitted by the scoreboard
//
// The scoreboard is the only component that knows the architectural meaning
// of bus activity (which channel, why a burst was cut, how a transfer ended),
// so it publishes these events and dma_coverage samples them.
// -----------------------------------------------------------------------------
typedef enum int {
  EV_START,           // START accepted
  EV_START_IGNORED,   // START while busy
  EV_ABORT,           // ABORT accepted
  EV_ABORT_IGNORED,   // ABORT while idle / finishing
  EV_GRANT,           // burst granted (AR request)
  EV_BURST,           // burst completed (read or write)
  EV_FINISH,          // channel finished (done / error / aborted)
  EV_APB,             // any APB transfer
  EV_IRQ              // irq rising edge
} dma_ev_kind_e;

typedef enum int {FIN_DONE, FIN_ERR_RD, FIN_ERR_WR, FIN_ABORT} dma_fin_kind_e;

class dma_cov_evt extends uvm_object;

  `uvm_object_utils(dma_cov_evt)

  dma_ev_kind_e  kind;
  int unsigned   ch;

  // EV_START
  bit [15:0]     len;
  bit [3:0]      max_burst;
  bit            src_inc;
  bit            dst_inc;
  bit            with_abort;

  // EV_ABORT
  bit            inflight;
  bit            en;

  // EV_GRANT
  int unsigned   n_req;

  // EV_BURST
  bit            is_write;
  int unsigned   beats;
  bit [1:0]      burst;
  bit [1:0]      resp;
  bit            lim_len;     // cut by the remaining length
  bit            lim_max;     // cut by MAX_BURST
  bit            lim_4k;      // cut by a 4 KB boundary
  int unsigned   addr_wait;
  bit            w_before_aw;

  // EV_FINISH
  dma_fin_kind_e fin;

  // EV_APB
  int unsigned   region;      // 0 global, 1 channel, 2 unmapped, 3 misaligned
  bit            write;
  bit            slverr;
  bit [4:0]      reg_off;

  // EV_IRQ
  bit [31:0]     int_status;
  bit [31:0]     int_enable;

  function new(string name = "dma_cov_evt");
    super.new(name);
  endfunction

endclass : dma_cov_evt
