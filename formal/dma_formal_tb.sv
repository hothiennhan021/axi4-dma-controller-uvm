// -----------------------------------------------------------------------------
// dma_formal_tb - SymbiYosys harness for dma_top
//
// The APB master and the AXI4 slave are unconstrained inputs, restricted only
// by protocol assumptions. The assertions are the AXI4 master rules the DUT
// must obey whatever the environment does:
//   * VALID held until READY, payload stable while waiting (AR, AW, W)
//   * AxLEN <= 15, AxSIZE = 4 bytes, AxBURST in {FIXED, INCR}, aligned
//   * no INCR burst crosses a 4 KB boundary
//   * WSTRB = 0xF, WLAST exactly on beat AWLEN+1
//   * at most one read and one write burst outstanding
//   * PSLVERR only in the APB access phase, PRDATA = 0 on an erroring read
// Cover statements show that a transfer can complete and raise irq, and that
// reset can hit a burst in flight. Reset may be asserted at any cycle.
//
// Written with immediate assertions in clocked always blocks (the subset the
// open-source Yosys front end supports).
// -----------------------------------------------------------------------------
module dma_formal_tb (
  input logic        clk,
  input logic        rst_req,      // free: reset may be re-asserted at any time
  // APB master (free)
  input logic        psel,
  input logic        penable,
  input logic        pwrite,
  input logic [11:0] paddr,
  input logic [31:0] pwdata,
  // AXI slave (free)
  input logic        arready,
  input logic [3:0]  rid,
  input logic [31:0] rdata,
  input logic [1:0]  rresp,
  input logic        rlast,
  input logic        rvalid,
  input logic        awready,
  input logic        wready,
  input logic [3:0]  bid,
  input logic [1:0]  bresp,
  input logic        bvalid
);

  // ---------------------------------------------------------------------------
  // Reset: low for the first cycles, afterwards asserted whenever the solver
  // chooses (rst_req), so every property must also hold around a reset in the
  // middle of a transfer.
  // ---------------------------------------------------------------------------
  reg [1:0] rst_cnt = 2'd0;
  wire      rst_n = (rst_cnt == 2'd3) && !rst_req;
  always @(posedge clk) if (rst_cnt != 2'd3) rst_cnt <= rst_cnt + 2'd1;

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  wire [31:0] prdata;
  wire        pready, pslverr;
  wire [3:0]  arid, awid;
  wire [31:0] araddr, awaddr, wdata;
  wire [7:0]  arlen, awlen;
  wire [2:0]  arsize, awsize;
  wire [1:0]  arburst, awburst;
  wire        arvalid, rready, awvalid, wvalid, wlast, bready, irq;
  wire [3:0]  wstrb;

  dma_top #(.NUM_CH(4), .ID_W(4)) u_dut (
    .clk(clk), .rst_n(rst_n),
    .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
    .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
    .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
    .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
    .m_axi_rvalid(rvalid), .m_axi_rready(rready),
    .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
    .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
    .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid),
    .m_axi_wready(wready),
    .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
    .irq(irq)
  );

  // ---------------------------------------------------------------------------
  // Transaction bookkeeping
  // ---------------------------------------------------------------------------
  wire ar_hs = arvalid & arready;
  wire r_hs  = rvalid & rready;
  wire aw_hs = awvalid & awready;
  wire w_hs  = wvalid & wready;
  wire b_hs  = bvalid & bready;

  reg       rd_out;           // read burst outstanding
  reg [7:0] rd_len, rd_beat;
  reg [3:0] rd_id;
  reg       aw_done, w_done;  // write burst: address / all data accepted
  reg [7:0] w_beat;
  reg [3:0] wr_id;

  always @(posedge clk) begin
    if (!rst_n) begin
      rd_out  <= 1'b0;
      rd_beat <= 8'd0;
      aw_done <= 1'b0;
      w_done  <= 1'b0;
      w_beat  <= 8'd0;
    end else begin
      if (ar_hs) begin
        rd_out  <= 1'b1;
        rd_len  <= arlen;
        rd_id   <= arid;
        rd_beat <= 8'd0;
      end
      if (r_hs) begin
        rd_beat <= rd_beat + 8'd1;
        if (rlast) rd_out <= 1'b0;
      end
      if (aw_hs) begin
        aw_done <= 1'b1;
        wr_id   <= awid;
      end
      if (w_hs) begin
        w_beat <= wlast ? 8'd0 : w_beat + 8'd1;
        if (wlast) w_done <= 1'b1;
      end
      if (b_hs) begin
        aw_done <= 1'b0;
        w_done  <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Environment assumptions
  // ---------------------------------------------------------------------------
  always @(*) begin
    if (!rst_n) begin
      assume(!psel && !penable);
      assume(!rvalid && !bvalid);
    end
    // APB
    if (penable) assume(psel);
    // AXI slave: R only for an outstanding read, with the right ID and RLAST
    if (rvalid) begin
      assume(rd_out);
      assume(rid == rd_id);
      assume(rlast == (rd_beat == rd_len));
      assume(rresp != 2'b01);              // no EXOKAY (no exclusive access)
    end
    // B only after the address and the last data beat were accepted
    if (bvalid) begin
      assume(aw_done && w_done);
      assume(bid == wr_id);
      assume(bresp != 2'b01);
    end
  end

  always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(rst_n)) begin
      // APB: SETUP is followed by ACCESS with stable address/control/data;
      // after ACCESS (PREADY is always 1) PENABLE drops
      if ($past(psel && !penable)) begin
        assume(psel && penable);
        assume(paddr == $past(paddr) && pwrite == $past(pwrite) && pwdata == $past(pwdata));
      end
      if ($past(psel && penable)) assume(!penable);
      // AXI slave VALIDs hold until READY with stable payload
      if ($past(rvalid && !rready)) begin
        assume(rvalid);
        assume(rdata == $past(rdata) && rresp == $past(rresp) && rlast == $past(rlast) && rid == $past(rid));
      end
      if ($past(bvalid && !bready)) begin
        assume(bvalid);
        assume(bresp == $past(bresp) && bid == $past(bid));
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Assertions on the DUT
  // ---------------------------------------------------------------------------
  wire [12:0] ar_end = {1'b0, araddr[11:0]} + {3'b0, arlen, 2'b00} + 13'd4;
  wire [12:0] aw_end = {1'b0, awaddr[11:0]} + {3'b0, awlen, 2'b00} + 13'd4;

  always @(*) begin
    if (!rst_n) begin
      assert(!arvalid && !awvalid && !wvalid);
      assert(!irq);
    end else begin
      if (arvalid) begin
        assert(arlen <= 8'd15);
        assert(arsize == 3'b010);
        assert(arburst == 2'b00 || arburst == 2'b01);
        assert(araddr[1:0] == 2'b00);
        assert(arburst != 2'b01 || ar_end <= 13'd4096);
        assert(!rd_out);                               // one read burst at a time
      end
      if (awvalid) begin
        assert(awlen <= 8'd15);
        assert(awsize == 3'b010);
        assert(awburst == 2'b00 || awburst == 2'b01);
        assert(awaddr[1:0] == 2'b00);
        assert(awburst != 2'b01 || aw_end <= 13'd4096);
        assert(!aw_done);                              // one write burst at a time
      end
      if (wvalid) begin
        assert(wstrb == 4'hF);
        assert(!w_done);
        assert(wlast == (w_beat == awlen));
      end
      if (pslverr) assert(psel && penable);
      if (psel && penable && !pwrite && pslverr) assert(prdata == 32'h0);
      assert(pready);
    end
  end

  always @(posedge clk) begin
    if (f_past_valid && rst_n && $past(rst_n)) begin
      if ($past(arvalid && !arready)) begin
        assert(arvalid);
        assert(araddr == $past(araddr) && arlen == $past(arlen) && arburst == $past(arburst) &&
               arsize == $past(arsize) && arid == $past(arid));
      end
      if ($past(awvalid && !awready)) begin
        assert(awvalid);
        assert(awaddr == $past(awaddr) && awlen == $past(awlen) && awburst == $past(awburst) &&
               awsize == $past(awsize) && awid == $past(awid));
      end
      if ($past(wvalid && !wready)) begin
        assert(wvalid);
        assert(wdata == $past(wdata) && wlast == $past(wlast) && wstrb == $past(wstrb));
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Reachability
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n) begin
      cover(ar_hs && arlen == 8'd0);
      cover(b_hs && bresp == 2'b00);          // a burst completes
      cover(irq);                             // a channel finishes and interrupts
      cover(r_hs && rresp[1]);                // read error accepted
    end
    // reset arrives while a write burst is in flight
    if (f_past_valid) cover(!rst_n && $past(rst_n && wvalid));
  end

endmodule : dma_formal_tb
