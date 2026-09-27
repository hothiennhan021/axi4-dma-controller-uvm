// -----------------------------------------------------------------------------
// dma_top - multi-channel DMA controller
//
//   APB3 slave  : configuration / status registers (dma_apb_regs)
//   AXI4 master : memory-to-memory burst engine   (dma_axi_engine)
//   irq         : level interrupt, |(INT_STATUS & INT_ENABLE)
//
// Channels are served round-robin at burst granularity. See docs/spec.md.
// -----------------------------------------------------------------------------
module dma_top #(
  parameter int unsigned NUM_CH = 4,
  parameter int unsigned ID_W   = 4
) (
  input  logic            clk,
  input  logic            rst_n,

  // APB3 slave
  input  logic            psel,
  input  logic            penable,
  input  logic            pwrite,
  input  logic [11:0]     paddr,
  input  logic [31:0]     pwdata,
  output logic [31:0]     prdata,
  output logic            pready,
  output logic            pslverr,

  // AXI4 master
  output logic [ID_W-1:0] m_axi_arid,
  output logic [31:0]     m_axi_araddr,
  output logic [7:0]      m_axi_arlen,
  output logic [2:0]      m_axi_arsize,
  output logic [1:0]      m_axi_arburst,
  output logic            m_axi_arvalid,
  input  logic            m_axi_arready,
  input  logic [ID_W-1:0] m_axi_rid,
  input  logic [31:0]     m_axi_rdata,
  input  logic [1:0]      m_axi_rresp,
  input  logic            m_axi_rlast,
  input  logic            m_axi_rvalid,
  output logic            m_axi_rready,
  output logic [ID_W-1:0] m_axi_awid,
  output logic [31:0]     m_axi_awaddr,
  output logic [7:0]      m_axi_awlen,
  output logic [2:0]      m_axi_awsize,
  output logic [1:0]      m_axi_awburst,
  output logic            m_axi_awvalid,
  input  logic            m_axi_awready,
  output logic [31:0]     m_axi_wdata,
  output logic [3:0]      m_axi_wstrb,
  output logic            m_axi_wlast,
  output logic            m_axi_wvalid,
  input  logic            m_axi_wready,
  input  logic [ID_W-1:0] m_axi_bid,
  input  logic [1:0]      m_axi_bresp,
  input  logic            m_axi_bvalid,
  output logic            m_axi_bready,

  // Interrupt
  output logic            irq
);

  import dma_pkg::*;

  localparam int unsigned IW = (NUM_CH > 1) ? $clog2(NUM_CH) : 1;

  // Parameter sanity (elaboration time)
  if (NUM_CH < 2 || NUM_CH > MAX_CH) begin : g_bad_num_ch
    $error("dma_top: NUM_CH must be in [2, %0d]", MAX_CH);
  end
  if (ID_W < IW) begin : g_bad_id_w
    $error("dma_top: ID_W too small to carry the channel number");
  end

  // ---------------------------------------------------------------------------
  // Register file
  // ---------------------------------------------------------------------------
  logic                    glb_en;
  logic [31:0]             int_enable, int_clr;
  logic [31:0]             int_status;
  logic [NUM_CH-1:0][5:0]  ch_cfg;
  logic [NUM_CH-1:0][31:0] ch_src, ch_dst;
  logic [NUM_CH-1:0][15:0] ch_len;
  logic [NUM_CH-1:0]       ch_start, ch_abort;
  logic [NUM_CH-1:0][31:0] ch_stat;

  dma_apb_regs #(.NUM_CH(NUM_CH)) u_regs (
    .clk        (clk),
    .rst_n      (rst_n),
    .psel       (psel),
    .penable    (penable),
    .pwrite     (pwrite),
    .paddr      (paddr),
    .pwdata     (pwdata),
    .prdata     (prdata),
    .pready     (pready),
    .pslverr    (pslverr),
    .glb_en     (glb_en),
    .int_enable (int_enable),
    .int_clr    (int_clr),
    .ch_cfg     (ch_cfg),
    .ch_src     (ch_src),
    .ch_dst     (ch_dst),
    .ch_len     (ch_len),
    .ch_start   (ch_start),
    .ch_abort   (ch_abort),
    .int_status (int_status),
    .ch_stat    (ch_stat)
  );

  // ---------------------------------------------------------------------------
  // Engine <-> channel plumbing
  // ---------------------------------------------------------------------------
  logic            eng_idle, eng_active;
  logic [IW-1:0]   eng_ch;
  logic            res_ok, res_err, res_err_wr;
  logic [1:0]      res_resp;
  logic [4:0]      res_beats;

  logic [NUM_CH-1:0]        ch_req;
  logic [NUM_CH-1:0][31:0]  ch_cur_src, ch_cur_dst;
  logic [NUM_CH-1:0][15:0]  ch_rem;
  logic [NUM_CH-1:0][3:0]   ch_max_burst;
  logic [NUM_CH-1:0]        ch_src_inc, ch_dst_inc;
  logic [NUM_CH-1:0]        ch_fin_done, ch_fin_err;

  for (genvar c = 0; c < NUM_CH; c++) begin : g_ch
    logic sel;
    assign sel = eng_active && (eng_ch == IW'(c));

    dma_channel u_ch (
      .clk          (clk),
      .rst_n        (rst_n),
      .cfg          (ch_cfg[c]),
      .src          (ch_src[c]),
      .dst          (ch_dst[c]),
      .len          (ch_len[c]),
      .start_req    (ch_start[c]),
      .abort_req    (ch_abort[c]),
      .eng_sel      (sel),
      .eng_done     (sel & res_ok),
      .eng_err      (sel & res_err),
      .eng_err_wr   (res_err_wr),
      .eng_err_resp (res_resp),
      .eng_beats    (res_beats),
      .req          (ch_req[c]),
      .cur_src      (ch_cur_src[c]),
      .cur_dst      (ch_cur_dst[c]),
      .rem          (ch_rem[c]),
      .max_burst    (ch_max_burst[c]),
      .src_inc      (ch_src_inc[c]),
      .dst_inc      (ch_dst_inc[c]),
      .stat         (ch_stat[c]),
      .fin_done     (ch_fin_done[c]),
      .fin_err      (ch_fin_err[c])
    );
  end

  // ---------------------------------------------------------------------------
  // Arbitration
  // ---------------------------------------------------------------------------
  logic          gnt_valid;
  logic [IW-1:0] gnt_idx;

  dma_rr_arbiter #(.N(NUM_CH)) u_arb (
    .clk       (clk),
    .rst_n     (rst_n),
    .allow     (glb_en & eng_idle),
    .req       (ch_req),
    .gnt_valid (gnt_valid),
    .gnt_idx   (gnt_idx)
  );

  dma_axi_engine #(.NUM_CH(NUM_CH), .ID_W(ID_W)) u_eng (
    .clk           (clk),
    .rst_n         (rst_n),
    .gnt_valid     (gnt_valid),
    .gnt_idx       (gnt_idx),
    .d_src         (ch_cur_src[gnt_idx]),
    .d_dst         (ch_cur_dst[gnt_idx]),
    .d_rem         (ch_rem[gnt_idx]),
    .d_max_burst   (ch_max_burst[gnt_idx]),
    .d_src_inc     (ch_src_inc[gnt_idx]),
    .d_dst_inc     (ch_dst_inc[gnt_idx]),
    .idle          (eng_idle),
    .active        (eng_active),
    .cur_ch        (eng_ch),
    .res_ok        (res_ok),
    .res_err       (res_err),
    .res_err_wr    (res_err_wr),
    .res_resp      (res_resp),
    .res_beats     (res_beats),
    .m_axi_arid    (m_axi_arid),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rid     (m_axi_rid),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready),
    .m_axi_awid    (m_axi_awid),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_bid     (m_axi_bid),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready)
  );

  // ---------------------------------------------------------------------------
  // Interrupt status (W1C, hardware set has priority over software clear)
  // ---------------------------------------------------------------------------
  logic [31:0] int_set;

  always_comb begin
    int_set = '0;
    for (int c = 0; c < NUM_CH; c++) begin
      int_set[c]               = ch_fin_done[c];
      int_set[INT_ERR_LSB + c] = ch_fin_err[c];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) int_status <= '0;
    else        int_status <= (int_status & ~int_clr) | int_set;
  end

  assign irq = |(int_status & int_enable);

endmodule : dma_top
