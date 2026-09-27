// -----------------------------------------------------------------------------
// Testbench interfaces
//
// Drivers write the interface signals with non-blocking assignments right
// after a rising clock edge and monitors sample right after the rising edge,
// i.e. they see the values that were stable before the edge. This is
// race-free on every simulator without clocking blocks.
// -----------------------------------------------------------------------------

interface apb_if (input logic clk, input logic rst_n);
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [11:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;
endinterface : apb_if


interface axi_if (input logic clk, input logic rst_n);
  // read address
  logic [3:0]  arid;
  logic [31:0] araddr;
  logic [7:0]  arlen;
  logic [2:0]  arsize;
  logic [1:0]  arburst;
  logic        arvalid;
  logic        arready;
  // read data
  logic [3:0]  rid;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rlast;
  logic        rvalid;
  logic        rready;
  // write address
  logic [3:0]  awid;
  logic [31:0] awaddr;
  logic [7:0]  awlen;
  logic [2:0]  awsize;
  logic [1:0]  awburst;
  logic        awvalid;
  logic        awready;
  // write data
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wlast;
  logic        wvalid;
  logic        wready;
  // write response
  logic [3:0]  bid;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
endinterface : axi_if


interface irq_if (input logic clk, input logic rst_n);
  logic irq;
endinterface : irq_if
