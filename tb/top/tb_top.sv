// -----------------------------------------------------------------------------
// tb_top - clock, reset, DUT, interfaces, UVM start
//
// Plusargs:
//   +UVM_TESTNAME=<test>     test to run
//   +WAVES                   dump waves (Verilator: build with WAVES=1)
// -----------------------------------------------------------------------------
module tb_top;

  import uvm_pkg::*;
  import dma_test_pkg::*;

  localparam int unsigned NUM_CH = 4;
  localparam int unsigned ID_W   = 4;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #5ns clk = ~clk;            // 100 MHz

  initial begin
    rst_n = 1'b0;
    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
  end

  apb_if apb_bus (.clk(clk), .rst_n(rst_n));
  axi_if axi_bus (.clk(clk), .rst_n(rst_n));
  irq_if irq_bus (.clk(clk), .rst_n(rst_n));

  dma_top #(
    .NUM_CH (NUM_CH),
    .ID_W   (ID_W)
  ) u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .psel          (apb_bus.psel),
    .penable       (apb_bus.penable),
    .pwrite        (apb_bus.pwrite),
    .paddr         (apb_bus.paddr),
    .pwdata        (apb_bus.pwdata),
    .prdata        (apb_bus.prdata),
    .pready        (apb_bus.pready),
    .pslverr       (apb_bus.pslverr),
    .m_axi_arid    (axi_bus.arid),
    .m_axi_araddr  (axi_bus.araddr),
    .m_axi_arlen   (axi_bus.arlen),
    .m_axi_arsize  (axi_bus.arsize),
    .m_axi_arburst (axi_bus.arburst),
    .m_axi_arvalid (axi_bus.arvalid),
    .m_axi_arready (axi_bus.arready),
    .m_axi_rid     (axi_bus.rid),
    .m_axi_rdata   (axi_bus.rdata),
    .m_axi_rresp   (axi_bus.rresp),
    .m_axi_rlast   (axi_bus.rlast),
    .m_axi_rvalid  (axi_bus.rvalid),
    .m_axi_rready  (axi_bus.rready),
    .m_axi_awid    (axi_bus.awid),
    .m_axi_awaddr  (axi_bus.awaddr),
    .m_axi_awlen   (axi_bus.awlen),
    .m_axi_awsize  (axi_bus.awsize),
    .m_axi_awburst (axi_bus.awburst),
    .m_axi_awvalid (axi_bus.awvalid),
    .m_axi_awready (axi_bus.awready),
    .m_axi_wdata   (axi_bus.wdata),
    .m_axi_wstrb   (axi_bus.wstrb),
    .m_axi_wlast   (axi_bus.wlast),
    .m_axi_wvalid  (axi_bus.wvalid),
    .m_axi_wready  (axi_bus.wready),
    .m_axi_bid     (axi_bus.bid),
    .m_axi_bresp   (axi_bus.bresp),
    .m_axi_bvalid  (axi_bus.bvalid),
    .m_axi_bready  (axi_bus.bready),
    .irq           (irq_bus.irq)
  );

  initial begin
    uvm_config_db#(virtual apb_if)::set(null, "uvm_test_top", "apb_vif", apb_bus);
    uvm_config_db#(virtual axi_if)::set(null, "uvm_test_top", "axi_vif", axi_bus);
    uvm_config_db#(virtual irq_if)::set(null, "uvm_test_top", "irq_vif", irq_bus);
    run_test();
  end

  initial begin
    if ($test$plusargs("WAVES")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top);
    end
  end

endmodule : tb_top
