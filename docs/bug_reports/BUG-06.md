# BUG-06: AWBURST is always INCR, even for a fixed (FIFO) destination

* File: `rtl/dma_axi_engine.sv`
* Detected in simulation: yes - 4/30 runs failed
* Failing tests: `dma_fixed_addr_test`, `dma_stress_test`
* Formal BMC (protocol properties): caught at `dma_formal_tb.sv:198.9-198.56`

## Injected change

```diff
--- rtl/dma_axi_engine.sv
+++ rtl/dma_axi_engine.sv
@@ -151,7 +151,7 @@
             araddr_q  <= d_src;
             awaddr_q  <= d_dst;
             arburst_q <= d_src_inc ? AXI_BURST_INCR : AXI_BURST_FIXED;
-            awburst_q <= d_dst_inc ? AXI_BURST_INCR : AXI_BURST_FIXED;
+            awburst_q <= AXI_BURST_INCR;
             len_q     <= 4'(beats_c - 16'd1);
             rcnt      <= '0;
             wcnt      <= '0;
```

## First error reported

```
UVM_ERROR @ 3425000 ps [SB_AW] ch2 AWBURST=1 expected 0
```
