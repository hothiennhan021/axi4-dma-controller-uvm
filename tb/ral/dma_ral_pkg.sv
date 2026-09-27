// -----------------------------------------------------------------------------
// dma_ral_pkg - UVM register model of the DMA controller + APB adapter
//
// Hierarchy:
//   dma_reg_block
//     ID, CTRL, INT_STATUS, INT_ENABLE, BUSY          (global registers)
//     ch[n] : dma_ch_reg_block  (sub-map at 0x100 + 0x20*n)
//               CFG, SRC, DST, LEN, CMD, STAT
//
// Hardware-updated fields (INT_STATUS, BUSY, STAT) are volatile so the
// mirror is not compared on reads; their values are predicted and checked by
// the scoreboard instead. CMD has side effects and is excluded from the
// automatic register tests.
// -----------------------------------------------------------------------------
package dma_ral_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_pkg::*;

  // ---------------------------------------------------------------------------
  // Global registers
  // ---------------------------------------------------------------------------
  class dma_reg_id extends uvm_reg;
    `uvm_object_utils(dma_reg_id)
    uvm_reg_field NUM_CH;
    uvm_reg_field VERSION;
    uvm_reg_field MAGIC;
    int unsigned  num_ch = 4;
    function new(string name = "dma_reg_id");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      NUM_CH  = uvm_reg_field::type_id::create("NUM_CH");
      VERSION = uvm_reg_field::type_id::create("VERSION");
      MAGIC   = uvm_reg_field::type_id::create("MAGIC");
      //                parent size lsb access volatile reset has_reset is_rand individually_accessible
      NUM_CH.configure (this,  8,  0, "RO", 0, num_ch,     1, 0, 0);
      VERSION.configure(this,  8,  8, "RO", 0, 8'h01,      1, 0, 0);
      MAGIC.configure  (this, 16, 16, "RO", 0, 16'hDA0C,   1, 0, 0);
    endfunction
  endclass

  class dma_reg_ctrl extends uvm_reg;
    `uvm_object_utils(dma_reg_ctrl)
    rand uvm_reg_field EN;
    function new(string name = "dma_reg_ctrl");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      EN = uvm_reg_field::type_id::create("EN");
      EN.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
    endfunction
  endclass

  // INT_STATUS (W1C, set by hardware) and INT_ENABLE (RW) share the layout
  class dma_reg_int extends uvm_reg;
    `uvm_object_utils(dma_reg_int)
    rand uvm_reg_field DONE;
    rand uvm_reg_field ERR;
    int unsigned  num_ch = 4;
    string        acc    = "RW";
    function new(string name = "dma_reg_int");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      bit vol = (acc == "W1C");
      DONE = uvm_reg_field::type_id::create("DONE");
      ERR  = uvm_reg_field::type_id::create("ERR");
      DONE.configure(this, num_ch, 0, acc, vol, 0, 1, !vol, 0);
      ERR.configure (this, num_ch, 8, acc, vol, 0, 1, !vol, 0);
    endfunction
  endclass

  class dma_reg_busy extends uvm_reg;
    `uvm_object_utils(dma_reg_busy)
    uvm_reg_field BUSY;
    int unsigned  num_ch = 4;
    function new(string name = "dma_reg_busy");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      BUSY = uvm_reg_field::type_id::create("BUSY");
      BUSY.configure(this, num_ch, 0, "RO", 1, 0, 1, 0, 0);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Channel registers
  // ---------------------------------------------------------------------------
  class dma_reg_ch_cfg extends uvm_reg;
    `uvm_object_utils(dma_reg_ch_cfg)
    rand uvm_reg_field MAX_BURST;
    rand uvm_reg_field SRC_INC;
    rand uvm_reg_field DST_INC;
    function new(string name = "dma_reg_ch_cfg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      MAX_BURST = uvm_reg_field::type_id::create("MAX_BURST");
      SRC_INC   = uvm_reg_field::type_id::create("SRC_INC");
      DST_INC   = uvm_reg_field::type_id::create("DST_INC");
      MAX_BURST.configure(this, 4, 0, "RW", 0, 4'hF, 1, 1, 0);
      SRC_INC.configure  (this, 1, 4, "RW", 0, 1'b1, 1, 1, 0);
      DST_INC.configure  (this, 1, 5, "RW", 0, 1'b1, 1, 1, 0);
    endfunction
  endclass

  class dma_reg_ch_addr extends uvm_reg;
    `uvm_object_utils(dma_reg_ch_addr)
    rand uvm_reg_field ADDR;
    function new(string name = "dma_reg_ch_addr");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      ADDR = uvm_reg_field::type_id::create("ADDR");
      ADDR.configure(this, 30, 2, "RW", 0, 0, 1, 1, 0);
    endfunction
  endclass

  class dma_reg_ch_len extends uvm_reg;
    `uvm_object_utils(dma_reg_ch_len)
    rand uvm_reg_field WORDS;
    function new(string name = "dma_reg_ch_len");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      WORDS = uvm_reg_field::type_id::create("WORDS");
      WORDS.configure(this, 16, 0, "RW", 0, 0, 1, 1, 0);
    endfunction
  endclass

  class dma_reg_ch_cmd extends uvm_reg;
    `uvm_object_utils(dma_reg_ch_cmd)
    uvm_reg_field START;
    uvm_reg_field ABORT;
    function new(string name = "dma_reg_ch_cmd");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      START = uvm_reg_field::type_id::create("START");
      ABORT = uvm_reg_field::type_id::create("ABORT");
      START.configure(this, 1, 0, "WO", 0, 0, 1, 0, 0);
      ABORT.configure(this, 1, 1, "WO", 0, 0, 1, 0, 0);
    endfunction
  endclass

  class dma_reg_ch_stat extends uvm_reg;
    `uvm_object_utils(dma_reg_ch_stat)
    uvm_reg_field BUSY;
    uvm_reg_field DONE;
    uvm_reg_field ERR;
    uvm_reg_field ABORTED;
    uvm_reg_field ERR_RESP;
    uvm_reg_field ERR_WR;
    uvm_reg_field REMAIN;
    function new(string name = "dma_reg_ch_stat");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      BUSY     = uvm_reg_field::type_id::create("BUSY");
      DONE     = uvm_reg_field::type_id::create("DONE");
      ERR      = uvm_reg_field::type_id::create("ERR");
      ABORTED  = uvm_reg_field::type_id::create("ABORTED");
      ERR_RESP = uvm_reg_field::type_id::create("ERR_RESP");
      ERR_WR   = uvm_reg_field::type_id::create("ERR_WR");
      REMAIN   = uvm_reg_field::type_id::create("REMAIN");
      BUSY.configure    (this,  1,  0, "RO", 1, 0, 1, 0, 0);
      DONE.configure    (this,  1,  1, "RO", 1, 0, 1, 0, 0);
      ERR.configure     (this,  1,  2, "RO", 1, 0, 1, 0, 0);
      ABORTED.configure (this,  1,  3, "RO", 1, 0, 1, 0, 0);
      ERR_RESP.configure(this,  2,  4, "RO", 1, 0, 1, 0, 0);
      ERR_WR.configure  (this,  1,  6, "RO", 1, 0, 1, 0, 0);
      REMAIN.configure  (this, 16, 16, "RO", 1, 0, 1, 0, 0);
    endfunction
  endclass

  class dma_ch_reg_block extends uvm_reg_block;
    `uvm_object_utils(dma_ch_reg_block)
    rand dma_reg_ch_cfg  CFG;
    rand dma_reg_ch_addr SRC;
    rand dma_reg_ch_addr DST;
    rand dma_reg_ch_len  LEN;
    dma_reg_ch_cmd       CMD;
    dma_reg_ch_stat      STAT;
    function new(string name = "dma_ch_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
      default_map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN, 1);
      CFG  = dma_reg_ch_cfg ::type_id::create("CFG");
      SRC  = dma_reg_ch_addr::type_id::create("SRC");
      DST  = dma_reg_ch_addr::type_id::create("DST");
      LEN  = dma_reg_ch_len ::type_id::create("LEN");
      CMD  = dma_reg_ch_cmd ::type_id::create("CMD");
      STAT = dma_reg_ch_stat::type_id::create("STAT");
      CFG.configure(this);  CFG.build();
      SRC.configure(this);  SRC.build();
      DST.configure(this);  DST.build();
      LEN.configure(this);  LEN.build();
      CMD.configure(this);  CMD.build();
      STAT.configure(this); STAT.build();
      default_map.add_reg(CFG,  'h00, "RW");
      default_map.add_reg(SRC,  'h04, "RW");
      default_map.add_reg(DST,  'h08, "RW");
      default_map.add_reg(LEN,  'h0C, "RW");
      default_map.add_reg(CMD,  'h10, "WO");
      default_map.add_reg(STAT, 'h14, "RO");
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Top block
  // ---------------------------------------------------------------------------
  class dma_reg_block extends uvm_reg_block;
    `uvm_object_utils(dma_reg_block)
    dma_reg_id        ID;
    rand dma_reg_ctrl CTRL;
    dma_reg_int       INT_STATUS;
    rand dma_reg_int  INT_ENABLE;
    dma_reg_busy      BUSY;
    rand dma_ch_reg_block ch[];
    int unsigned      num_ch = 4;

    function new(string name = "dma_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      default_map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN, 1);

      ID = dma_reg_id::type_id::create("ID");
      ID.num_ch = num_ch;
      ID.configure(this); ID.build();

      CTRL = dma_reg_ctrl::type_id::create("CTRL");
      CTRL.configure(this); CTRL.build();

      INT_STATUS = dma_reg_int::type_id::create("INT_STATUS");
      INT_STATUS.num_ch = num_ch;
      INT_STATUS.acc    = "W1C";
      INT_STATUS.configure(this); INT_STATUS.build();

      INT_ENABLE = dma_reg_int::type_id::create("INT_ENABLE");
      INT_ENABLE.num_ch = num_ch;
      INT_ENABLE.acc    = "RW";
      INT_ENABLE.configure(this); INT_ENABLE.build();

      BUSY = dma_reg_busy::type_id::create("BUSY");
      BUSY.num_ch = num_ch;
      BUSY.configure(this); BUSY.build();

      default_map.add_reg(ID,         'h000, "RO");
      default_map.add_reg(CTRL,       'h004, "RW");
      default_map.add_reg(INT_STATUS, 'h008, "RW");
      default_map.add_reg(INT_ENABLE, 'h00C, "RW");
      default_map.add_reg(BUSY,       'h010, "RO");

      ch = new[num_ch];
      foreach (ch[i]) begin
        ch[i] = dma_ch_reg_block::type_id::create($sformatf("ch%0d", i));
        ch[i].configure(this);
        ch[i].build();
        default_map.add_submap(ch[i].default_map, 'h100 + 'h20 * i);
        // CMD has side effects (starts/aborts transfers): no automatic tests
        uvm_resource_db#(bit)::set({"REG::", ch[i].CMD.get_full_name()}, "NO_REG_TESTS", 1, this);
      end

      lock_model();
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Register adapter: uvm_reg_bus_op <-> apb_seq_item
  // ---------------------------------------------------------------------------
  class dma_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(dma_reg_adapter)

    function new(string name = "dma_reg_adapter");
      super.new(name);
      supports_byte_enable = 0;
      provides_responses   = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      apb_seq_item t = apb_seq_item::type_id::create("reg_apb_item");
      t.write = (rw.kind == UVM_WRITE);
      t.addr  = rw.addr[11:0];
      t.data  = (rw.kind == UVM_WRITE) ? rw.data[31:0] : 32'h0;
      return t;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
      apb_seq_item t;
      if (!$cast(t, bus_item)) begin
        `uvm_fatal("ADAPTER", "bus2reg: item is not an apb_seq_item")
        return;
      end
      rw.kind    = t.write ? UVM_WRITE : UVM_READ;
      rw.addr    = t.addr;
      rw.data    = t.data;
      rw.n_bits  = 32;
      rw.byte_en = '1;
      rw.status  = t.slverr ? UVM_NOT_OK : UVM_IS_OK;
    endfunction
  endclass

endpackage : dma_ral_pkg
