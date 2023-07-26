/*
 * fir_streamer.sv
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

import fir_package::*;
import hwpe_stream_package::*;

module fir_streamer
#(
  parameter int unsigned MEM_WIDTH  = 32, // data width of the TCDM interface (32 bits)
  parameter int unsigned DATA_WIDTH = 16, // data width of the streams (16 bits)
  parameter int unsigned MP = 3           // number of master ports
)
(
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_mode_i,
  // local enable & clear
  input  logic                   enable_i,
  input  logic                   clear_i,

  // input x stream + handshake
  hwpe_stream_intf_stream.source x_o,
  // input h stream + handshake
  hwpe_stream_intf_stream.source h_o,
  // output y stream + handshake
  hwpe_stream_intf_stream.sink   y_i,

  // TCDM ports
  hwpe_stream_intf_tcdm.master tcdm [MP-1:0],

  // control channel
  input  fir_streamer_ctrl_t  ctrl_i,
  output fir_streamer_flags_t flags_o
);

  // Interface declarations
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) x_mem ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) h_mem ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) y_mem ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) x_split [MEM_WIDTH/DATA_WIDTH-1:0] ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) h_split [MEM_WIDTH/DATA_WIDTH-1:0] ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) y_split [MEM_WIDTH/DATA_WIDTH-1:0] ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) x_prefifo  ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) h_prefifo  ( .clk ( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( MEM_WIDTH ) ) y_postfifo ( .clk ( clk_i ) );
  hwpe_stream_intf_tcdm tcdm_fifo [MP-1:0] ( .clk ( clk_i ) );

  // Source and sink modules are used as interfaces between memory protocols
  // (in this case, HCI) and streaming protocols used inside the datapath in
  // the FIR HWPE. HCI-Core sources and sinks employ a 3D strided pattern address
  // generator to generate memory addresses for the TCDM, controlled by the
  // main HWPE FSM (see `fir_ctrl.sv` and in particular the `ctrl_streamer_t ctrl_i`
  // data structure).
  // HWPE-Streams produced/consumed by the source/sink modules work according to 
  // a streaming protocol and a data-flow paradigm.
  // x source
  hci_core_source #(
    .DATA_WIDTH          ( MEM_WIDTH ),
    .MISALIGNED_ACCESSES ( 0         )
  ) i_x_source (
    .clk_i              ( clk_i                  ),
    .rst_ni             ( rst_ni                 ),
    .test_mode_i        ( test_mode_i            ),
    .clear_i            ( clear_i                ),
    .enable_i           ( enable_i               ),
    .tcdm               ( tcdm_fifo[X_STREAM_IDX]),
    .stream             ( x_mem                  ),
    .ctrl_i             ( ctrl_i.x_source_ctrl   ),
    .flags_o            ( flags_o.x_source_flags )
  );
  // h source
  hci_core_source #(
    .DATA_WIDTH          ( MEM_WIDTH ),
    .MISALIGNED_ACCESSES ( 0         )
  ) i_h_source (
    .clk_i              ( clk_i                  ),
    .rst_ni             ( rst_ni                 ),
    .test_mode_i        ( test_mode_i            ),
    .clear_i            ( clear_i                ),
    .enable_i           ( enable_i               ),
    .tcdm               ( tcdm_fifo[H_STREAM_IDX]),
    .stream             ( h_mem                  ),
    .ctrl_i             ( ctrl_i.h_source_ctrl   ),
    .flags_o            ( flags_o.h_source_flags )
  );
  // y sink
  hci_core_sink #(
    .DATA_WIDTH          ( MEM_WIDTH ),
    .MISALIGNED_ACCESSES ( 0         )
  ) i_y_sink (
    .clk_i       ( clk_i                  ),
    .rst_ni      ( rst_ni                 ),
    .test_mode_i ( test_mode_i            ),
    .clear_i     ( clear_i                ),
    .enable_i    ( enable_i               ),
    .tcdm        ( tcdm_fifo[Y_STREAM_IDX]),
    .stream      ( y_postfifo             ),
    .ctrl_i      ( ctrl_i.y_sink_ctrl     ),
    .flags_o     ( flags_o.y_sink_flags   )
  );

  // TCDM-side FIFOs (here mainly as an example). We may need these
  // in "real" designs to decouple the internal datapath from memory,
  // cutting dangerously long combinational paths. They are also useful
  // to partially amortize memory stalls. HWPE-Streams on the datapath
  // side of the streamer are latency-insensitive and well suited for
  // being enqueued to/dequeued from FIFOs. HCI access "streams" are
  // designed to maintain this desirable property on the memory side.
  // x fifo
  hci_core_fifo #(
    .FIFO_DEPTH ( 4         ),
    .DW         ( MEM_WIDTH )
  ) i_x_tcdm_fifo (
    .clk_i       ( clk_i                  ),
    .rst_ni      ( rst_ni                 ),
    .clear_i     ( clear_i                ),
    .flags_o     (                        ),
    .tcdm_slave  ( tcdm_fifo[X_STREAM_IDX]),
    .tcdm_master ( tcdm[X_STREAM_IDX]     )
  );
  // h fifo
  hci_core_fifo #(
    .FIFO_DEPTH ( 4         ),
    .DW         ( MEM_WIDTH )
  ) i_h_tcdm_fifo (
    .clk_i       ( clk_i                  ),
    .rst_ni      ( rst_ni                 ),
    .clear_i     ( clear_i                ),
    .flags_o     (                        ),
    .tcdm_slave  ( tcdm_fifo[H_STREAM_IDX]),
    .tcdm_master ( tcdm[H_STREAM_IDX]     )
  );
  // y fifo
  hci_core_fifo #(
    .FIFO_DEPTH ( 4         ),
    .DW         ( MEM_WIDTH )
  ) i_y_tcdm_fifo (
    .clk_i       ( clk_i                  ),
    .rst_ni      ( rst_ni                 ),
    .clear_i     ( clear_i                ),
    .flags_o     (                        ),
    .tcdm_slave  ( tcdm_fifo[Y_STREAM_IDX]),
    .tcdm_master ( tcdm[Y_STREAM_IDX]     )
  );

  // As the memory and datapath sides use different data sizes, we need
  // to split and serialize incoming streams and deserialize and merge
  // outgoing ones.
  // x split
  hwpe_stream_split #(
    .NB_OUT_STREAMS ( MEM_WIDTH/DATA_WIDTH ),
    .DATA_WIDTH_IN  ( MEM_WIDTH            )
  ) i_x_split (
    .clk_i       ( clk_i   ),
    .rst_ni      ( rst_ni  ),
    .clear_i     ( clear_i ),
    .push_i      ( x_mem   ),
    .pop_o       ( x_split )
  );
  // x serialize
  hwpe_stream_serialize #(
    .NB_IN_STREAMS ( MEM_WIDTH/DATA_WIDTH ),
    .DATA_WIDTH    ( DATA_WIDTH           )
  ) i_x_serialize (
    .clk_i       ( clk_i                   ),
    .rst_ni      ( rst_ni                  ),
    .clear_i     ( clear_i                 ),
    .ctrl_i      ( ctrl_i.x_serialize_ctrl ),
    .push_i      ( x_split                 ),
    .pop_o       ( x_prefifo               )
  );
  // h split
  hwpe_stream_split #(
    .NB_OUT_STREAMS ( MEM_WIDTH/DATA_WIDTH ),
    .DATA_WIDTH_IN  ( MEM_WIDTH            )
  ) i_h_split (
    .clk_i       ( clk_i   ),
    .rst_ni      ( rst_ni  ),
    .clear_i     ( clear_i ),
    .push_i      ( h_mem   ),
    .pop_o       ( h_split )
  );
  // h serialize
  hwpe_stream_serialize #(
    .NB_IN_STREAMS ( MEM_WIDTH/DATA_WIDTH ),
    .DATA_WIDTH    ( DATA_WIDTH           )
  ) i_h_serialize (
    .clk_i       ( clk_i                   ),
    .rst_ni      ( rst_ni                  ),
    .clear_i     ( clear_i                 ),
    .ctrl_i      ( ctrl_i.h_serialize_ctrl ),
    .push_i      ( h_split                 ),
    .pop_o       ( h_prefifo               )
  );
  // y deserialize
  hwpe_stream_deserialize #(
    .NB_OUT_STREAMS ( MEM_WIDTH/DATA_WIDTH ),
    .DATA_WIDTH     ( DATA_WIDTH           )
  ) i_y_deserialize (
    .clk_i       ( clk_i                     ),
    .rst_ni      ( rst_ni                    ),
    .clear_i     ( clear_i                   ),
    .ctrl_i      ( ctrl_i.y_deserialize_ctrl ),
    .push_i      ( y_postfifo                ),
    .pop_o       ( y_split                   )
  );
  // y merge
  hwpe_stream_merge #(
    .NB_IN_STREAMS ( MEM_WIDTH/DATA_WIDTH ),
    .DATA_WIDTH    ( DATA_WIDTH           )
  ) i_y_merge (
    .clk_i       ( clk_i   ),
    .rst_ni      ( rst_ni  ),
    .clear_i     ( clear_i ),
    .push_i      ( y_split ),
    .pop_o       ( y_mem   )
  );

  // Datapath-side FIFOs. These are used to decouple the datapath from
  // the streamer. It is generally desirable to decouple at least a bit
  // as it helps in the design of datapath controllers - the hardest
  // part of an accelerator's design.
  // Here we enqueue/dequeue HWPE-Streams with the final data-width
  // `DATA_WIDTH` -- by default, 16 bits -- after being split and serialized.
  hwpe_stream_fifo #(
    .DATA_WIDTH( DATA_WIDTH ),
    .FIFO_DEPTH( 2          ),
    .LATCH_FIFO( 0          )
  ) i_x_fifo (
    .clk_i   ( clk_i     ),
    .rst_ni  ( rst_ni    ),
    .clear_i ( clear_i   ),
    .push_i  ( x_prefifo ),
    .pop_o   ( x_o       ),
    .flags_o (           )
  );

  hwpe_stream_fifo #(
    .DATA_WIDTH( DATA_WIDTH ),
    .FIFO_DEPTH( 2          ),
    .LATCH_FIFO( 0          )
  ) i_h_fifo (
    .clk_i   ( clk_i     ),
    .rst_ni  ( rst_ni    ),
    .clear_i ( clear_i   ),
    .push_i  ( h_prefifo ),
    .pop_o   ( h_o       ),
    .flags_o (           )
  );

  hwpe_stream_fifo #(
    .DATA_WIDTH( DATA_WIDTH ),
    .FIFO_DEPTH( 2          ),
    .LATCH_FIFO( 0          )
  ) i_y_fifo (
    .clk_i   ( clk_i      ),
    .rst_ni  ( rst_ni     ),
    .clear_i ( clear_i    ),
    .push_i  ( y_i        ),
    .pop_o   ( y_postfifo ),
    .flags_o (            )
  );

endmodule // fir_streamer
