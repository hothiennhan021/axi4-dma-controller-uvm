// -----------------------------------------------------------------------------
// Bind the protocol checkers into every dma_top instance.
// Port names of the checkers match the dma_top signal names, so .* connects
// them (including the internal int_status / int_enable of dma_top).
// -----------------------------------------------------------------------------
bind dma_top axi4_protocol_sva #(.ID_W(ID_W)) u_axi_sva (.*);
bind dma_top apb_protocol_sva                 u_apb_sva (.*);
bind dma_top dma_irq_sva                      u_irq_sva (.*);
