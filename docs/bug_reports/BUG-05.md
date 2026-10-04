# BUG-05: Read error does not suppress the write burst (garbage written to the destination)

* File: `rtl/dma_axi_engine.sv`
* Detected in simulation: yes - 6/30 runs failed
* Failing tests: `dma_error_test`, `dma_irq_test`, `dma_stress_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_axi_engine.sv
+++ rtl/dma_axi_engine.sv
@@ -173,7 +173,7 @@
               rd_resp_q <= m_axi_rresp;
             end
             if (m_axi_rlast) begin
-              if (rd_fail) begin
+              if (1'b0) begin
                 state <= S_IDLE;
               end else begin
                 state   <= S_W;
```

## First error reported

```
UVM_ERROR @ 6655000 ps [SB_AXI] unexpected write burst: AXI_WRITE id=3 addr=0x83d41e1c len=13 size=2 burst=INCR beats=14
```
