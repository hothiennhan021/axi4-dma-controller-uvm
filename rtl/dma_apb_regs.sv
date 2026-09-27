// -----------------------------------------------------------------------------
// dma_apb_regs - APB3 slave register file of the DMA controller
//
// * Zero wait state (PREADY is tied high).
// * Writes take effect in the APB access phase.
// * START / ABORT are one-cycle pulses generated from a write to CHn_CMD.
// * INT_STATUS is write-one-to-clear; the clear mask is forwarded to the
//   top level which owns the INT_STATUS flops (hardware set wins over clear).
// * Unmapped / misaligned accesses complete with PSLVERR and have no effect.
// -----------------------------------------------------------------------------
module dma_apb_regs #(
  parameter int unsigned NUM_CH = 4
) (
  input  logic                     clk,
  input  logic                     rst_n,

  // APB3 slave
  input  logic                     psel,
  input  logic                     penable,
  input  logic                     pwrite,
  input  logic [11:0]              paddr,
  input  logic [31:0]              pwdata,
  output logic [31:0]              prdata,
  output logic                     pready,
  output logic                     pslverr,

  // Programming model outputs
  output logic                     glb_en,
  output logic [31:0]              int_enable,
  output logic [31:0]              int_clr,      // W1C pulse mask
  output logic [NUM_CH-1:0][5:0]   ch_cfg,
  output logic [NUM_CH-1:0][31:0]  ch_src,
  output logic [NUM_CH-1:0][31:0]  ch_dst,
  output logic [NUM_CH-1:0][15:0]  ch_len,
  output logic [NUM_CH-1:0]        ch_start,     // pulse
  output logic [NUM_CH-1:0]        ch_abort,     // pulse

  // Status inputs
  input  logic [31:0]              int_status,
  input  logic [NUM_CH-1:0][31:0]  ch_stat
);

  import dma_pkg::*;

  localparam logic [31:0] INT_MASK =
      ((32'h1 << NUM_CH) - 32'h1) | (((32'h1 << NUM_CH) - 32'h1) << INT_ERR_LSB);

  // ---------------------------------------------------------------------------
  // Address decode
  // ---------------------------------------------------------------------------
  logic        access, wr_en, rd_en;
  logic        is_glb, is_ch, addr_ok;
  logic [2:0]  ch_idx;
  logic [4:0]  ch_off;

  assign access = psel & penable;
  assign ch_idx = paddr[7:5];
  assign ch_off = paddr[4:0];
  assign is_glb = (paddr[11:8] == 4'h0);
  assign is_ch  = (paddr[11:8] == CH_BASE[11:8]) && (32'(ch_idx) < NUM_CH);

  always_comb begin
    addr_ok = 1'b0;
    if (paddr[1:0] == 2'b00) begin
      if (is_glb) begin
        case (paddr[7:0])
          REG_ID[7:0], REG_CTRL[7:0], REG_INT_STATUS[7:0],
          REG_INT_ENABLE[7:0], REG_BUSY[7:0]: addr_ok = 1'b1;
          default:                            addr_ok = 1'b0;
        endcase
      end else if (is_ch) begin
        case (ch_off)
          CH_CFG, CH_SRC, CH_DST, CH_LEN, CH_CMD, CH_STAT: addr_ok = 1'b1;
          default:                                         addr_ok = 1'b0;
        endcase
      end
    end
  end

  assign wr_en   = access &  pwrite & addr_ok;
  assign rd_en   = access & ~pwrite & addr_ok;
  assign pready  = 1'b1;
  assign pslverr = access & ~addr_ok;

  // ---------------------------------------------------------------------------
  // Writable registers
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      glb_en     <= 1'b0;
      int_enable <= '0;
      for (int c = 0; c < NUM_CH; c++) begin
        ch_cfg[c] <= CFG_RESET;
        ch_src[c] <= '0;
        ch_dst[c] <= '0;
        ch_len[c] <= '0;
      end
    end else if (wr_en) begin
      if (is_glb) begin
        if (paddr[7:0] == REG_CTRL[7:0])       glb_en     <= pwdata[0];
        if (paddr[7:0] == REG_INT_ENABLE[7:0]) int_enable <= pwdata & INT_MASK;
      end else begin
        for (int c = 0; c < NUM_CH; c++) begin
          if (32'(ch_idx) == c) begin
            if (ch_off == CH_CFG) ch_cfg[c] <= pwdata[5:0];
            if (ch_off == CH_SRC) ch_src[c] <= {pwdata[31:2], 2'b00};
            if (ch_off == CH_DST) ch_dst[c] <= {pwdata[31:2], 2'b00};
            if (ch_off == CH_LEN) ch_len[c] <= pwdata[15:0];
          end
        end
      end
    end
  end

  // Command / clear pulses (combinational, valid in the access phase)
  always_comb begin
    ch_start = '0;
    ch_abort = '0;
    int_clr  = '0;
    if (wr_en) begin
      if (is_glb && paddr[7:0] == REG_INT_STATUS[7:0]) int_clr = pwdata & INT_MASK;
      if (is_ch && ch_off == CH_CMD) begin
        for (int c = 0; c < NUM_CH; c++) begin
          if (32'(ch_idx) == c) begin
            ch_start[c] = pwdata[0];
            ch_abort[c] = pwdata[1];
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Read mux
  // ---------------------------------------------------------------------------
  logic [31:0] rdata;
  logic [31:0] busy_vec;

  always_comb begin
    busy_vec = '0;
    for (int c = 0; c < NUM_CH; c++) busy_vec[c] = ch_stat[c][0];
  end

  always_comb begin
    rdata = '0;
    if (is_glb) begin
      case (paddr[7:0])
        REG_ID[7:0]:         rdata = {DMA_ID_MAGIC, DMA_VERSION, 8'(NUM_CH)};
        REG_CTRL[7:0]:       rdata = {31'b0, glb_en};
        REG_INT_STATUS[7:0]: rdata = int_status & INT_MASK;
        REG_INT_ENABLE[7:0]: rdata = int_enable;
        REG_BUSY[7:0]:       rdata = busy_vec;
        default:             rdata = '0;
      endcase
    end else if (is_ch) begin
      for (int c = 0; c < NUM_CH; c++) begin
        if (32'(ch_idx) == c) begin
          case (ch_off)
            CH_CFG:  rdata = {26'b0, ch_cfg[c]};
            CH_SRC:  rdata = ch_src[c];
            CH_DST:  rdata = ch_dst[c];
            CH_LEN:  rdata = {16'b0, ch_len[c]};
            CH_STAT: rdata = ch_stat[c];
            default: rdata = '0;     // CH_CMD reads as zero
          endcase
        end
      end
    end
  end

  assign prdata = rd_en ? rdata : '0;

endmodule : dma_apb_regs
