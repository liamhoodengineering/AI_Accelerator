`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/12/2026 11:10:34 PM
// Design Name: 
// Module Name: FSM_tiling
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


module FSM_tiling(
    input logic reset,
    input logic cycle_done,
    input logic computation_done,
    input logic clk,
    output logic[7:0] addr_q, addr_k, addr_v
    
    );
    logic base_addr;
    
    
     
    always_ff @(posedge clk)
    begin
        base_addr <= (reset||computation_done) ? 8'b0 : (cycle_done ? base_addr+8'd1 : base_addr);
        
    end
    
    
    
endmodule
