/*
 * tb_fir_datapath.sv
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
 */

timeunit 1ps;
timeprecision 1ps;

module tb_fir_datapath;

  // parameters
  parameter PROB_STALL_GEN  = 0.1;
  parameter PROB_STALL_RECV = 0.1;
  parameter RESERVOIR_SIZE_X = 512;
  parameter RESERVOIR_SIZE_H = 1;
  parameter RECEIVER_SIZE_Y  = 512;
  parameter STIM_FILE_X = "x_stim.txt";
  parameter STIM_FILE_H = "h_stim.txt";
  parameter STIM_FILE_Y = "y_gold.txt";
  parameter DATA_WIDTH = 16;
  parameter NB_TAPS = 50;

  // ATI timing parameters.
  localparam TCP = 1.0ns; // clock period, 1 GHz clock
  localparam TA  = 0.2ns; // application time
  localparam TT  = 0.8ns; // test time

  localparam DATA_WIDTH_H = DATA_WIDTH*NB_TAPS;

  // global signals
  logic clk_i  = '0;
  logic rst_ni = '1;

  // Performs one entire clock cycle.
  task cycle;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TCP;
  endtask

  // The following task schedules the clock edges for the next cycle and
  // advances the simulation time to that cycles test time (localparam TT)
  // according to ATI timings.
  task cycle_start;
    clk_i <= #(TCP/2) 0;
    clk_i <= #TCP 1;
    #TT;
  endtask

  // The following task finishes a clock cycle previously started with
  // cycle_start by advancing the simulation time to the end of the cycle.
  task cycle_end;
    #(TCP-TT);
  endtask

  // local enable
  logic enable_i = '1;
  logic clear_i  = '0;
  // end of test signals
  logic eot_gen, eot_recv;
  // force signals
  logic force_invalid_gen = 1'b1, force_valid_gen = 1'b0;
  logic force_unready_gen = 1'b1, force_ready_gen = 1'b0;

  // HWPE-Stream interfaces
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) x_stream (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) h_stream (
    .clk ( clk_i )
  );
  hwpe_stream_intf_stream #(
    .DATA_WIDTH ( DATA_WIDTH )
  ) y_stream (
    .clk ( clk_i )
  );

  // RNG signals
  int rng_gen, rng_recv;

  // HWPE-Stream traffic generators
  hwpe_stream_traffic_gen #(
    .STIM_FILE      ( STIM_FILE_X      ),
    .DATA_WIDTH     ( DATA_WIDTH       ),
    .RESERVOIR_SIZE ( RESERVOIR_SIZE_X ),
    .RANDOM_STROBE  ( 1'b0             ),
    .PROB_STALL     ( PROB_STALL_GEN   )
  ) i_traffic_gen_x (
    .clk_i          ( clk_i             ),
    .rst_ni         ( rst_ni            ),
    .randomize_i    ( 1'b0              ),
    .force_invalid_i( force_invalid_gen ),
    .force_valid_i  ( force_valid_gen   ),
    .eot_o          ( eot_gen           ),
    .rng_i          ( rng_gen           ),
    .pop_o          ( x_stream          )
  );

  hwpe_stream_traffic_gen #(
    .STIM_FILE      ( STIM_FILE_H        ),
    .DATA_WIDTH     ( DATA_WIDTH_H       ),
    .RESERVOIR_SIZE ( RESERVOIR_SIZE_H   ),
    .RANDOM_STROBE  ( 1'b0               ),
    .PROB_STALL     ( PROB_STALL_GEN     )
  ) i_traffic_gen_h (
    .clk_i          ( clk_i             ),
    .rst_ni         ( rst_ni            ),
    .randomize_i    ( 1'b0              ),
    .force_invalid_i( force_invalid_gen ),
    .force_valid_i  ( force_valid_gen   ),
    .eot_o          ( eot_gen           ),
    .rng_i          ( rng_gen           ),
    .pop_o          ( h_stream          )
  );

  // Design Under Test (FIR)
  fir_datapath #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .NB_TAPS    ( NB_TAPS    )
  ) i_dut (
    .clk_i   ( clk_i    ),
    .rst_ni  ( rst_ni   ),
    .clear_i ( clear_i  ),
    .x       ( x_stream ),
    .h       ( h_stream ),
    .y       ( y_stream )
  );

  // HWPE-Stream traffic receiver
  hwpe_stream_traffic_recv #(
    .STIM_FILE      ( STIM_FILE_Y     ),
    .DATA_WIDTH     ( DATA_WIDTH      ),
    .RESERVOIR_SIZE ( RECEIVER_SIZE_Y ),
    .CHECK          ( 1'b1            ),
    .PROB_STALL     ( PROB_STALL_RECV )
  ) i_traffic_recv_y (
    .clk_i          ( clk_i             ),
    .rst_ni         ( rst_ni            ),
    .force_unready_i( force_unready_gen ),
    .force_ready_i  ( force_ready_gen   ),
    .enable_i       ( enable_i          ),
    .eot_o          ( eot_recv          ),
    .rng_i          ( rng_recv          ),
    .push_i         ( y_stream          )
  );

  // RNG
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      rng_gen <= '0;
      rng_recv <= '0;
    end
    else begin
      rng_gen  <= $urandom_range(0, 1000);
      rng_recv <= $urandom_range(0, 1000);
    end
  end

  // test reset & clock generation loop
  initial begin
    #(20*TCP);

    // Reset phase.
    rst_ni <= #TA 1'b0;
    #(20*TCP);
    rst_ni <= #TA 1'b1;

    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b0;
    for (int i = 0; i < 10; i++)
      cycle();
    rst_ni <= #TA 1'b1;

    while(1) begin
      cycle();
    end

  end

  initial begin

    integer id;

    #(70*TCP);
    // release unready
    force_unready_gen <= #TA 1'b0;
    #(2*TCP);
    // release invalid
    force_invalid_gen <= #TA 1'b0;

    while(~eot_gen | ~eot_recv)
      #(TCP);
    $display("Testbench: Test finished.");
    $finish;

  end

endmodule // tb_fir_datapath

