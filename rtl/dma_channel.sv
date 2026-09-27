// -----------------------------------------------------------------------------
// dma_channel - runtime state of one DMA channel
//
// The programming registers (CFG/SRC/DST/LEN) are copied into working
// registers when START is accepted, so software may reprogram the channel
// while a transfer is running without disturbing it.
//
// Command rules (see docs/spec.md):
//   * START is accepted only while the channel is idle. LEN==0 completes
//     immediately (DONE, no bus traffic).
//   * ABORT is accepted only while the channel is busy and not finishing in
//     the same cycle. The channel stops at the next burst boundary: a burst
//     that is already in flight always completes, then the channel goes idle
//     with ABORTED=1 one cycle later.
//   * A burst error (read or write response SLVERR/DECERR) terminates the
//     channel with ERR=1 in the cycle of the terminating handshake.
//   * If the last burst completes successfully the channel reports DONE, even
//     if an abort was pending (the transfer is complete).
// -----------------------------------------------------------------------------
module dma_channel (
  input  logic        clk,
  input  logic        rst_n,

  // Programming registers
  input  logic [5:0]  cfg,
  input  logic [31:0] src,
  input  logic [31:0] dst,
  input  logic [15:0] len,
  input  logic        start_req,
  input  logic        abort_req,

  // Engine interface
  input  logic        eng_sel,      // engine currently owns this channel
  input  logic        eng_done,     // burst completed OK (B handshake, OKAY)
  input  logic        eng_err,      // burst terminated with an error response
  input  logic        eng_err_wr,   // 1: write response error, 0: read
  input  logic [1:0]  eng_err_resp,
  input  logic [4:0]  eng_beats,    // beats moved by the completed burst

  // Arbitration / descriptor
  output logic        req,
  output logic [31:0] cur_src,
  output logic [31:0] cur_dst,
  output logic [15:0] rem,
  output logic [3:0]  max_burst,
  output logic        src_inc,
  output logic        dst_inc,

  // Status
  output logic [31:0] stat,
  output logic        fin_done,     // pulse: channel completed (INT DONE)
  output logic        fin_err       // pulse: channel failed    (INT ERR)
);

  logic       busy;
  logic       abort_pend;
  logic       done_q, err_q, aborted_q, err_wr_q;
  logic [1:0] err_resp_q;
  logic [5:0] cfg_q;

  logic       last_ok;
  logic       fin_abort;
  logic       finishing;
  logic       start_ok;

  assign max_burst = cfg_q[3:0];
  assign src_inc   = cfg_q[4];
  assign dst_inc   = cfg_q[5];

  assign req       = busy & ~abort_pend;
  assign last_ok   = busy & eng_done & ({11'b0, eng_beats} == rem);
  assign fin_abort = busy & abort_pend & ~eng_sel;
  assign finishing = last_ok | (busy & eng_err) | fin_abort;
  assign start_ok  = start_req & ~busy;

  assign fin_done  = last_ok | (start_ok & (len == 16'd0));
  assign fin_err   = busy & eng_err;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy       <= 1'b0;
      abort_pend <= 1'b0;
      done_q     <= 1'b0;
      err_q      <= 1'b0;
      aborted_q  <= 1'b0;
      err_wr_q   <= 1'b0;
      err_resp_q <= 2'b00;
      cfg_q      <= dma_pkg::CFG_RESET;
      cur_src    <= '0;
      cur_dst    <= '0;
      rem        <= '0;
    end else begin
      if (start_ok) begin
        // New transfer: clear sticky status, latch descriptor
        done_q     <= (len == 16'd0);
        err_q      <= 1'b0;
        aborted_q  <= 1'b0;
        err_wr_q   <= 1'b0;
        err_resp_q <= 2'b00;
        cfg_q      <= cfg;
        cur_src    <= src;
        cur_dst    <= dst;
        rem        <= len;
        busy       <= (len != 16'd0);
        abort_pend <= (len != 16'd0) & abort_req;
      end else if (busy) begin
        if (abort_req && !finishing) abort_pend <= 1'b1;

        if (eng_done) begin
          cur_src <= src_inc ? cur_src + {25'b0, eng_beats, 2'b00} : cur_src;
          cur_dst <= dst_inc ? cur_dst + {25'b0, eng_beats, 2'b00} : cur_dst;
          rem     <= rem - {11'b0, eng_beats};
        end

        if (last_ok) begin
          busy       <= 1'b0;
          done_q     <= 1'b1;
          abort_pend <= 1'b0;
        end else if (eng_err) begin
          busy       <= 1'b0;
          err_q      <= 1'b1;
          err_wr_q   <= eng_err_wr;
          err_resp_q <= eng_err_resp;
          abort_pend <= 1'b0;
        end else if (fin_abort) begin
          busy       <= 1'b0;
          aborted_q  <= 1'b1;
          abort_pend <= 1'b0;
        end
      end
    end
  end

  assign stat = {rem, 9'b0, err_wr_q, err_resp_q, aborted_q, err_q, done_q, busy};

endmodule : dma_channel
