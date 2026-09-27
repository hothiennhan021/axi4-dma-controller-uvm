# BUG-01: Burst length ignores the destination 4 KB boundary (AW bursts may cross 4 KB)

* File: `rtl/dma_axi_engine.sv`
* Detected in simulation: yes - 20/30 runs failed
* Failing tests: `dma_4k_boundary_test`, `dma_abort_test`, `dma_apb_err_test`, `dma_backpressure_test`, `dma_corner_test`, `dma_error_test`, `dma_fixed_addr_test`, `dma_irq_test`, `dma_multi_ch_test`, `dma_pause_resume_test`, `dma_single_ch_test`, `dma_stress_test`
* Formal BMC (protocol properties): caught at `dma_formal_tb.sv:198.9-198.56`

## Injected change

```diff
--- rtl/dma_axi_engine.sv
+++ rtl/dma_axi_engine.sv
@@ -108,7 +108,6 @@
     beats_c  = d_rem;
     if (beats_c > ({12'b0, d_max_burst} + 16'd1)) beats_c = {12'b0, d_max_burst} + 16'd1;
     if (d_src_inc && (beats_c > {5'b0, src_room})) beats_c = {5'b0, src_room};
-    if (d_dst_inc && (beats_c > {5'b0, dst_room})) beats_c = {5'b0, dst_room};
   end
 
   // ---------------------------------------------------------------------------
```

## First error reported

```
UVM_ERROR @ 4585000 ps [SB_AR] ch2 ARLEN=10 expected 4 (rem=294 max_burst=10 src=0x12aa43d4 dst=0x8226dfec)
```
