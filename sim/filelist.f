// Source list (paths relative to the repository root). The UVM library is
// added by the simulator-specific scripts.
+incdir+tb/top
+incdir+tb/agents/apb
+incdir+tb/agents/axi
+incdir+tb/env
+incdir+tb/seq
+incdir+tb/tests
rtl/dma_pkg.sv
rtl/dma_apb_regs.sv
rtl/dma_channel.sv
rtl/dma_rr_arbiter.sv
rtl/dma_axi_engine.sv
rtl/dma_top.sv
tb/top/dma_ifs.sv
tb/agents/apb/apb_pkg.sv
tb/agents/axi/axi_pkg.sv
tb/ral/dma_ral_pkg.sv
tb/env/dma_env_pkg.sv
tb/seq/dma_seq_pkg.sv
tb/tests/dma_test_pkg.sv
tb/sva/dma_sva.sv
tb/sva/dma_bind.sv
tb/top/tb_top.sv
