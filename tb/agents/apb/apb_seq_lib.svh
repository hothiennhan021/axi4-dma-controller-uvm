// -----------------------------------------------------------------------------
// APB sequences (raw bus access, used for accesses the register model does
// not cover - e.g. unmapped addresses)
// -----------------------------------------------------------------------------
class apb_rw_seq extends uvm_sequence #(apb_seq_item);

  `uvm_object_utils(apb_rw_seq)

  rand bit [11:0] addr;
  rand bit        write;
  rand bit [31:0] data;
  bit             aligned = 1;   // set to 0 to allow misaligned addresses
  // results
  bit [31:0]      rdata;
  bit             slverr;

  function new(string name = "apb_rw_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item t;
    t = apb_seq_item::type_id::create("t");
    start_item(t);
    if (aligned) begin
      if (!t.randomize() with { addr == local::addr; write == local::write; data == local::data; })
        `uvm_fatal("RAND", "apb_rw_seq randomization failed")
    end else begin
      t.c_align.constraint_mode(0);
      if (!t.randomize() with { addr == local::addr; write == local::write; data == local::data; })
        `uvm_fatal("RAND", "apb_rw_seq randomization failed")
    end
    finish_item(t);
    rdata  = t.data;
    slverr = t.slverr;
  endtask

endclass : apb_rw_seq
