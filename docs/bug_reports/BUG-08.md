# BUG-08: CTRL.EN is ignored by the arbiter (channels run while disabled)

* File: `rtl/dma_top.sv`
* Detected in simulation: yes - 8/30 runs failed
* Failing tests: `dma_abort_test`, `dma_corner_test`, `dma_pause_resume_test`, `dma_stress_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_top.sv
+++ rtl/dma_top.sv
@@ -164,7 +164,7 @@
   dma_rr_arbiter #(.N(NUM_CH)) u_arb (
     .clk       (clk),
     .rst_n     (rst_n),
-    .allow     (glb_en & eng_idle),
+    .allow     (eng_idle),
     .req       (ch_req),
     .gnt_valid (gnt_valid),
     .gnt_idx   (gnt_idx)
```

## First error reported

```
UVM_ERROR @ 65365000 ps [SB_EN] ch2 granted @65355000 while CTRL.EN=0
```
