# Coverage report (merged regression: 15 tests x 5 seeds)

- Functional coverage (covergroups, average): 100.0%
  - cg_apb: 100.0%
  - cg_burst: 100.0%
  - cg_cmd: 100.0%
  - cg_finish: 100.0%
  - cg_grant: 100.0%
  - cg_irq: 100.0%
  - cg_start: 100.0%
  - cg_wr_order: 100.0%
- SVA cover properties hit: 11/11
- RTL line coverage: 100.0% (150/150)
- RTL toggle coverage: 80.7% (4325/5358)

## cg_apb (100.0%)

| Coverpoint / cross | Bins hit | Total | % |
|---|---|---|---|
| cp_ch_reg | 6 | 6 | 100.0 |
| cp_region | 4 | 4 | 100.0 |
| cp_write | 2 | 2 | 100.0 |
| x_chreg_dir | 12 | 12 | 100.0 |
| x_region_dir | 8 | 8 | 100.0 |

## cg_burst (100.0%)

| Coverpoint / cross | Bins hit | Total | % |
|---|---|---|---|
| cp_addr_wait | 3 | 3 | 100.0 |
| cp_beats | 16 | 16 | 100.0 |
| cp_ch | 4 | 4 | 100.0 |
| cp_cut | 3 | 3 | 100.0 |
| cp_dir | 2 | 2 | 100.0 |
| cp_resp | 3 | 3 | 100.0 |
| cp_type | 2 | 2 | 100.0 |
| x_cut_dir | 6 | 6 | 100.0 |
| x_dir_resp | 6 | 6 | 100.0 |
| x_dir_type | 4 | 4 | 100.0 |
| x_type_beats | 32 | 32 | 100.0 |

## cg_cmd (100.0%)

| Coverpoint / cross | Bins hit | Total | % |
|---|---|---|---|
| cp_abort_ctx | 4 | 4 | 100.0 |
| cp_kind | 3 | 3 | 100.0 |

## cg_finish (100.0%)

| Coverpoint / cross | Bins hit | Total | % |
|---|---|---|---|
| cp_ch | 4 | 4 | 100.0 |
| cp_fin | 4 | 4 | 100.0 |
| x_ch_fin | 16 | 16 | 100.0 |

## cg_grant (100.0%)

| Coverpoint / cross | Bins hit | Total | % |
|---|---|---|---|
| cp_ch | 4 | 4 | 100.0 |
| cp_n_req | 4 | 4 | 100.0 |
| x_ch_nreq | 16 | 16 | 100.0 |

## cg_irq (100.0%)

| Coverpoint / cross | Bins hit | Total | % |
|---|---|---|---|
| cp_cause | 3 | 3 | 100.0 |
| cp_masked_pending | 2 | 2 | 100.0 |

## cg_start (100.0%)

| Coverpoint / cross | Bins hit | Total | % |
|---|---|---|---|
| cp_ch | 4 | 4 | 100.0 |
| cp_dst_inc | 2 | 2 | 100.0 |
| cp_len | 7 | 7 | 100.0 |
| cp_max_burst | 5 | 5 | 100.0 |
| cp_src_inc | 2 | 2 | 100.0 |
| cp_with_abort | 2 | 2 | 100.0 |
| x_inc | 4 | 4 | 100.0 |
| x_len_burst | 25 | 25 | 100.0 |

## cg_wr_order (100.0%)

| Coverpoint / cross | Bins hit | Total | % |
|---|---|---|---|
| cp_w_before_aw | 2 | 2 | 100.0 |

## SVA cover properties

| Property | Hits |
|---|---|
| tb_top.u_dut.u_apb_sva.c_b2b | 16123 |
| tb_top.u_dut.u_apb_sva.c_slverr | 600 |
| tb_top.u_dut.u_axi_sva.c_ar_4k_end | 657 |
| tb_top.u_dut.u_axi_sva.c_ar_fixed | 4547 |
| tb_top.u_dut.u_axi_sva.c_ar_len16 | 21666 |
| tb_top.u_dut.u_axi_sva.c_ar_wait | 98199 |
| tb_top.u_dut.u_axi_sva.c_aw_before_w | 23260 |
| tb_top.u_dut.u_axi_sva.c_b_err | 43 |
| tb_top.u_dut.u_axi_sva.c_r_b2b | 363281 |
| tb_top.u_dut.u_axi_sva.c_r_err | 155 |
| tb_top.u_dut.u_axi_sva.c_w_before_aw | 24264 |
