`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/28/2026 06:48:11 PM
// Design Name: 
// Module Name: BRAM_to_LUTRAM
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


module BRAM_to_LUTRAM(

    input logic[5:0] addr_1,
    input logic reset,
    input logic[3:0] wea_q,
    input logic[3:0] web_q,
    input logic[31:0] din_1,
    output logic[31:0] dout_1,
    input logic[5:0] addr_2,
    output logic[31:0] dout_2,
    input logic[31:0] din_2,
    input logic clk
    
    

    );
    
    
// genvar bank;
//    generate
//        for (bank = 0; bank < 4; bank++) begin : q_banks
            Q_bank Q_bank_inst_1 (
                .clka (clk),  
                .addra(addr_1), 
                .dina(din_1),
                .douta(dout_1), 
                .rsta(reset), 
                .wea(wea_q),
                .clkb (clk),  
                .addrb(addr_2), 
                .dinb(din_2),
                .doutb(dout_2), 
                .rstb(reset), 
                .web(web_q)
            );
//         end
//        //end
//    endgenerate    
endmodule
