# BUG-13: Software W1C wins over a hardware set in the same cycle (interrupt lost)

* File: `rtl/dma_top.sv`
* Detected in simulation: yes - 2/30 runs failed
* Failing tests: `dma_irq_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_top.sv
+++ rtl/dma_top.sv
@@ -235,7 +235,7 @@
 
   always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) int_status <= '0;
-    else        int_status <= (int_status & ~int_clr) | int_set;
+    else        int_status <= (int_status | int_set) & ~int_clr;
   end
 
   assign irq = |(int_status & int_enable);
```

## First error reported

```
UVM_ERROR @ 54085000 ps [SB_IRQ] irq=0 expected 1 (INT_STATUS=0x00000001 INT_ENABLE=0x00000f0f)
```
