/*
 * fir_tap_buffer.sv
 * Francesco Conti <f.conti@unibo.it>
 *
 * Copyright (C) 2018-2023 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * The following datapath implements a direct-form FIR filter.
 */

module fir_tap_buffer
  import fir_package::*;
#(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned NB_TAPS = 2
)
(
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,
  // input x stream
  hwpe_stream_intf_stream.sink   h_serial,
  // output y stream
  hwpe_stream_intf_stream.source h_parallel
);

  // Unrolled HWPE-Stream signals
  logic [DATA_WIDTH-1:0] h_serial_data;
  logic                  h_serial_valid;
  logic                  h_serial_ready;
  logic                  h_serial_handshake;
  logic                               h_parallel_valid;
  logic                               h_parallel_ready;
  logic                               h_parallel_handshake;

  // Counter signals
  logic [$clog2(NB_TAPS):0] tap_counter_d, tap_counter_q;
  logic                     tap_counter_en_d, tap_counter_clr_d;
  logic [NB_TAPS-1:0][DATA_WIDTH-1:0] h_parallel_q;

  // Unroll all HWPE-Stream sink modports into `logic` bit vectors for convenience.
  // h_serial out --> in
  assign h_serial_data     = h_serial.data;
  assign h_serial_valid    = h_serial.valid;
  // h_serial in --> out
  assign h_serial.ready    = h_serial_ready;
  // h_serial handshake
  assign h_serial_handshake = h_serial_valid & h_serial_ready;

  // Tap counter
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      tap_counter_q <= '0;
    end
    else if(tap_counter_clr_d) begin
      tap_counter_q <= '0;
    end
    else if(tap_counter_en_d) begin
      tap_counter_q <= tap_counter_d;
    end
  end
  assign tap_counter_d = tap_counter_q + 1;

  // Any serialized h handshake increases the counter value
  assign tap_counter_en_d  = h_serial_handshake;

  // The counter is cleared only when `clear_i` is asserted.
  assign tap_counter_clr_d = clear_i; // | (tap_counter_q == NB_TAPS-1);

  // Buffer tap values in a set of registers
  always_ff @(posedge clk_i or negedge rst_ni)
  begin
    if(~rst_ni) begin
      h_parallel_q[tap_counter_q] <= '0;
    end
    else if(clear_i) begin
      h_parallel_q[tap_counter_q] <= '0;
    end
    else if(h_serial_handshake) begin
      h_parallel_q[tap_counter_q] <= h_serial_data;
    end
  end

  // The h_parallel stream is valid when the counter reaches NB_TAPS.
  // Here, compared with the fir_datapath, we use a counter instead of a shift register
  // to generate the valid signal -- it simply makes more sense as the validity
  // of the parallel taps is achieved when the tap_counter is at NB_TAPS.
  // This means that it will stop being valid as soon as new taps are streamed in;
  // there is no further "internal" control.
  assign h_parallel_valid = (tap_counter_q == NB_TAPS);

  // Unroll all HWPE-Stream source modports into `logic` bit vectors for convenience.
  // h_parallel out --> in
  assign h_parallel.data     = h_parallel_q;
  assign h_parallel.valid    = h_parallel_valid;
  // h_parallel in --> out
  assign h_parallel_ready    = h_parallel.ready;
  // h_parallel handshake
  assign h_parallel_handshake = h_parallel_valid & h_parallel_ready;

  // The h_serial stream is always ready
  assign h_serial_ready = 1'b1;

`ifndef SYNTHESIS
`ifndef VERILATOR
  // use assertions to check that the streams have the correct width
  assert property (@(posedge clk_i) disable iff(~rst_ni)
    (h_parallel.DATA_WIDTH) == (DATA_WIDTH*NB_TAPS));
  assert property (@(posedge clk_i) disable iff(~rst_ni)
    (h_serial.DATA_WIDTH) == (DATA_WIDTH));
`endif
`endif

endmodule // fir_tap_buffer
