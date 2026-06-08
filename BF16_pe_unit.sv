`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: BF16_pe_unit
// Description: One BF16 MAC processing element for an output-stationary
//              systolic array. Each cycle the accumulator does:
//                  accumulate <= accumulate + A * B
//              with all arithmetic in BF16. S exposes the registered
//              accumulator value.
//////////////////////////////////////////////////////////////////////////////////


module BF16_pe_unit(
        input  logic        clk,
        input  logic        reset,
        input  logic [15:0] A,
        input  logic [15:0] B,
        output logic [15:0] S
    );

    logic [15:0] product;
    logic [15:0] sum;
    logic [15:0] accumulate;

    // S is the registered accumulator value (single driver = this assign).
    assign S = accumulate;

    always_ff @(posedge clk) begin
        accumulate <= reset ? 16'b0 : sum;
    end

    // sum is the next-state value of accumulate: A*B + accumulate.
    BF16_Mult_Unit BF16_Mult_Unit_inst (.A(A),       .B(B),          .C(product));
    BF16_Add_Unit  BF16_Add_Unit_inst  (.A(product), .B(accumulate), .C(sum));

endmodule
