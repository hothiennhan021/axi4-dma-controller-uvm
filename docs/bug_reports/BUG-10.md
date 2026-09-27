# BUG-10: Channel offset 0x18 decoded as a register (no PSLVERR)

* File: `rtl/dma_apb_regs.sv`
* Detected in simulation: yes - 2/30 runs failed
* Failing tests: `dma_apb_err_test`
* Formal BMC (protocol properties): not caught (functional bug, outside the protocol property set)

## Injected change

```diff
--- rtl/dma_apb_regs.sv
+++ rtl/dma_apb_regs.sv
@@ -70,7 +70,7 @@
         endcase
       end else if (is_ch) begin
         case (ch_off)
-          CH_CFG, CH_SRC, CH_DST, CH_LEN, CH_CMD, CH_STAT: addr_ok = 1'b1;
+          CH_CFG, CH_SRC, CH_DST, CH_LEN, CH_CMD, CH_STAT, 5'h18: addr_ok = 1'b1;
           default:                                         addr_ok = 1'b0;
         endcase
       end
```

## First error reported

```
UVM_ERROR @ 365000 ps [SB_APB] missing PSLVERR on unmapped access: WR addr=0x118 data=0x2b2b6c4c
```
