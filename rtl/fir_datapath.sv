/*
 * fir_datapath.sv
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

module fir_datapath
  import fir_package::*;
#(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned NB_TAPS = 50
)
(
  // global signals
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,
  input  fir_datapath_ctrl_t     ctrl_i,
  // input x stream
  hwpe_stream_intf_stream.sink   x,
  // input h stream
  hwpe_stream_intf_stream.sink   h,
  // output y stream
  hwpe_stream_intf_stream.source y
);

  // A design choice of this accelerator is that at the interface of modules only a few categories
  // of signals are exposed:
  //  - global signals (`clk_i`, `rst_ni`)
  //  - HWPE-Stream interfaces (`x`, `h`, `y`)
  //  - an input control packed struct (`ctrl_i`) and an output flags packed struct (`flags_o`)
  // The `flags_o` packed struct encapsulates all of the information about the internal state
  // of the module that must be exposed to the controller, and the `ctrl_i` all the control
  // information necessary for configuring the current module. In this way, it is possible to
  // make significant changes to the control interface (which can typically propagate through
  // a large hierarchy of modules) without manually modifying the interface in all modules; it
  // is sufficient to change the packed struct definition in the package where it is defined.
  // Packed structs are essentially bit vectors where bit fields have a name, and as such
  // are easily synthesizable and much more readable than Verilog-2001-ish code.

  // Unrolled HWPE-Stream signals
  logic signed [DATA_WIDTH-1:0] x_data,      y_data;
  logic                         x_valid,     y_valid;
  logic                         x_ready,     y_ready;
  logic                         x_handshake, y_handshake;
  logic signed [NB_TAPS-1:0][DATA_WIDTH-1:0] h_data;
  logic                                      h_valid;
  logic                                      h_ready;
  logic                                      h_handshake;
  // delayed inputs and valids
  logic signed [NB_TAPS-1:0][DATA_WIDTH-1:0] x_delay_q;
  logic        [NB_TAPS-1:0]                 x_delay_valid_q;
  // FIR products
  logic signed [NB_TAPS-1:0][DATA_WIDTH*2-1:0]    prod_d;
  logic signed [DATA_WIDTH*2+$clog2(NB_TAPS)-1:0] y_nonshifted_d;

  // Unroll all HWPE-Stream sink modports into `logic` bit vectors for convenience.
  // Notice that for simple combinational logic we tend to prefer `assign` to `always_comb`.
  // This is a style choice, which makes the code more aligned to an RTL style and less
  // to a behavioral one.
  // x out --> in
  assign x_data  = x.data;
  assign x_valid = x.valid;
  // x in --> out
  assign x.ready = x_ready;
  // x handshake
  assign x_handshake = x_valid & x_ready;
  // h out --> in
  assign h_data  = h.data;
  assign h_valid = h.valid;
  // h in --> out
  assign h.ready = h_ready;
  // h handshake
  assign h_handshake = h_valid & h_ready;
  
  // The first delayed x is actually not delayed at all
  assign x_delay_q[0]       = x_data;

  // We consider the first delayed x valid if also the tap is valid
  assign x_delay_valid_q[0] = x_valid & h_valid;

  // This chain of delayed x values implements a shift register enabled by the handshake x_valid & x_ready.
  // Note that we favor an implementation based on generate-loops of simple blocks (flip-flops) rather than
  // a single big `always_ff` block with a loop inside. This is mainly a matter of style, but it has
  // the advantage that it directly corresponds to an RTL description as opposed to a behavioral one.
  // So there will be less surprises when synthesizing this!
  // Another important point is that we choose to propagate the `valid` along with the data through
  // the shift register. We only need the actual `valid` for the last tap, so an alternative choice
  // would be to propagate only the data and use a separate counter for handshakes, activating the
  // "last `valid`" after `NB_TAPS-1` handshakes.
  for (genvar ii=1; ii<NB_TAPS; ii++) begin : x_delay_gen
    always_ff @(posedge clk_i or negedge rst_ni)
    begin
      if(~rst_ni) begin
        x_delay_q[ii]       <= '0;
        x_delay_valid_q[ii] <= '0;
      end
      else if(clear_i) begin
        x_delay_q[ii]       <= '0;
        x_delay_valid_q[ii] <= '0;
      end
      else if(x_handshake & h_handshake) begin
        x_delay_q[ii]       <= x_delay_q[ii-1];
        x_delay_valid_q[ii] <= x_delay_valid_q[ii-1];
      end
    end
  end

  // The product between the delayed x and the h coefficients is computed in parallel.
  // Taps arrive parallelly in `h_data`.
  // We also use generate-loops here.
  // Notice the usage of the `signed'` cast operator:
  //  - data extracted with a bit-slice or a part-select is unsigned by default, so it
  //    needs to be casted to signed
  //  - in any case, the operators are 16-bit, therefore the result of the multiplication
  //    needs to be casted to DATA_WIDTH (>16-bit). Here we assume that DATA_WIDTH<=64,
  //    thus the simplest way to cast it up to the final size in a sign-preserving way
  //    is to multiply the product by 64'sh1.
  for (genvar ii=0; ii<NB_TAPS; ii++) begin : product_gen
    assign prod_d[ii] = 64'sh1 * signed'(h_data[ii]) * signed'(x_delay_q[ii]);
  end

  // The sum of all products is computed as a chain of additions. In this case, we preferred
  // a more behavioral style: we leave to the synthesis tool the task of inferring the appropriate
  // adder tree architecture.
  // In simulation, the value of `y_nonshifted_d` will vary `NB_TAPS` times in as many delta cycles
  // when the `always_comb` block is woken-up by a change in one of the `prod_d` values.
  // In synthesis, the starting implementation will be a chain of adders, but the synthesis tool
  // will likely replace this with a more efficient adder tree early in the synthesis.
  // This kind of transformations can happen with any coding style (RTL or behavioral), but here
  // we prefer to *emphasize* the fact that we are not interested in the specific implementation.
  // In many HWPEs, we follow a consistent style: we use single-letter index variables (`i`) for
  // these behavioral loops, and multi-letter index variables (`ii`) for generate-loops.
  always_comb
  begin 
    y_nonshifted_d = 64'sh0 + signed'(prod_d[0]);
    for (int i=1; i<NB_TAPS; i++) begin
      y_nonshifted_d += 64'sh0 + signed'(prod_d[i]);
    end
  end

  // Right-shift y so that it is aligned to the original data width.
  // Notice the usage of the `>>>` operator, which is a logical shift (i.e., it preservs sign)
  // and of the `signed` cast operator.
  assign y_data  = signed'(y_nonshifted_d) >>> ctrl_i.right_shift;
  assign y_valid = x_valid & h_valid;
  
  // Unroll the HWPE-Stream source modports into `logic` bit vectors for convenience.
  // y in --> out
  assign y.data  = y_data;
  assign y.strb  = '1;
  assign y.valid = y_valid;
  // y out --> in
  assign y_ready = y.ready;
  // y handshake
  assign y_handshake = y_valid & y_ready;

  // How to assign `ready` signals? This is often more challenging then `valid`s.
  // To avoid deadlocks, in HWPE-Streams the following rules have to be followed:
  //  1) transition of `ready` CAN depend on the current state of `valid`
  //  2) transition of `valid` CAN NOT depend on the current state of `ready`
  //  3) transition 1->0 of `valid` MUST follow a handshake (i.e., once the `valid` goes
  //     to `1` it cannot revert to 0 until there is a handshake)
  // Ready signals generally have to be propagated backwards through pipeline
  // stages combinationally unless we insert a FIFO buffer to isolate two computational
  // stages.
  // However, in this example we have a more complicated scenario as y depends on 
  // both x and h (without FIFOs in between), and the ready signal must be propagated
  // accordingly:
  //
  //   x ---\
  //         \
  //          |---> y
  //         /
  //   h ---/
  //
  // We can distinguish a few cases:
  //  - both x and h are valid: in this case, y's ready is directly back-propagated to x_ready
  //    and h_ready 
  //  - both x and h are invalid: in this case, the value of y_ready is not used to calculate
  //    x_ready and h_ready; we often assign y_ready to x_ready and h_ready to 1'b1
  //    signaling that the module is ready to accept new data (but 1'b0 would also work!)
  //  - x is valid and h is invalid: in this case, x_ready must be set to 1'b0 to avoid a
  //    out-of-sync handshake, which would make x "ahead of time" compared to h. h_ready
  //    is indifferent also in this case.
  //  - h is valid and x is invalid: in this case, h_ready must be set to 1'b0 to avoid a
  //    out-of-sync handshake, which would make h "ahead of time" compared to x. x_ready
  //    is indifferent also in this case.
  // Below, we choose to set indifferent signals to 1'b1 (as a default "I can accept data"
  // situation).
  // We use a "multiplexer" `assign` style for readability, although a simple network
  // of & and | would work as well.
  assign x_ready =  x_valid &  h_valid ? y_ready :
                   ~x_valid & ~h_valid ? 1'b1    :
                    x_valid & ~h_valid ? 1'b0    : 
                                         1'b1;
  assign h_ready =  x_valid &  h_valid ? y_ready :
                   ~x_valid & ~h_valid ? 1'b1    :
                    x_valid & ~h_valid ? 1'b1    : 
                                         1'b0;
  // Notice that inserting a FIFO between x and y would change this logic. For example,
  //
  //   x ---||||--- x_fifo ---\
  //                           \
  //                            |---> y
  //                           /
  //   h ---------------------/
  // 
  // would require to move the logic to the FIFO ready signals:
  //
  //   assign x_fifo.ready =  x_fifo.valid &  h_valid ? y_ready :
  //                         ~x_fifo.valid & ~h_valid ? 1'b1    :
  //                          x_fifo.valid & ~h_valid ? 1'b0    : 
  //                                                    1'b1;
  //   assign h_ready =  x_valid &  h_valid ? y_ready :
  //                    ~x_valid & ~h_valid ? 1'b1    :
  //                     x_valid & ~h_valid ? 1'b1    : 
  //                                          1'b0;
  //
  // The x_ready signal would then be directly generated by the FIFO (as `~full`).

`ifndef SYNTHESIS
`ifndef VERILATOR
  // use assertions to check that the streams have the correct width
  assert property (@(posedge clk_i) disable iff(~rst_ni)
    (h.DATA_WIDTH) == (DATA_WIDTH*NB_TAPS));
  assert property (@(posedge clk_i) disable iff(~rst_ni)
    (x.DATA_WIDTH) == (DATA_WIDTH));
  assert property (@(posedge clk_i) disable iff(~rst_ni)
    (y.DATA_WIDTH) == (DATA_WIDTH));
`endif
`endif

endmodule // fir_datapath
