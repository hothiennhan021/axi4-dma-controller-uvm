# BUG-14: Off-by-one in the source 4 KB room computation

* File: `rtl/dma_axi_engine.sv`
* Detected in simulation: yes - 18/30 runs failed
* Failing tests: `dma_4k_boundary_test`, `dma_backpressure_test`, `dma_corner_test`, `dma_fixed_addr_test`, `dma_irq_test`, `dma_multi_ch_test`, `dma_pause_resume_test`, `dma_single_ch_test`, `dma_stress_test`
* Formal BMC (protocol properties): caught at `dma_formal_tb.sv:190.9-190.56`

## Injected change

```diff
--- rtl/dma_axi_engine.sv
+++ rtl/dma_axi_engine.sv
@@ -103,7 +103,7 @@
   logic [15:0] beats_c;
 
   always_comb begin
-    src_room = 11'd1024 - {1'b0, d_src[11:2]};
+    src_room = 11'd1023 - {1'b0, d_src[11:2]};
     dst_room = 11'd1024 - {1'b0, d_dst[11:2]};
     beats_c  = d_rem;
     if (beats_c > ({12'b0, d_max_burst} + 16'd1)) beats_c = {12'b0, d_max_burst} + 16'd1;
```

## First error reported

```
UVM_ERROR @ 19495000 ps [SB_AR] ch2 ARLEN=1 expected 2 (rem=62 max_burst=2 src=0x127c8ff4 dst=0x8223d50c)
```
