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
    //input logic[15:0] matrix_a[16][16],
    output logic[7:0] block_addr_q, block_addr_k, block_addr_v
    
    );
    logic base_addr;
    
    
//     sub_matrix_A = matrix_A[i:i+4, k:k+4]
//                sub_matrix_B = matrix_B[k:k+4, j:j+4]

//                result[i:i+4, j:j+4] += np.matmul(sub_matrix_A, sub_matrix_B)
    always_ff @(posedge clk)
    begin
        base_addr <= (reset||computation_done) ? 8'b0 : (cycle_done ? base_addr+8'd1 : base_addr);
        
    end
    
    
    
endmodule
