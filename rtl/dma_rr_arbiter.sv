// -----------------------------------------------------------------------------
// dma_rr_arbiter - round-robin arbiter, burst granularity
//
// A grant is issued (gnt_valid) when 'allow' is high and at least one channel
// requests. The search starts at the channel after the last granted one, so
// every requesting channel is served within NUM_CH grants.
// -----------------------------------------------------------------------------
module dma_rr_arbiter #(
  parameter int unsigned N  = 4,
  parameter int unsigned IW = (N > 1) ? $clog2(N) : 1   // derived, do not override
) (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          allow,
  input  logic [N-1:0]  req,
  output logic          gnt_valid,
  output logic [IW-1:0] gnt_idx
);

  logic [IW-1:0] last_q;

  always_comb begin
    logic [IW:0] idx;
    gnt_valid = 1'b0;
    gnt_idx   = '0;
    for (int unsigned i = 1; i <= N; i++) begin
      idx = {1'b0, last_q} + (IW+1)'(i);
      if (idx >= (IW+1)'(N)) idx = idx - (IW+1)'(N);
      if (!gnt_valid && req[idx[IW-1:0]]) begin
        gnt_valid = 1'b1;
        gnt_idx   = idx[IW-1:0];
      end
    end
    if (!allow) gnt_valid = 1'b0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)         last_q <= IW'(N - 1);   // first grant goes to channel 0
    else if (gnt_valid) last_q <= gnt_idx;
  end

endmodule : dma_rr_arbiter
