# BUG-02: Arbiter degenerates to fixed priority (channel 0 always wins)

* File: `rtl/dma_rr_arbiter.sv`
* Detected in simulation: yes - 14/30 runs failed
* Failing tests: `dma_backpressure_test`, `dma_corner_test`, `dma_error_test`, `dma_irq_test`, `dma_multi_ch_test`, `dma_pause_resume_test`, `dma_stress_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_rr_arbiter.sv
+++ rtl/dma_rr_arbiter.sv
@@ -24,7 +24,7 @@
     gnt_valid = 1'b0;
     gnt_idx   = '0;
     for (int unsigned i = 1; i <= N; i++) begin
-      idx = {1'b0, last_q} + (IW+1)'(i);
+      idx = (IW+1)'(i - 1);
       if (idx >= (IW+1)'(N)) idx = idx - (IW+1)'(N);
       if (!gnt_valid && req[idx[IW-1:0]]) begin
         gnt_valid = 1'b1;
```

## First error reported

```
UVM_ERROR @ 1565000 ps [SB_RR] round-robin violation: granted ch0, expected ch3 (last grant ch2)
```
