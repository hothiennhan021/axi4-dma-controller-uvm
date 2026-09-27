# BUG-09: START while busy restarts the channel when no burst is in flight

* File: `rtl/dma_channel.sv`
* Detected in simulation: yes - 3/30 runs failed
* Failing tests: `dma_corner_test`, `dma_stress_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_channel.sv
+++ rtl/dma_channel.sv
@@ -71,7 +71,7 @@
   assign last_ok   = busy & eng_done & ({11'b0, eng_beats} == rem);
   assign fin_abort = busy & abort_pend & ~eng_sel;
   assign finishing = last_ok | (busy & eng_err) | fin_abort;
-  assign start_ok  = start_req & ~busy;
+  assign start_ok  = start_req & ~(busy & eng_sel);
 
   assign fin_done  = last_ok | (start_ok & (len == 16'd0));
   assign fin_err   = busy & eng_err;
```

## First error reported

```
UVM_ERROR @ 519955000 ps [SB_AR] ch1 ARADDR=0x11cc3488 expected 0x112e4718
```
