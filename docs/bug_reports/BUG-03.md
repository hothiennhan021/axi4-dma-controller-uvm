# BUG-03: ABORT terminates the channel while its burst is still in flight

* File: `rtl/dma_channel.sv`
* Detected in simulation: yes - 4/30 runs failed
* Failing tests: `dma_abort_test`, `dma_stress_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_channel.sv
+++ rtl/dma_channel.sv
@@ -69,7 +69,7 @@
 
   assign req       = busy & ~abort_pend;
   assign last_ok   = busy & eng_done & ({11'b0, eng_beats} == rem);
-  assign fin_abort = busy & abort_pend & ~eng_sel;
+  assign fin_abort = busy & abort_pend;
   assign finishing = last_ok | (busy & eng_err) | fin_abort;
   assign start_ok  = start_req & ~busy;
```

## First error reported

```
UVM_ERROR @ 4755000 ps [SB_REG] read 0x114: DUT=0x04050008 model=0x04050001 (diff 0x00000009)
```
