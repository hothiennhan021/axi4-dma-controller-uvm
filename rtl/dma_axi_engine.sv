// -----------------------------------------------------------------------------
// dma_axi_engine - AXI4 master burst engine (one burst in flight)
//
// For every grant the engine
//   1. computes the burst length
//        beats = min(REMAIN, MAX_BURST+1,
//                    words to the next 4 KB boundary of SRC  (if SRC_INC),
//                    words to the next 4 KB boundary of DST  (if DST_INC))
//      so no INCR burst ever crosses a 4 KB boundary,
//   2. issues AR and collects the R beats into a 16-entry buffer,
//   3. if every R beat was OKAY, issues AW and W (AWVALID and WVALID are
//      raised together) and waits for B.
// A read error suppresses the write burst. The result is reported to the
// owning channel in the cycle of the terminating handshake (last R beat on a
// read error, B otherwise).
//
// All AXI outputs are decoded from flops (no input-to-output combinational
// paths). ARID/AWID carry the channel number.
// -----------------------------------------------------------------------------
module dma_axi_engine #(
  parameter int unsigned NUM_CH = 4,
  parameter int unsigned ID_W   = 4,
  parameter int unsigned IW     = (NUM_CH > 1) ? $clog2(NUM_CH) : 1   // derived
) (
  input  logic            clk,
  input  logic            rst_n,

  // Grant and descriptor of the granted channel
  input  logic            gnt_valid,
  input  logic [IW-1:0]   gnt_idx,
  input  logic [31:0]     d_src,
  input  logic [31:0]     d_dst,
  input  logic [15:0]     d_rem,
  input  logic [3:0]      d_max_burst,
  input  logic            d_src_inc,
  input  logic            d_dst_inc,

  output logic            idle,
  output logic            active,
  output logic [IW-1:0]   cur_ch,

  // Burst result (single-cycle pulses)
  output logic            res_ok,
  output logic            res_err,
  output logic            res_err_wr,
  output logic [1:0]      res_resp,
  output logic [4:0]      res_beats,

  // AXI4 master - read address
  output logic [ID_W-1:0] m_axi_arid,
  output logic [31:0]     m_axi_araddr,
  output logic [7:0]      m_axi_arlen,
  output logic [2:0]      m_axi_arsize,
  output logic [1:0]      m_axi_arburst,
  output logic            m_axi_arvalid,
  input  logic            m_axi_arready,
  // read data
  input  logic [ID_W-1:0] m_axi_rid,
  input  logic [31:0]     m_axi_rdata,
  input  logic [1:0]      m_axi_rresp,
  input  logic            m_axi_rlast,
  input  logic            m_axi_rvalid,
  output logic            m_axi_rready,
  // write address
  output logic [ID_W-1:0] m_axi_awid,
  output logic [31:0]     m_axi_awaddr,
  output logic [7:0]      m_axi_awlen,
  output logic [2:0]      m_axi_awsize,
  output logic [1:0]      m_axi_awburst,
  output logic            m_axi_awvalid,
  input  logic            m_axi_awready,
  // write data
  output logic [31:0]     m_axi_wdata,
  output logic [3:0]      m_axi_wstrb,
  output logic            m_axi_wlast,
  output logic            m_axi_wvalid,
  input  logic            m_axi_wready,
  // write response
  input  logic [ID_W-1:0] m_axi_bid,
  input  logic [1:0]      m_axi_bresp,
  input  logic            m_axi_bvalid,
  output logic            m_axi_bready
);

  import dma_pkg::*;

  typedef enum logic [2:0] {S_IDLE, S_AR, S_R, S_W, S_B} state_t;

  state_t      state;
  logic [31:0] araddr_q, awaddr_q;
  logic [1:0]  arburst_q, awburst_q;
  logic [3:0]  len_q;            // beats - 1
  logic [3:0]  rcnt, wcnt;
  logic        rd_err_q;
  logic [1:0]  rd_resp_q;
  logic        aw_pend, w_pend;
  logic [31:0] dbuf [MAX_BEATS];

  // ---------------------------------------------------------------------------
  // Burst length for the granted channel
  // ---------------------------------------------------------------------------
  logic [10:0] src_room, dst_room;
  logic [15:0] beats_c;

  always_comb begin
    src_room = 11'd1024 - {1'b0, d_src[11:2]};
    dst_room = 11'd1024 - {1'b0, d_dst[11:2]};
    beats_c  = d_rem;
    if (beats_c > ({12'b0, d_max_burst} + 16'd1)) beats_c = {12'b0, d_max_burst} + 16'd1;
    if (d_src_inc && (beats_c > {5'b0, src_room})) beats_c = {5'b0, src_room};
    if (d_dst_inc && (beats_c > {5'b0, dst_room})) beats_c = {5'b0, dst_room};
  end

  // ---------------------------------------------------------------------------
  // Handshakes
  // ---------------------------------------------------------------------------
  logic ar_hs, r_hs, aw_hs, w_hs, b_hs;
  logic r_err_beat, rd_fail;

  assign ar_hs      = m_axi_arvalid & m_axi_arready;
  assign r_hs       = m_axi_rvalid  & m_axi_rready;
  assign aw_hs      = m_axi_awvalid & m_axi_awready;
  assign w_hs       = m_axi_wvalid  & m_axi_wready;
  assign b_hs       = m_axi_bvalid  & m_axi_bready;
  assign r_err_beat = m_axi_rresp[1];            // SLVERR or DECERR
  assign rd_fail    = rd_err_q | r_err_beat;

  // ---------------------------------------------------------------------------
  // FSM
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= S_IDLE;
      cur_ch    <= '0;
      araddr_q  <= '0;
      awaddr_q  <= '0;
      arburst_q <= AXI_BURST_INCR;
      awburst_q <= AXI_BURST_INCR;
      len_q     <= '0;
      rcnt      <= '0;
      wcnt      <= '0;
      rd_err_q  <= 1'b0;
      rd_resp_q <= AXI_RESP_OKAY;
      aw_pend   <= 1'b0;
      w_pend    <= 1'b0;
    end else begin
      case (state)
        S_IDLE: begin
          if (gnt_valid) begin
            cur_ch    <= gnt_idx;
            araddr_q  <= d_src;
            awaddr_q  <= d_dst;
            arburst_q <= d_src_inc ? AXI_BURST_INCR : AXI_BURST_FIXED;
            awburst_q <= d_dst_inc ? AXI_BURST_INCR : AXI_BURST_FIXED;
            len_q     <= 4'(beats_c - 16'd1);
            rcnt      <= '0;
            wcnt      <= '0;
            rd_err_q  <= 1'b0;
            rd_resp_q <= AXI_RESP_OKAY;
            state     <= S_AR;
          end
        end

        S_AR: begin
          if (ar_hs) state <= S_R;
        end

        S_R: begin
          if (r_hs) begin
            if (rcnt != 4'hF) rcnt <= rcnt + 4'd1;
            if (r_err_beat && !rd_err_q) begin
              rd_err_q  <= 1'b1;
              rd_resp_q <= m_axi_rresp;
            end
            if (m_axi_rlast) begin
              if (rd_fail) begin
                state <= S_IDLE;
              end else begin
                state   <= S_W;
                aw_pend <= 1'b1;
                w_pend  <= 1'b1;
              end
            end
          end
        end

        S_W: begin
          if (aw_hs) aw_pend <= 1'b0;
          if (w_hs) begin
            if (m_axi_wlast) w_pend <= 1'b0;
            else             wcnt   <= wcnt + 4'd1;
          end
          if ((!aw_pend || aw_hs) && (!w_pend || (w_hs && m_axi_wlast))) state <= S_B;
        end

        S_B: begin
          if (b_hs) state <= S_IDLE;
        end

        // unreachable (all encodings of state_t are handled above)
        /* verilator coverage_off */
        default: state <= S_IDLE;
        /* verilator coverage_on */
      endcase
    end
  end

  // Read data buffer (data path only, no reset needed)
  always_ff @(posedge clk) begin
    if (state == S_R && r_hs) dbuf[rcnt] <= m_axi_rdata;
  end

  // ---------------------------------------------------------------------------
  // Outputs
  // ---------------------------------------------------------------------------
  assign idle   = (state == S_IDLE);
  assign active = ~idle;

  assign m_axi_arid    = ID_W'(cur_ch);
  assign m_axi_araddr  = araddr_q;
  assign m_axi_arlen   = {4'b0, len_q};
  assign m_axi_arsize  = AXI_SIZE_4B;
  assign m_axi_arburst = arburst_q;
  assign m_axi_arvalid = (state == S_AR);
  assign m_axi_rready  = (state == S_R);

  assign m_axi_awid    = ID_W'(cur_ch);
  assign m_axi_awaddr  = awaddr_q;
  assign m_axi_awlen   = {4'b0, len_q};
  assign m_axi_awsize  = AXI_SIZE_4B;
  assign m_axi_awburst = awburst_q;
  assign m_axi_awvalid = (state == S_W) & aw_pend;
  assign m_axi_wdata   = dbuf[wcnt];
  assign m_axi_wstrb   = 4'hF;
  assign m_axi_wlast   = (wcnt == len_q);
  assign m_axi_wvalid  = (state == S_W) & w_pend;
  assign m_axi_bready  = (state == S_B);

  assign res_ok     = (state == S_B) & b_hs & ~m_axi_bresp[1];
  assign res_err    = ((state == S_R) & r_hs & m_axi_rlast & rd_fail) |
                      ((state == S_B) & b_hs & m_axi_bresp[1]);
  assign res_err_wr = (state == S_B);
  assign res_resp   = (state == S_B) ? m_axi_bresp :
                      (rd_err_q ? rd_resp_q : m_axi_rresp);
  assign res_beats  = {1'b0, len_q} + 5'd1;

  // RID/BID are not needed with a single burst in flight; the testbench
  // checks that the slave returns the right ID.
  logic unused_ok;
  assign unused_ok = ^{m_axi_rid, m_axi_bid};

endmodule : dma_axi_engine
