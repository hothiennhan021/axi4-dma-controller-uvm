# BUG-11: Write data pointer advances without WREADY (data lost under back-pressure)

* File: `rtl/dma_axi_engine.sv`
* Detected in simulation: yes - 26/30 runs failed
* Failing tests: `dma_4k_boundary_test`, `dma_abort_test`, `dma_apb_err_test`, `dma_backpressure_test`, `dma_corner_test`, `dma_error_test`, `dma_fixed_addr_test`, `dma_irq_test`, `dma_multi_ch_test`, `dma_pause_resume_test`, `dma_single_ch_test`, `dma_smoke_test`, `dma_stress_test`
* Formal BMC (protocol properties): caught at `dma_formal_tb.sv:204.9-204.44`

## Injected change

```diff
--- rtl/dma_axi_engine.sv
+++ rtl/dma_axi_engine.sv
@@ -189,6 +189,8 @@
           if (w_hs) begin
             if (m_axi_wlast) w_pend <= 1'b0;
             else             wcnt   <= wcnt + 4'd1;
+          end else if (m_axi_wvalid && wcnt != len_q && wcnt[0]) begin
+            wcnt <= wcnt + 4'd1;
           end
           if ((!aw_pend || aw_hs) && (!w_pend || (w_hs && m_axi_wlast))) state <= S_B;
         end
```

## First error reported

```
UVM_ERROR @ 785000 ps [AXI_SVA] W payload changed while waiting for WREADY
```
