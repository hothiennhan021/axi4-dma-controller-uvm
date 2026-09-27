// -----------------------------------------------------------------------------
// axi_slave_cfg - knobs for the reactive AXI4 slave (memory model)
// -----------------------------------------------------------------------------
class axi_err_region extends uvm_object;
  `uvm_object_utils(axi_err_region)
  bit [31:0] lo;
  bit [31:0] hi;         // inclusive
  bit [1:0]  resp;       // SLVERR (2) or DECERR (3)
  bit        on_read;
  bit        on_write;
  function new(string name = "axi_err_region");
    super.new(name);
  endfunction
  function bit hit(bit [31:0] a);
    return (a >= lo) && (a <= hi);
  endfunction
endclass : axi_err_region


class axi_slave_cfg extends uvm_object;

  `uvm_object_utils(axi_slave_cfg)

  virtual axi_if          vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // READY / VALID timing. For each address/data channel the slave either
  // raises READY before VALID ("ready early", probability pct_ready_early)
  // or waits a random number of cycles in [min,max] after VALID.
  int unsigned pct_ready_early = 30;
  int unsigned ar_delay_min = 0, ar_delay_max = 3;
  int unsigned aw_delay_min = 0, aw_delay_max = 3;
  int unsigned w_delay_min  = 0, w_delay_max  = 2;
  int unsigned r_gap_min    = 0, r_gap_max    = 2;   // idle cycles before each R beat
  int unsigned b_delay_min  = 0, b_delay_max  = 3;

  axi_err_region err_regions[$];

  function new(string name = "axi_slave_cfg");
    super.new(name);
  endfunction

  function void set_delays(int unsigned lo, int unsigned hi, int unsigned pct_early = 30);
    ar_delay_min = lo; ar_delay_max = hi;
    aw_delay_min = lo; aw_delay_max = hi;
    w_delay_min  = lo; w_delay_max  = hi;
    r_gap_min    = lo; r_gap_max    = hi;
    b_delay_min  = lo; b_delay_max  = hi;
    pct_ready_early = pct_early;
  endfunction

  function axi_err_region add_err_region(bit [31:0] lo, bit [31:0] hi, bit [1:0] resp,
                                         bit on_read, bit on_write);
    axi_err_region r = axi_err_region::type_id::create("err_region");
    r.lo = lo; r.hi = hi; r.resp = resp; r.on_read = on_read; r.on_write = on_write;
    err_regions.push_back(r);
    return r;
  endfunction

  function void remove_err_region(axi_err_region r);
    foreach (err_regions[i]) begin
      if (err_regions[i] == r) begin
        err_regions.delete(i);
        return;
      end
    end
  endfunction

  function void clear_err_regions();
    err_regions.delete();
  endfunction

  // Response for one beat address (first matching region wins)
  function bit [1:0] resp_for(bit [31:0] a, bit is_read);
    foreach (err_regions[i]) begin
      if (err_regions[i].hit(a) && (is_read ? err_regions[i].on_read : err_regions[i].on_write))
        return err_regions[i].resp;
    end
    return 2'b00;
  endfunction

endclass : axi_slave_cfg
