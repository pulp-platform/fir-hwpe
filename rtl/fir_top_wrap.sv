/*
 * fir_top_wrap.sv
 * Francesco Conti <fconti@iis.ee.ethz.ch>
 *
 * Copyright (C) 2017-2023 ETH Zurich, University of Bologna
 * All rights reserved.
 */

`include "hci_helpers.svh"

module fir_top_wrap
  import fir_package::*;
  import hwpe_ctrl_package::*;
  import hci_package::*;
#(
`ifndef SYNTHESIS
  parameter bit WAIVE_RQ3_ASSERT  = 1'b0,
  parameter bit WAIVE_RQ4_ASSERT  = 1'b0,
  parameter bit WAIVE_RSP3_ASSERT = 1'b0,
  parameter bit WAIVE_RSP5_ASSERT = 1'b0,
`endif
  parameter N_CORES = 2,
  parameter MP  = 4,
  parameter ID  = 10
)
(
  // global signals
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  input  logic                                  test_mode_i,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  // tcdm master ports
  output logic [MP-1:0]                         tcdm_req,
  input  logic [MP-1:0]                         tcdm_gnt,
  output logic [MP-1:0][31:0]                   tcdm_add,
  output logic [MP-1:0]                         tcdm_wen,
  output logic [MP-1:0][3:0]                    tcdm_be,
  output logic [MP-1:0][31:0]                   tcdm_data,
  input  logic [MP-1:0][31:0]                   tcdm_r_data,
  input  logic [MP-1:0]                         tcdm_r_valid,
  // periph slave port
  input  logic                                  periph_req,
  output logic                                  periph_gnt,
  input  logic         [31:0]                   periph_add,
  input  logic                                  periph_wen,
  input  logic         [3:0]                    periph_be,
  input  logic         [31:0]                   periph_data,
  input  logic       [ID-1:0]                   periph_id,
  output logic         [31:0]                   periph_r_data,
  output logic                                  periph_r_valid,
  output logic       [ID-1:0]                   periph_r_id
);

  localparam hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '{
    DW:  32,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  DEFAULT_IW,
    EW:  DEFAULT_EW,
    EHW: DEFAULT_EHW
  };
  hci_core_intf #(
`ifndef SYNTHESIS
    .WAIVE_RQ3_ASSERT  ( WAIVE_RQ3_ASSERT  ),
    .WAIVE_RQ4_ASSERT  ( WAIVE_RQ4_ASSERT  ),
    .WAIVE_RSP3_ASSERT ( WAIVE_RSP3_ASSERT ),
    .WAIVE_RSP5_ASSERT ( WAIVE_RSP5_ASSERT ),
`endif
    .DW  ( 32          ),
    .AW  ( DEFAULT_AW  ),
    .BW  ( DEFAULT_BW  ),
    .UW  ( DEFAULT_UW  ),
    .IW  ( DEFAULT_IW  ),
    .EW  ( DEFAULT_EW  ),
    .EHW ( DEFAULT_EHW )
  ) tcdm [0:MP-2] (
    .clk ( clk_i )
  );

  hwpe_ctrl_intf_periph #(
    .ID_WIDTH ( ID )
  ) periph (
    .clk ( clk_i )
  );

  // bindings
  generate
    for(genvar ii=0; ii<MP-1; ii++) begin: tcdm_binding
      if(ii<3) begin
        assign tcdm_req  [ii] = tcdm[ii].req;
        assign tcdm_add  [ii] = tcdm[ii].add;
        assign tcdm_wen  [ii] = tcdm[ii].wen;
        assign tcdm_be   [ii] = tcdm[ii].be;
        assign tcdm_data [ii] = tcdm[ii].data;
        assign tcdm[ii].gnt      = tcdm_gnt     [ii];
        assign tcdm[ii].r_data   = tcdm_r_data  [ii];
        assign tcdm[ii].r_valid  = tcdm_r_valid [ii];
        assign tcdm[ii].r_user   = '0;
        assign tcdm[ii].r_ecc    = '0;
        assign tcdm[ii].r_id     = '0;
        assign tcdm[ii].r_opc    = '0;
        assign tcdm[ii].r_evalid = '0;
      end
      else begin
        assign tcdm_req  [ii] = '0;
        assign tcdm_add  [ii] = '0;
        assign tcdm_wen  [ii] = '0;
        assign tcdm_be   [ii] = '0;
        assign tcdm_data [ii] = '0;
        assign tcdm[ii].gnt      = '0;
        assign tcdm[ii].r_data   = '0;
        assign tcdm[ii].r_valid  = '0;
        assign tcdm[ii].r_user   = '0;
        assign tcdm[ii].r_ecc    = '0;
        assign tcdm[ii].r_id     = '0;
        assign tcdm[ii].r_opc    = '0;
        assign tcdm[ii].r_evalid = '0;
      end
    end
  endgenerate
  always_comb
  begin
    periph.req  = periph_req;
    periph.add  = periph_add;
    periph.wen  = periph_wen;
    periph.be   = periph_be;
    periph.data = periph_data;
    periph.id   = periph_id;
    periph_gnt     = periph.gnt;
    periph_r_data  = periph.r_data;
    periph_r_valid = periph.r_valid;
    periph_r_id    = periph.r_id;
  end

  fir_top #(
    .N_CORES               ( N_CORES               ),
    .MP                    ( 3                     ),
    .ID                    ( ID                    ),
    .`HCI_SIZE_PARAM(tcdm) ( `HCI_SIZE_PARAM(tcdm) )
  ) i_fir_top (
    .clk_i       ( clk_i       ),
    .rst_ni      ( rst_ni      ),
    .test_mode_i ( test_mode_i ),
    .evt_o       ( evt_o       ),
    .tcdm        ( tcdm        ),
    .periph      ( periph      )
  );

endmodule // fir_top_wrap
