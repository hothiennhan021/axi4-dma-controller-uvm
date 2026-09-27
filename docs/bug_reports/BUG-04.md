# BUG-04: W1C to INT_STATUS clears every pending bit, not only the bits written as 1

* File: `rtl/dma_top.sv`
* Detected in simulation: yes - 4/30 runs failed
* Failing tests: `dma_irq_test`, `dma_stress_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_top.sv
+++ rtl/dma_top.sv
@@ -235,7 +235,7 @@
 
   always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) int_status <= '0;
-    else        int_status <= (int_status & ~int_clr) | int_set;
+    else        int_status <= (|int_clr) ? int_set : (int_status | int_set);
   end
 
   assign irq = |(int_status & int_enable);
```

## First error reported

```
UVM_ERROR @ 2725000 ps [SB_REG] read 0x008: DUT=0x00000000 model=0x00000001 (diff 0x00000001)
```
