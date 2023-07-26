/* 
 * fir_top.sv
 * Francesco Conti <fconti@iis.ee.ethz.ch>
 *
 * Copyright (C) 2018 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

module fir_top
  import fir_package::*;
  import hwpe_ctrl_package::*;
  import hci_package::*;
#(
  parameter int unsigned N_CORES = 2,
  parameter int unsigned MP  = 3,
  parameter int unsigned ID  = 10,
  parameter int unsigned DATA_WIDTH = 16,
  parameter int unsigned NB_TAPS = 50
)
(
  // global signals
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  input  logic                                  test_mode_i,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  // tcdm master ports
  hci_core_intf.master                          tcdm[MP-1:0],
  // periph slave port
  hwpe_ctrl_intf_periph.slave                   periph
);

  logic enable, clear;
  fir_streamer_ctrl_t    streamer_ctrl;
  fir_streamer_flags_t   streamer_flags;
  fir_datapath_ctrl_t    datapath_ctrl;
  fir_tap_buffer_flags_t tap_buffer_flags;

  // Interface declarations
  hwpe_stream_intf_stream #( .DATA_WIDTH( DATA_WIDTH ) )         x_stream        ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH( DATA_WIDTH ) )         h_stream        ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH( DATA_WIDTH*NB_TAPS ) ) h_buffer_stream ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH( DATA_WIDTH ) )         y_stream        ( .clk ( clk_i ) );

  // Tap buffer
  fir_tap_buffer #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .NB_TAPS    ( NB_TAPS    )
  ) i_tap_buffer (
    .clk_i      ( clk_i            ),
    .rst_ni     ( rst_ni           ),
    .clear_i    ( clear            ),
    .h_serial   ( h_stream         ),
    .h_parallel ( h_buffer_stream  ),
    .flags_o    ( tap_buffer_flags )
  );

  // FIR datapath
  fir_datapath #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .NB_TAPS    ( NB_TAPS    )
  ) i_datapath (
    .clk_i   ( clk_i             ),
    .rst_ni  ( rst_ni            ),
    .clear_i ( clear             ),
    .ctrl_i  ( datapath_ctrl     ),
    .x       ( x_stream          ),
    .h       ( h_buffer_stream   ),
    .y       ( y_stream          )
  );

  // FIR streamer (load/store units)
  fir_streamer #(
    .MP ( MP )
  ) i_streamer (
    .clk_i            ( clk_i          ),
    .rst_ni           ( rst_ni         ),
    .test_mode_i      ( test_mode_i    ),
    .enable_i         ( enable         ),
    .clear_i          ( clear          ),
    .x_o              ( x_stream       ),
    .h_o              ( h_stream       ),
    .y_i              ( y_stream       ),
    .tcdm             ( tcdm           ),
    .ctrl_i           ( streamer_ctrl  ),
    .flags_o          ( streamer_flags )
  );

  // FIR controller and state-machine
  fir_ctrl #(
    .N_CORES   ( 2  ),
    .N_CONTEXT ( 2  ),
    .ID ( ID )
  ) i_ctrl (
    .clk_i              ( clk_i            ),
    .rst_ni             ( rst_ni           ),
    .test_mode_i        ( test_mode_i      ),
    .evt_o              ( evt_o            ),
    .clear_o            ( clear            ),
    .streamer_ctrl_o    ( streamer_ctrl    ),
    .streamer_flags_i   ( streamer_flags   ),
    .datapath_ctrl_o    ( datapath_ctrl    ),
    .tap_buffer_flags_i ( tap_buffer_flags ),
    .periph             ( periph           )
  );

  assign enable = 1'b1;

endmodule // fir_top
