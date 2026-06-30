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

    //input logic[5:0] addr_1,
    input logic reset,
    input logic[3:0] wea_q,
    input logic[3:0] web_q,
   // input logic[31:0] din_1,
    output logic[31:0] dout_1[4],
   // input logic[5:0] addr_2,
    output logic[31:0] dout_2[4],
    //input logic[31:0] din_2,
    input logic clk,
    input logic[255:0] input_data
    
    

    );
    
    
 genvar bank;
    generate
        for (bank = 0; bank < 4; bank++) begin : q_banks
            Q_bank Q_bank_inst_1 (
                .clka (clk),  
                .addra(bank[5:0]<<1), 
               // .dina(din_1),
                .dina(input_data[(bank*16+15):(bank*16)]),
                .douta(dout_1[bank]), 
                .rsta(reset), 
                .wea(wea_q),
                .clkb (clk),  
                .addrb(bank[5:0]<<1+6'd1), 
                .dinb(input_data[(bank*16+31):(bank*16+16)]),
                .doutb(dout_2[bank]), 
                .rstb(reset), 
                .web(web_q)
            );
         end
    endgenerate    
endmodule
