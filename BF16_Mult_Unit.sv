`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/06/2026 05:27:59 PM
// Design Name: 
// Module Name: BF16_Mult_Unit
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


module BF16_Mult_Unit(
    input logic[15:0] A,
    input logic[15:0] B,
    output logic[15:0] C 
    );
    
    logic c_sign;
    logic[7:0] c_exp;
    logic[15:0] c_mant;
    logic[6:0] c_mant_tmp;
    
    always_comb
    begin
        c_sign     = A[15] ^ B[15];
        c_mant     = {1'b1, A[6:0]} * {1'b1, B[6:0]};
        c_mant_tmp = (c_mant[15] == 1'b0) ? c_mant[13:7] : c_mant[14:8];
        c_exp      = A[14:7] + B[14:7] - 8'd127 + ((8'b00000001) & {8{c_mant[15]}});

        if (A[14:0] == 15'b0 || B[14:0] == 15'b0) begin
            C = {c_sign, 15'b0};   // signed zero
        end
        else begin
            C = {c_sign, c_exp, c_mant_tmp};
        end
    end
    
endmodule
