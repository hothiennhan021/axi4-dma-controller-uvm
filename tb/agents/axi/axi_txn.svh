// -----------------------------------------------------------------------------
// axi_txn - one AXI4 burst as observed on the bus
//
// READ : address phase + all R beats (data[], resp[] per beat)
// WRITE: address phase + all W beats (data[], strb[]) + B response (resp[0])
// The monitor also publishes "address request" events (kind AXI_AR_REQ) at the
// first cycle ARVALID is seen, which the scoreboard uses to check arbitration
// and abort timing.
// -----------------------------------------------------------------------------
typedef enum bit [1:0] {AXI_READ, AXI_WRITE, AXI_AR_REQ} axi_kind_e;

class axi_txn extends uvm_sequence_item;

  axi_kind_e   kind;
  bit [3:0]    id;
  bit [31:0]   addr;
  bit [7:0]    len;          // beats - 1
  bit [2:0]    size;
  bit [1:0]    burst;

  bit [31:0]   data[$];
  bit [3:0]    strb[$];
  bit [1:0]    resp[$];      // READ: one per beat; WRITE: resp[0] = BRESP

  time         t_req;        // first cycle ADDR VALID was sampled high
  time         t_addr;       // address handshake
  time         t_end;        // last R beat / B handshake
  int unsigned addr_wait;    // cycles VALID waited for READY on the address channel
  bit          w_before_aw;  // WRITE: first W beat was accepted before AW

  `uvm_object_utils(axi_txn)

  function new(string name = "axi_txn");
    super.new(name);
  endfunction

  function int unsigned beats();
    return int'(len) + 1;
  endfunction

  // Address of beat i (FIXED or INCR, 4-byte beats)
  function bit [31:0] beat_addr(int unsigned i);
    if (burst == 2'b00) return addr;
    return addr + 32'(i) * 32'd4;
  endfunction

  function bit has_error();
    foreach (resp[i]) if (resp[i][1]) return 1'b1;
    return 1'b0;
  endfunction

  function bit [1:0] first_error();
    foreach (resp[i]) if (resp[i][1]) return resp[i];
    return 2'b00;
  endfunction

  virtual function string convert2string();
    string s;
    s = $sformatf("%s id=%0d addr=0x%08h len=%0d size=%0d burst=%s",
                  kind.name(), id, addr, len, size,
                  burst == 2'b00 ? "FIXED" : (burst == 2'b01 ? "INCR" : "WRAP/RSVD"));
    if (kind != AXI_AR_REQ) begin
      s = {s, $sformatf(" beats=%0d", data.size())};
      if (has_error()) s = {s, $sformatf(" RESP=%0d", first_error())};
    end
    return s;
  endfunction

endclass : axi_txn
