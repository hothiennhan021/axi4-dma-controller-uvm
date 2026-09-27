// -----------------------------------------------------------------------------
// dma_xfer - one channel transfer descriptor (+ expected data)
//
// Address windows keep channels apart so concurrent transfers never overlap:
//   channel c source      : 0x1000_0000 + c * 0x0100_0000 (16 MB)
//   channel c destination : 0x8000_0000 + c * 0x0100_0000 (16 MB)
//   channel c FIFO ports  : 0x4000_0000 + c * 0x0000_1000
// -----------------------------------------------------------------------------
class dma_xfer extends uvm_object;

  `uvm_object_utils(dma_xfer)

  int unsigned    ch;
  rand bit [31:0] src;
  rand bit [31:0] dst;
  rand bit [15:0] len;
  rand bit [3:0]  max_burst;
  rand bit        src_inc;
  rand bit        dst_inc;
  rand bit        edge_4k;       // bias addresses to just below a 4 KB boundary

  // filled by dma_base_vseq::snapshot() right before START
  bit [31:0]      exp_data[$];
  bit             src_fifo;
  bit             dst_fifo;
  int unsigned    sink0;         // sink depth of a destination FIFO before START
  bit [31:0]      guard_lo, guard_hi;

  constraint c_align    { src[1:0] == 2'b00; dst[1:0] == 2'b00; }
  constraint c_inc      { soft src_inc == 1'b1; soft dst_inc == 1'b1; }
  constraint c_edge     { edge_4k dist {1'b0 := 3, 1'b1 := 1}; }
  constraint c_src_win  {
    src inside {[32'h1000_0000 + ch * 32'h0100_0000 + 32'h10 : 32'h1000_0000 + ch * 32'h0100_0000 + 32'h00F0_0000]};
  }
  constraint c_dst_win  {
    dst inside {[32'h8000_0000 + ch * 32'h0100_0000 + 32'h10 : 32'h8000_0000 + ch * 32'h0100_0000 + 32'h00F0_0000]};
  }
  constraint c_edge_addr {
    edge_4k -> (src[11:0] inside {[12'hF00 : 12'hFFC]} || dst[11:0] inside {[12'hF00 : 12'hFFC]});
  }

  function new(string name = "dma_xfer");
    super.new(name);
  endfunction

  static function bit [31:0] src_base(int unsigned c);
    return 32'h1000_0000 + c * 32'h0100_0000;
  endfunction

  static function bit [31:0] dst_base(int unsigned c);
    return 32'h8000_0000 + c * 32'h0100_0000;
  endfunction

  static function bit [31:0] fifo_base(int unsigned c);
    return 32'h4000_0000 + c * 32'h0000_1000;
  endfunction

  function bit [5:0] cfg_word();
    return {dst_inc, src_inc, max_burst};
  endfunction

  virtual function string convert2string();
    return $sformatf("ch%0d src=0x%08h%s dst=0x%08h%s len=%0d max_burst=%0d",
                     ch, src, src_inc ? "" : "(fixed)", dst, dst_inc ? "" : "(fixed)", len, max_burst);
  endfunction

endclass : dma_xfer
