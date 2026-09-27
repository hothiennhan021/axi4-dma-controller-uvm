# BUG-12: Channel reports DONE one word early when the last burst is longer than one beat

* File: `rtl/dma_channel.sv`
* Detected in simulation: yes - 20/30 runs failed
* Failing tests: `dma_4k_boundary_test`, `dma_abort_test`, `dma_backpressure_test`, `dma_corner_test`, `dma_error_test`, `dma_fixed_addr_test`, `dma_irq_test`, `dma_multi_ch_test`, `dma_pause_resume_test`, `dma_single_ch_test`, `dma_stress_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_channel.sv
+++ rtl/dma_channel.sv
@@ -68,7 +68,7 @@
   assign dst_inc   = cfg_q[5];
 
   assign req       = busy & ~abort_pend;
-  assign last_ok   = busy & eng_done & ({11'b0, eng_beats} == rem);
+  assign last_ok   = busy & eng_done & ({11'b0, eng_beats} >= rem - 16'd1) & (rem != 16'd1 || eng_beats == 5'd1);
   assign fin_abort = busy & abort_pend & ~eng_sel;
   assign finishing = last_ok | (busy & eng_err) | fin_abort;
   assign start_ok  = start_req & ~busy;
```

## First error reported

```
UVM_ERROR @ 103365000 ps [SB_IRQ] irq=1 expected 0 (INT_STATUS=0x00000000 INT_ENABLE=0x00000f0f)
```
