// -----------------------------------------------------------------------------
// dma_env
//
//   apb_agent (active master) --mon.ap--> reg predictor --> regmodel mirror
//                                   \---> scoreboard
//   axi_agent (reactive slave) --mon.ap / mon.ar_req_ap--> scoreboard
//   scoreboard --cov_ap--> coverage
// -----------------------------------------------------------------------------
class dma_env extends uvm_env;

  `uvm_component_utils(dma_env)

  dma_env_cfg                       cfg;
  apb_agent                         apb;
  axi_agent                         axi;
  dma_reg_block                     regmodel;
  dma_reg_adapter                   adapter;
  uvm_reg_predictor #(apb_seq_item) predictor;
  dma_scoreboard                    sb;
  dma_coverage                      cov;
  dma_virtual_sequencer             vsqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(dma_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "dma_env_cfg not found")

    uvm_config_db#(apb_agent_cfg)::set(this, "apb*", "cfg", cfg.apb_cfg);
    uvm_config_db#(axi_slave_cfg)::set(this, "axi*", "cfg", cfg.axi_cfg);
    uvm_config_db#(axi_mem)::set(this, "axi*", "mem", cfg.mem);
    uvm_config_db#(dma_env_cfg)::set(this, "sb", "cfg", cfg);
    uvm_config_db#(dma_env_cfg)::set(this, "cov", "cfg", cfg);

    apb = apb_agent::type_id::create("apb", this);
    axi = axi_agent::type_id::create("axi", this);

    regmodel = dma_reg_block::type_id::create("regmodel");
    regmodel.num_ch = cfg.num_ch;
    regmodel.build();

    adapter   = dma_reg_adapter::type_id::create("adapter");
    predictor = uvm_reg_predictor#(apb_seq_item)::type_id::create("predictor", this);

    if (cfg.has_scoreboard) sb = dma_scoreboard::type_id::create("sb", this);
    if (cfg.has_coverage)   cov = dma_coverage::type_id::create("cov", this);
    vsqr = dma_virtual_sequencer::type_id::create("vsqr", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Register layer: frontdoor through the APB sequencer, explicit prediction
    regmodel.default_map.set_sequencer(apb.sqr, adapter);
    regmodel.default_map.set_auto_predict(0);
    predictor.map     = regmodel.default_map;
    predictor.adapter = adapter;
    apb.mon.ap.connect(predictor.bus_in);

    if (cfg.has_scoreboard) begin
      apb.mon.ap.connect(sb.apb_export);
      axi.mon.ap.connect(sb.axi_export);
      axi.mon.ar_req_ap.connect(sb.arreq_export);
      if (cfg.has_coverage) sb.cov_ap.connect(cov.analysis_export);
    end

    vsqr.apb_sqr  = apb.sqr;
    vsqr.regmodel = regmodel;
    vsqr.mem      = cfg.mem;
    vsqr.axi_cfg  = cfg.axi_cfg;
    vsqr.cfg      = cfg;
    vsqr.irq_vif  = cfg.irq_vif;
  endfunction

endclass : dma_env
