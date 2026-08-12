`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 08/10/2026 11:14:48 PM
// Design Name:
// Module Name: square_root
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module square_root#(parameter logic[25:0] dimension = 26'd128)(
    input logic clk,
    output logic[15:0] dim_sqrt,   // BF16 (1 sign + 8 exp + 7 mantissa)
    output logic done
    );

    logic sqrt_root_done;
    logic[13:0] sqrt_op_output;    // Q8.6: [13:6]=int, [5:0]=frac  => value = sqrt(dimension)
    square_root_operation CORDIC_INST(
        .aclk(clk),
        .s_axis_cartesian_tdata((dimension<<12)),
        .s_axis_cartesian_tvalid(1'b1),
        .m_axis_dout_tdata(sqrt_op_output),
        .m_axis_dout_tvalid(sqrt_root_done)

    );

   CONVERT_to_BF16 BF16_inst
   (
        .start(sqrt_root_done),
        .input_data(sqrt_op_output),
        .output_data(dim_sqrt),
        .clk(clk),
        .done(done)
   );


endmodule

// Converts a Q8.6 unsigned fixed-point value (input_data / 64) into BF16.
// One-shot: loads on the rising edge of `start` (CORDIC tvalid stays high, so a
// level-sensitive load would reload every cycle and never normalize). Normalizes by
// shifting the leading 1 up to bit 15; exp base 136 makes the BF16 exponent field
// resolve to (k + 121) for a leading-one at Q8.6 bit k.
module CONVERT_to_BF16
(
    input logic start,
    input logic[13:0] input_data,
    output logic[15:0] output_data,
    input logic clk,

    output logic done
);
    logic[7:0]  exp;
    logic[15:0] mantissa;
    logic       busy;
    logic       start_d;

    always_ff @(posedge clk) begin
        start_d <= start;
        if (start & ~start_d) begin          // one-shot load
            if (input_data == 14'd0) begin    // zero guard -> BF16 +0.0
                mantissa <= 16'd0;
                exp      <= 8'd0;
                done     <= 1'b1;
                busy     <= 1'b0;
            end else begin
                mantissa <= {2'b0, input_data};
                exp      <= 8'd136;
                done     <= 1'b0;
                busy     <= 1'b1;
            end
        end else if (busy) begin
            if (mantissa[15]) begin           // leading 1 reached the top: done
                done <= 1'b1;
                busy <= 1'b0;
            end else begin
                mantissa <= {mantissa[14:0], 1'b0};
                exp      <= exp - 8'd1;
            end
        end
    end

    assign output_data = done ? {1'b0, exp, mantissa[14:8]} : 16'd0;

endmodule
