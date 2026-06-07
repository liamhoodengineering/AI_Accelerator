`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/07/2026 05:31:28 PM
// Design Name: 
// Module Name: BF16_pe_unit
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


module BF16_pe_unit(
        input logic[15:0] A,
        input logic[15:0] B,
        input logic reset,
        input logic clk,
       // input logic[15:0] accumulate
        output logic[15:0] S
    );
    
    logic[15:0] sum;
    logic[15:0] product;
    logic[15:0] accumulate;
    
    assign S = accumulate;
    
    always_ff @(posedge clk)
    begin
        
        accumulate <= reset ? 16'b0 : sum;
    end
    
    BF16_Mult_Unit(.A(A), .B(B), .C(product));
    BF16_Add_Unit(.A(product), .B(accumulate), .C(S));
endmodule
