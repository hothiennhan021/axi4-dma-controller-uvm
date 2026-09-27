// -----------------------------------------------------------------------------
// Protocol assertions, bound into dma_top (see dma_bind.sv)
//
//   axi4_protocol_sva : AXI4 handshake rules for both directions (DUT master
//                       outputs and testbench slave responses), DUT burst
//                       restrictions (size, length, alignment, 4 KB) and
//                       outstanding-transaction limits
//   apb_protocol_sva  : APB3 phase sequencing and response rules
//   dma_irq_sva       : irq output vs. INT_STATUS / INT_ENABLE
//
// Failures are reported through `uvm_error so that every simulator counts
// them in the UVM report summary and the test fails.
// -----------------------------------------------------------------------------

module axi4_protocol_sva #(
  parameter int unsigned ID_W = 4
) (
  input logic            clk,
  input logic            rst_n,
  input logic [ID_W-1:0] m_axi_arid,
  input logic [31:0]     m_axi_araddr,
  input logic [7:0]      m_axi_arlen,
  input logic [2:0]      m_axi_arsize,
  input logic [1:0]      m_axi_arburst,
  input logic            m_axi_arvalid,
  input logic            m_axi_arready,
  input logic [ID_W-1:0] m_axi_rid,
  input logic [31:0]     m_axi_rdata,
  input logic [1:0]      m_axi_rresp,
  input logic            m_axi_rlast,
  input logic            m_axi_rvalid,
  input logic            m_axi_rready,
  input logic [ID_W-1:0] m_axi_awid,
  input logic [31:0]     m_axi_awaddr,
  input logic [7:0]      m_axi_awlen,
  input logic [2:0]      m_axi_awsize,
  input logic [1:0]      m_axi_awburst,
  input logic            m_axi_awvalid,
  input logic            m_axi_awready,
  input logic [31:0]     m_axi_wdata,
  input logic [3:0]      m_axi_wstrb,
  input logic            m_axi_wlast,
  input logic            m_axi_wvalid,
  input logic            m_axi_wready,
  input logic [ID_W-1:0] m_axi_bid,
  input logic [1:0]      m_axi_bresp,
  input logic            m_axi_bvalid,
  input logic            m_axi_bready
);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Outstanding-burst bookkeeping
  logic [3:0] rd_out, aw_out, w_out;
  logic ar_hs, rl_hs, aw_hs, wl_hs, b_hs;
  assign ar_hs = m_axi_arvalid & m_axi_arready;
  assign rl_hs = m_axi_rvalid & m_axi_rready & m_axi_rlast;
  assign aw_hs = m_axi_awvalid & m_axi_awready;
  assign wl_hs = m_axi_wvalid & m_axi_wready & m_axi_wlast;
  assign b_hs  = m_axi_bvalid & m_axi_bready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_out <= '0;
      aw_out <= '0;
      w_out  <= '0;
    end else begin
      rd_out <= rd_out + {3'b0, ar_hs} - {3'b0, rl_hs};
      aw_out <= aw_out + {3'b0, aw_hs} - {3'b0, b_hs};
      w_out  <= w_out  + {3'b0, wl_hs} - {3'b0, b_hs};
    end
  end

  // --- reset ------------------------------------------------------------------
  a_valid_low_in_reset: assert property (@(posedge clk)
      !rst_n |-> !m_axi_arvalid && !m_axi_awvalid && !m_axi_wvalid)
    else `uvm_error("AXI_SVA", "master VALID asserted during reset")

  // --- read address channel -----------------------------------------------------
  a_ar_hold: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_arvalid && !m_axi_arready |=> m_axi_arvalid)
    else `uvm_error("AXI_SVA", "ARVALID dropped before ARREADY")
  a_ar_stable: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_arvalid && !m_axi_arready |=>
        $stable({m_axi_arid, m_axi_araddr, m_axi_arlen, m_axi_arsize, m_axi_arburst}))
    else `uvm_error("AXI_SVA", "AR payload changed while waiting for ARREADY")
  a_ar_shape: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_arvalid |-> m_axi_arlen <= 8'd15 && m_axi_arsize == 3'b010 &&
                        m_axi_arburst inside {2'b00, 2'b01} && m_axi_araddr[1:0] == 2'b00)
    else `uvm_error("AXI_SVA", $sformatf("illegal AR: len=%0d size=%0d burst=%0d addr=0x%08h",
                                         m_axi_arlen, m_axi_arsize, m_axi_arburst, m_axi_araddr))
  a_ar_4k: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_arvalid && m_axi_arburst == 2'b01 |->
        ({1'b0, m_axi_araddr[11:0]} + {3'b0, m_axi_arlen, 2'b00} + 13'd4) <= 13'd4096)
    else `uvm_error("AXI_SVA", $sformatf("read burst crosses 4KB: addr=0x%08h len=%0d", m_axi_araddr, m_axi_arlen))
  a_ar_single_outstanding: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_arvalid |-> rd_out == 0)
    else `uvm_error("AXI_SVA", "second read burst issued while one is outstanding")

  // --- read data channel (slave side) ----------------------------------------------
  a_r_hold: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_rvalid && !m_axi_rready |=> m_axi_rvalid)
    else `uvm_error("AXI_SVA", "RVALID dropped before RREADY")
  a_r_stable: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_rvalid && !m_axi_rready |=> $stable({m_axi_rid, m_axi_rdata, m_axi_rresp, m_axi_rlast}))
    else `uvm_error("AXI_SVA", "R payload changed while waiting for RREADY")
  a_r_after_ar: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_rvalid |-> rd_out != 0)
    else `uvm_error("AXI_SVA", "RVALID without an outstanding read burst")

  // --- write address channel ----------------------------------------------------------
  a_aw_hold: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_awvalid && !m_axi_awready |=> m_axi_awvalid)
    else `uvm_error("AXI_SVA", "AWVALID dropped before AWREADY")
  a_aw_stable: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_awvalid && !m_axi_awready |=>
        $stable({m_axi_awid, m_axi_awaddr, m_axi_awlen, m_axi_awsize, m_axi_awburst}))
    else `uvm_error("AXI_SVA", "AW payload changed while waiting for AWREADY")
  a_aw_shape: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_awvalid |-> m_axi_awlen <= 8'd15 && m_axi_awsize == 3'b010 &&
                        m_axi_awburst inside {2'b00, 2'b01} && m_axi_awaddr[1:0] == 2'b00)
    else `uvm_error("AXI_SVA", $sformatf("illegal AW: len=%0d size=%0d burst=%0d addr=0x%08h",
                                         m_axi_awlen, m_axi_awsize, m_axi_awburst, m_axi_awaddr))
  a_aw_4k: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_awvalid && m_axi_awburst == 2'b01 |->
        ({1'b0, m_axi_awaddr[11:0]} + {3'b0, m_axi_awlen, 2'b00} + 13'd4) <= 13'd4096)
    else `uvm_error("AXI_SVA", $sformatf("write burst crosses 4KB: addr=0x%08h len=%0d", m_axi_awaddr, m_axi_awlen))
  a_aw_single_outstanding: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_awvalid |-> aw_out == 0)
    else `uvm_error("AXI_SVA", "second write burst issued while one is outstanding")

  // --- write data channel ----------------------------------------------------------------
  a_w_hold: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_wvalid && !m_axi_wready |=> m_axi_wvalid)
    else `uvm_error("AXI_SVA", "WVALID dropped before WREADY")
  a_w_stable: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_wvalid && !m_axi_wready |=> $stable({m_axi_wdata, m_axi_wstrb, m_axi_wlast}))
    else `uvm_error("AXI_SVA", "W payload changed while waiting for WREADY")
  a_w_strb: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_wvalid |-> m_axi_wstrb == 4'hF)
    else `uvm_error("AXI_SVA", "partial WSTRB on a full-word transfer")

  // --- write response channel (slave side) -------------------------------------------------
  a_b_hold: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_bvalid && !m_axi_bready |=> m_axi_bvalid)
    else `uvm_error("AXI_SVA", "BVALID dropped before BREADY")
  a_b_stable: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_bvalid && !m_axi_bready |=> $stable({m_axi_bid, m_axi_bresp}))
    else `uvm_error("AXI_SVA", "B payload changed while waiting for BREADY")
  a_b_after_aw_w: assert property (@(posedge clk) disable iff (!rst_n)
      m_axi_bvalid |-> aw_out != 0 && w_out != 0)
    else `uvm_error("AXI_SVA", "BVALID before both AW and the last W beat were accepted")

  // --- coverage of interesting protocol situations ------------------------------------------
  c_ar_wait:      cover property (@(posedge clk) disable iff (!rst_n) m_axi_arvalid && !m_axi_arready);
  c_ar_len16:     cover property (@(posedge clk) disable iff (!rst_n) ar_hs && m_axi_arlen == 8'd15);
  c_ar_fixed:     cover property (@(posedge clk) disable iff (!rst_n) ar_hs && m_axi_arburst == 2'b00);
  c_ar_4k_end:    cover property (@(posedge clk) disable iff (!rst_n)
                      ar_hs && m_axi_arburst == 2'b01 &&
                      ({1'b0, m_axi_araddr[11:0]} + {3'b0, m_axi_arlen, 2'b00} + 13'd4) == 13'd4096);
  c_r_b2b:        cover property (@(posedge clk) disable iff (!rst_n)
                      m_axi_rvalid && m_axi_rready ##1 m_axi_rvalid && m_axi_rready);
  c_w_before_aw:  cover property (@(posedge clk) disable iff (!rst_n)
                      m_axi_wvalid && m_axi_wready && m_axi_awvalid && !m_axi_awready);
  c_aw_before_w:  cover property (@(posedge clk) disable iff (!rst_n)
                      aw_hs && m_axi_wvalid && !m_axi_wready);
  c_r_err:        cover property (@(posedge clk) disable iff (!rst_n) m_axi_rvalid && m_axi_rresp[1]);
  c_b_err:        cover property (@(posedge clk) disable iff (!rst_n) b_hs && m_axi_bresp[1]);

endmodule : axi4_protocol_sva


module apb_protocol_sva (
  input logic        clk,
  input logic        rst_n,
  input logic        psel,
  input logic        penable,
  input logic        pwrite,
  input logic [11:0] paddr,
  input logic [31:0] pwdata,
  input logic [31:0] prdata,
  input logic        pready,
  input logic        pslverr
);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  a_setup_then_access: assert property (@(posedge clk) disable iff (!rst_n)
      psel && !penable |=> psel && penable)
    else `uvm_error("APB_SVA", "SETUP phase not followed by ACCESS phase")
  a_enable_needs_sel: assert property (@(posedge clk) disable iff (!rst_n)
      penable |-> psel)
    else `uvm_error("APB_SVA", "PENABLE without PSEL")
  a_stable_in_access: assert property (@(posedge clk) disable iff (!rst_n)
      psel && !(penable && pready) |=> $stable({paddr, pwrite, pwdata}))
    else `uvm_error("APB_SVA", "address/control/data changed during a transfer")
  a_zero_wait: assert property (@(posedge clk) disable iff (!rst_n)
      psel && penable |-> pready)
    else `uvm_error("APB_SVA", "DUT inserted a wait state (design is zero-wait)")
  a_slverr_only_in_access: assert property (@(posedge clk) disable iff (!rst_n)
      pslverr |-> psel && penable)
    else `uvm_error("APB_SVA", "PSLVERR outside the ACCESS phase")
  a_prdata_zero_on_err: assert property (@(posedge clk) disable iff (!rst_n)
      psel && penable && !pwrite && pslverr |-> prdata == 32'h0)
    else `uvm_error("APB_SVA", "PRDATA not zero on an erroring read")

  c_b2b:    cover property (@(posedge clk) disable iff (!rst_n) psel && penable ##1 psel && !penable);
  c_slverr: cover property (@(posedge clk) disable iff (!rst_n) psel && penable && pslverr);

endmodule : apb_protocol_sva


module dma_irq_sva (
  input logic        clk,
  input logic        rst_n,
  input logic [31:0] int_status,
  input logic [31:0] int_enable,
  input logic        irq
);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  a_irq: assert property (@(posedge clk) disable iff (!rst_n)
      irq == |(int_status & int_enable))
    else `uvm_error("IRQ_SVA", "irq does not match |(INT_STATUS & INT_ENABLE)")
  a_irq_reset: assert property (@(posedge clk) !rst_n |-> !irq)
    else `uvm_error("IRQ_SVA", "irq asserted during reset")

endmodule : dma_irq_sva
