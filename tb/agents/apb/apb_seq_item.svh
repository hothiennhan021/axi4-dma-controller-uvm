// -----------------------------------------------------------------------------
// apb_seq_item - one APB3 transfer
// For writes 'data' is PWDATA; for reads the driver/monitor fill 'data' with
// PRDATA. 'slverr' is the PSLVERR response.
// -----------------------------------------------------------------------------
class apb_seq_item extends uvm_sequence_item;

  rand bit [11:0] addr;
  rand bit        write;
  rand bit [31:0] data;
  bit             slverr;
  int unsigned    wait_cycles;   // PREADY wait states observed (monitor)

  constraint c_align { addr[1:0] == 2'b00; }

  `uvm_object_utils_begin(apb_seq_item)
    `uvm_field_int(addr,   UVM_ALL_ON)
    `uvm_field_int(write,  UVM_ALL_ON)
    `uvm_field_int(data,   UVM_ALL_ON)
    `uvm_field_int(slverr, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "apb_seq_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("%s addr=0x%03h data=0x%08h%s", write ? "WR" : "RD", addr, data,
                     slverr ? " PSLVERR" : "");
  endfunction

endclass : apb_seq_item
