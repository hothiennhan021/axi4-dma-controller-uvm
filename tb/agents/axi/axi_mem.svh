// -----------------------------------------------------------------------------
// axi_mem - sparse 32-bit word memory behind the AXI slave
//
// * Never-written words read as a seed-dependent hash of their address, so
//   every source buffer has unique, reproducible content without any setup.
// * FIFO windows model a peripheral data register: every read of an address
//   inside a window pops the next value of a per-address stream, every write
//   is appended to a per-address sink queue. This lets fixed-address (FIXED
//   burst) transfers be checked for beat order, not just for the last value.
// -----------------------------------------------------------------------------
class axi_fifo_window extends uvm_object;
  `uvm_object_utils(axi_fifo_window)
  bit [31:0] lo;
  bit [31:0] hi;   // inclusive
  function new(string name = "axi_fifo_window");
    super.new(name);
  endfunction
endclass : axi_fifo_window


class axi_word_q extends uvm_object;
  `uvm_object_utils(axi_word_q)
  bit [31:0] q[$];
  function new(string name = "axi_word_q");
    super.new(name);
  endfunction
endclass : axi_word_q


class axi_mem extends uvm_object;

  `uvm_object_utils(axi_mem)

  bit [31:0]        salt;
  axi_fifo_window   fifo_windows[$];

  protected bit [31:0]   mem[bit [29:0]];
  protected int unsigned rd_count[bit [29:0]];
  protected axi_word_q   sink[bit [29:0]];

  function new(string name = "axi_mem");
    super.new(name);
    salt = $urandom();
  endfunction

  static function bit [31:0] hash32(bit [31:0] x);
    bit [31:0] h;
    h = x;
    h = h ^ (h >> 16);
    h = h * 32'h7feb352d;
    h = h ^ (h >> 15);
    h = h * 32'h846ca68b;
    h = h ^ (h >> 16);
    return h;
  endfunction

  // Content of a never-written word
  function bit [31:0] init_value(bit [31:0] a);
    return hash32({a[31:2], 2'b00} ^ salt);
  endfunction

  // n-th value popped from FIFO address a
  function bit [31:0] fifo_value(bit [31:0] a, int unsigned n);
    return hash32({a[31:2], 2'b00} ^ salt ^ 32'hF1F0_0000 ^ (32'(n) * 32'h9E37_79B9));
  endfunction

  function void add_fifo_window(bit [31:0] lo, bit [31:0] hi);
    axi_fifo_window w = axi_fifo_window::type_id::create("fifo_window");
    w.lo = lo;
    w.hi = hi;
    fifo_windows.push_back(w);
  endfunction

  function bit is_fifo(bit [31:0] a);
    foreach (fifo_windows[i]) if (a >= fifo_windows[i].lo && a <= fifo_windows[i].hi) return 1'b1;
    return 1'b0;
  endfunction

  // ---------------------------------------------------------------------------
  // Backdoor
  // ---------------------------------------------------------------------------
  function bit [31:0] peek(bit [31:0] a);
    bit [29:0] w = a[31:2];
    if (mem.exists(w)) return mem[w];
    return init_value(a);
  endfunction

  function void poke(bit [31:0] a, bit [31:0] d);
    mem[a[31:2]] = d;
  endfunction

  function bit written(bit [31:0] a);
    return mem.exists(a[31:2]);
  endfunction

  function int unsigned fifo_reads(bit [31:0] a);
    bit [29:0] w = a[31:2];
    return rd_count.exists(w) ? rd_count[w] : 0;
  endfunction

  function int unsigned sink_size(bit [31:0] a);
    bit [29:0] w = a[31:2];
    return sink.exists(w) ? sink[w].q.size() : 0;
  endfunction

  function bit [31:0] sink_word(bit [31:0] a, int unsigned i);
    bit [29:0] w = a[31:2];
    if (!sink.exists(w) || i >= sink[w].q.size()) return 32'h0;
    return sink[w].q[i];
  endfunction

  function void clear();
    mem.delete();
    rd_count.delete();
    sink.delete();
  endfunction

  // ---------------------------------------------------------------------------
  // Bus side (used by the slave driver)
  // ---------------------------------------------------------------------------
  function bit [31:0] bus_read(bit [31:0] a);
    bit [29:0] w = a[31:2];
    if (is_fifo(a)) begin
      int unsigned n = rd_count.exists(w) ? rd_count[w] : 0;
      rd_count[w] = n + 1;
      return fifo_value(a, n);
    end
    return peek(a);
  endfunction

  function void bus_write(bit [31:0] a, bit [31:0] d, bit [3:0] strb);
    bit [29:0] w = a[31:2];
    bit [31:0] merged;
    merged = peek(a);
    for (int b = 0; b < 4; b++) if (strb[b]) merged[8*b +: 8] = d[8*b +: 8];
    mem[w] = merged;
    if (is_fifo(a)) begin
      if (!sink.exists(w)) sink[w] = axi_word_q::type_id::create("sink");
      sink[w].q.push_back(merged);
    end
  endfunction

endclass : axi_mem
