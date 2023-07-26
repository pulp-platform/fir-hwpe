/*
 * fir_package.sv
 * Francesco Conti <fconti@iis.ee.ethz.ch>
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
 */

// Packages are collections of 

package fir_package;

  typedef enum {
    FSM_IDLE,
    FSM_TAP_BUFFER,
    FSM_COMPUTE
  } fir_fsm_state_t;

  // registers in register file
  parameter int unsigned FIR_REG_X_ADDR       = 0;
  parameter int unsigned FIR_REG_H_ADDR       = 1;
  parameter int unsigned FIR_REG_Y_ADDR       = 2;
  parameter int unsigned FIR_REG_SHIFT_LENGTH = 3;
  parameter int unsigned FIR_NB_REGS          = 4;

  parameter int unsigned X_STREAM_IDX = 0;
  parameter int unsigned H_STREAM_IDX = 1;
  parameter int unsigned Y_STREAM_IDX = 2;

  // "Flat" FIR HWPE configuration
  typedef struct packed {
    logic unsigned [31:0] x_addr;
    logic unsigned [31:0] h_addr;
    logic unsigned [31:0] y_addr;
    logic unsigned [4:0]  right_shift;
    logic unsigned [15:0] signal_length;
  } fir_config_t;

  typedef struct packed {
    hci_package::hci_streamer_ctrl_t   x_source_ctrl;
    hci_package::hci_streamer_ctrl_t   h_source_ctrl;
    hci_package::hci_streamer_ctrl_t   y_sink_ctrl;
    hwpe_stream_package::ctrl_serdes_t x_serialize_ctrl;
    hwpe_stream_package::ctrl_serdes_t h_serialize_ctrl;
    hwpe_stream_package::ctrl_serdes_t y_deserialize_ctrl;
  } fir_streamer_ctrl_t;

  typedef struct packed {
    hci_package::hci_streamer_flags_t x_source_flags;
    hci_package::hci_streamer_flags_t h_source_flags;
    hci_package::hci_streamer_flags_t y_sink_flags;
  } fir_streamer_flags_t;

  // typedef struct packed {
  // } fir_tap_buffer_ctrl_t;

  typedef struct packed {
    logic done;
  } fir_tap_buffer_flags_t;

  typedef struct packed {
    logic [5:0] right_shift;
  } fir_datapath_ctrl_t;

endpackage // fir_package
