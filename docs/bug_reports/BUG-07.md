# BUG-07: WLAST asserted one beat early on bursts longer than 8 beats

* File: `rtl/dma_axi_engine.sv`
* Detected in simulation: yes - 25/30 runs failed
* Failing tests: `dma_4k_boundary_test`, `dma_abort_test`, `dma_apb_err_test`, `dma_backpressure_test`, `dma_corner_test`, `dma_error_test`, `dma_fixed_addr_test`, `dma_irq_test`, `dma_multi_ch_test`, `dma_pause_resume_test`, `dma_single_ch_test`, `dma_smoke_test`, `dma_stress_test`
* Formal BMC (protocol properties): caught at `dma_formal_tb.sv:204.9-204.44`

## Injected change

```diff
--- rtl/dma_axi_engine.sv
+++ rtl/dma_axi_engine.sv
@@ -232,7 +232,7 @@
   assign m_axi_awvalid = (state == S_W) & aw_pend;
   assign m_axi_wdata   = dbuf[wcnt];
   assign m_axi_wstrb   = 4'hF;
-  assign m_axi_wlast   = (wcnt == len_q);
+  assign m_axi_wlast   = (wcnt == len_q) || (len_q > 4'd7 && wcnt == len_q - 4'd1);
   assign m_axi_wvalid  = (state == S_W) & w_pend;
   assign m_axi_bready  = (state == S_B);
```

## First error reported

```
UVM_ERROR @ 1095000 ps [AXI_SLV_WLAST] WLAST after 15 beats but AWLEN=15 (16 beats): AXI_WRITE id=0 addr=0x80026d30 len=15 size=2 burst=INCR beats=0
```
