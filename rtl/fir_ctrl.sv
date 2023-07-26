/* 
 * fir_ctrl.sv
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

module fir_ctrl
  import fir_package::*;
  import hwpe_ctrl_package::*;
#(
  parameter int unsigned N_CORES   = 2,
  parameter int unsigned N_CONTEXT = 2,
  parameter int unsigned NB_TAPS   = 50,
  parameter int unsigned ID        = 10
)
(
  // global signals
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  input  logic                                  test_mode_i,
  output logic                                  clear_o,
  // events
  output logic [N_CORES-1:0][REGFILE_N_EVT-1:0] evt_o,
  // ctrl & flags
  output fir_streamer_ctrl_t                    streamer_ctrl_o,
  input  fir_streamer_flags_t                   streamer_flags_i,
  output fir_datapath_ctrl_t                    datapath_ctrl_o,
  input  fir_tap_buffer_flags_t                 tap_buffer_flags_i,
  // periph slave port
  hwpe_ctrl_intf_periph.slave                   periph
);

  // The controller is often the most complex piece of logic in a HWPE (even
  // a quite simple one). It is typically divided into several submodules:
  //  - a "target" or "slave" interface to enable programming the HWPE. 
  //    We currently generally rely on memory-mapped control, but this could
  //    also be replaced with other mechanisms, such as ISA extensions.
  //    The slave hosts a physical register file to store the configuration
  //    parameters as offloaded.
  //  - a "config" data structure. This is a handy abstraction of the content
  //    of the physical register file, which contains in a "flat" format
  //    all of the information needed to control the HWPE.
  //    This config data structure is not strictly necessary, but it makes
  //    the controller much tidier, more readable and maintainable.
  //  - a finite-state machine (FSM) that controls the overall state of the 
  //    accelerator. This can be very simple (IDLE/RUN) or very complex,
  //    including hierarchical FSMs that include, for example, microcoded loops
  //    (through the `hwpe_ctrl_uloop` module). In general, the more control
  //    is distributed in the data-flow datapath modules, the less is centralized
  //    here: but we always need at least a minimal amount of central control.
  //    The FSM uses information from the config data structure, the `flags` incoming
  //    from the datapath and streamer, and the internal state to drive the 
  //    `ctrl` signals outgoing towards the datapath and streamer.

  hwpe_ctrl_package::ctrl_slave_t   slave_ctrl;
  hwpe_ctrl_package::flags_slave_t  slave_flags;
  hwpe_ctrl_package::ctrl_regfile_t reg_file;

  fir_config_t config_;

  // Peripheral slave & register file
  // The main parameters necessary to instantiate the register file are the following:
  //   - N_CORES: number of cores in the system expected to control the HWPE
  //   - N_CONTEXT: number of contexts, i.e., of jobs that can be offloaded to the
  //     HWPE while it is running (2 in most cases!)
  //   - N_IO_REGS: unfortunate naming, this is actually the number of registers per
  //     context
  //   - N_GENERIC_REGS: number of generic registers (common to every context)
  hwpe_ctrl_slave #(
    .N_CORES        ( N_CORES     ),
    .N_CONTEXT      ( N_CONTEXT   ),
    .N_IO_REGS      ( FIR_NB_REGS ),
    .N_GENERIC_REGS ( 0           ),
    .ID_WIDTH       ( ID          )
  ) i_slave (
    .clk_i    ( clk_i       ),
    .rst_ni   ( rst_ni      ),
    .clear_o  ( clear_o     ),
    .cfg      ( periph      ),
    .ctrl_i   ( slave_ctrl  ),
    .flags_o  ( slave_flags ),
    .reg_file ( reg_file    )
  );
  assign evt_o = slave_flags.evt;

  // Config <-> register file mappings
  // In this example, the mapping is relatively trivial, but it can become
  // more interesting for example if we share the same physical register with 
  // multiple fields, or if we need to perform some kind of translation.
  assign config_.x_addr = reg_file.hwpe_params[FIR_REG_X_ADDR];
  assign config_.h_addr = reg_file.hwpe_params[FIR_REG_H_ADDR];
  assign config_.y_addr = reg_file.hwpe_params[FIR_REG_Y_ADDR];
  assign config_.right_shift = reg_file.hwpe_params[FIR_REG_SHIFT_LENGTH][5:0];
  assign config_.signal_length = reg_file.hwpe_params[FIR_REG_SHIFT_LENGTH][31:16];

  // Main FSM
  // Here we employ something similar to a "3-process" FSM style: one
  // (minimal) sequential process, one state-update combinational process,
  // and many separate state-dependent `assign` statements to compute the
  // "output" of the state machine (i.e., control signals).
  // This style, which is by no means the only "correct" way to write such
  // an FSM, was chosen due to the following advantages:
  //  - state-update and output computation are clearly separated, which
  //    favours readability and maintainability
  //  - no combinational logic in the sequential process
  //  - "atomic" assign statements drive each control signal separately,
  //    making it easier to identify and debug issues
  // In this case, we use a Mealy machine (i.e., output dependent on input
  // + state in a combinational fashion), as it often leads to a much
  // simpler FSM (see https://en.wikipedia.org/wiki/Mealy_machine).
  // For this reason, despite what is taught in basic logic networks courses,
  // Mealy FSMs are often preferred in digital design.
  // Notice, however, that the choice of a Mealy machine can also introduce
  // problems. In particular, there are combinational paths that start from
  // an incoming `flags` signal in the datapath, go through the FSM, and
  // then back to the datapath in the form of `ctrl` signals. This can lead
  // to timing issues, and - if the `flags` are improperly generated - even
  // to combinational timing loops.
  // There are several possible solutions, including:
  //  - designing a Moore machine instead.
  //  - registering the control signals, which is essentially the same as
  //    using a Moore machine, but generally easier to design.
  //  - removing specific combinational paths on a case-by-case basis after
  //    a preliminary synthesis to identify "dangerous" paths.
  
  fir_fsm_state_t state_d, state_q;

  always_ff @(posedge clk_i or negedge rst_ni)
  begin : main_fsm_seq
    if(~rst_ni) begin
      state_q <= FSM_IDLE;
    end
    else if(clear_o) begin
      state_q <= FSM_IDLE;
    end
    else begin
      state_q <= state_d;
    end
  end

  always_comb
  begin : main_fsm_comb
    state_d = state_q;
    case(state_q)
      FSM_IDLE: begin
        if(slave_flags.start) begin
          state_d = FSM_TAP_BUFFER;
        end
      end
      FSM_TAP_BUFFER: begin
        if(tap_buffer_flags_i.done) begin
          state_d = FSM_COMPUTE;
        end
      end
      FSM_COMPUTE: begin
        if(streamer_flags_i.y_sink_flags.done) begin
          state_d = FSM_IDLE;
        end
      end
    endcase
  end

  // Control signals

  // X stream
  // We can start the X streamer immediately, even in the FSM_TAP_BUFFER state
  // (where the datapath is not yet active), because the X streamer will simply
  // stall waiting for a `ready` from the datapath when all FIFOs are full.
  assign streamer_ctrl_o.x_source_ctrl.req_start = (state_d == FSM_TAP_BUFFER && state_q == FSM_IDLE) ? 1'b1 : 1'b0;
  assign streamer_ctrl_o.x_source_ctrl.addressgen_ctrl.base_addr = config_.x_addr; // directly from configuration
  assign streamer_ctrl_o.x_source_ctrl.addressgen_ctrl.tot_len   = config_.signal_length >> 1 + (config_.signal_length % 2 != '0 ? 1 : 0); // signal_length is in 16-bit words, tot_len in 32-bit words
  assign streamer_ctrl_o.x_source_ctrl.addressgen_ctrl.d0_len    = config_.signal_length >> 1 + (config_.signal_length % 2 != '0 ? 1 : 0); // signal_length is in 16-bit words, d0_len in 32-bit words
  assign streamer_ctrl_o.x_source_ctrl.addressgen_ctrl.d0_stride = 4; // 4 bytes per 32-bit word
  assign streamer_ctrl_o.x_source_ctrl.addressgen_ctrl.d1_len    = 1;
  assign streamer_ctrl_o.x_source_ctrl.addressgen_ctrl.d1_stride = 0;
  assign streamer_ctrl_o.x_source_ctrl.addressgen_ctrl.d2_stride = 0;
  assign streamer_ctrl_o.x_source_ctrl.addressgen_ctrl.dim_enable_1h = hwpe_stream_package::HWPE_STREAM_ADDRESSGEN_1D; // single-dimension counting

  assign streamer_ctrl_o.x_serialize_ctrl.first_stream       = 0;
  assign streamer_ctrl_o.x_serialize_ctrl.clear_serdes_state = FSM_IDLE;
  assign streamer_ctrl_o.x_serialize_ctrl.nb_contig_m1       = 1;

  // H stream
  // We start the H streamer as soon as possible, but this will leave a bit of 
  // latency to start fetching data from memory, and get the results back before
  // the tap buffer "really" works in the FSM_TAP_BUFFER state.
  assign streamer_ctrl_o.h_source_ctrl.req_start = (state_d == FSM_TAP_BUFFER && state_q == FSM_IDLE) ? 1'b1 : 1'b0;
  assign streamer_ctrl_o.h_source_ctrl.addressgen_ctrl.base_addr = config_.h_addr;
  assign streamer_ctrl_o.h_source_ctrl.addressgen_ctrl.tot_len   = NB_TAPS >> 1 + (NB_TAPS %2 != '0 ? 1 : 0); // NB_TAPS is in 16-bit words, tot_len in 32-bit words
  assign streamer_ctrl_o.h_source_ctrl.addressgen_ctrl.d0_len    = NB_TAPS >> 1 + (NB_TAPS %2 != '0 ? 1 : 0); // NB_TAPS is in 16-bit words, tot_len in 32-bit words
  assign streamer_ctrl_o.h_source_ctrl.addressgen_ctrl.d0_stride = 4; // 4 bytes per 32-bit word
  assign streamer_ctrl_o.h_source_ctrl.addressgen_ctrl.d1_len    = 1;
  assign streamer_ctrl_o.h_source_ctrl.addressgen_ctrl.d1_stride = 0;
  assign streamer_ctrl_o.h_source_ctrl.addressgen_ctrl.d2_stride = 0;
  assign streamer_ctrl_o.h_source_ctrl.addressgen_ctrl.dim_enable_1h = hwpe_stream_package::HWPE_STREAM_ADDRESSGEN_1D; // single-dimension counting

  assign streamer_ctrl_o.h_serialize_ctrl.first_stream       = 0;
  assign streamer_ctrl_o.h_serialize_ctrl.clear_serdes_state = FSM_IDLE;
  assign streamer_ctrl_o.h_serialize_ctrl.nb_contig_m1       = 1;

  // Y stream
  // We start even the Y streamer immediately at the start. It will really start
  // working only when the outputs of the datapath are valid.
  assign streamer_ctrl_o.y_sink_ctrl.req_start = (state_d == FSM_TAP_BUFFER && state_q == FSM_IDLE) ? 1'b1 : 1'b0;
  assign streamer_ctrl_o.y_sink_ctrl.addressgen_ctrl.base_addr = config_.y_addr;
  assign streamer_ctrl_o.y_sink_ctrl.addressgen_ctrl.tot_len   = config_.signal_length >> 1 + (config_.signal_length % 2 != '0 ? 1 : 0); // signal_length is in 16-bit words, tot_len in 32-bit words
  assign streamer_ctrl_o.y_sink_ctrl.addressgen_ctrl.d0_len    = config_.signal_length >> 1 + (config_.signal_length % 2 != '0 ? 1 : 0); // signal_length is in 16-bit words, d0_len in 32-bit words
  assign streamer_ctrl_o.y_sink_ctrl.addressgen_ctrl.d0_stride = 4; // 4 bytes per 32-bit word
  assign streamer_ctrl_o.y_sink_ctrl.addressgen_ctrl.d1_len    = 1;
  assign streamer_ctrl_o.y_sink_ctrl.addressgen_ctrl.d1_stride = 0;
  assign streamer_ctrl_o.y_sink_ctrl.addressgen_ctrl.d2_stride = 0;
  assign streamer_ctrl_o.y_sink_ctrl.addressgen_ctrl.dim_enable_1h = hwpe_stream_package::HWPE_STREAM_ADDRESSGEN_1D; // single-dimension counting

  assign streamer_ctrl_o.y_deserialize_ctrl.first_stream       = 0;
  assign streamer_ctrl_o.y_deserialize_ctrl.clear_serdes_state = FSM_IDLE;
  assign streamer_ctrl_o.y_deserialize_ctrl.nb_contig_m1       = 1;

  // Simply propagate the correct right shift to the datapath
  assign datapath_ctrl_o.right_shift = config_.right_shift;

endmodule // fir_ctrl
