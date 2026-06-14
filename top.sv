`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/12/2026 10:59:47 PM
// Design Name: 
// Module Name: top
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

//ports (A): addra, clka, dina, wea
module top(
    input logic clk,
    input logic Reset

    );
    
    logic[5:0] addr_q_1[1:0], addr_q_2[1:0];
    //addr_k, addr_v;
    logic[31:0] dout_q_1[1:0], dout_q_2[1:0];
    logic[31:0] dout_k_1[1:0], dout_k_2[1:0];
    //dout_k, dout_v;
   
    
    logic[15:0] q_tile_lut[15:0][15:0], k_tile_lut[15:0][15:0];
    //, k_tile_lut, v_tile_lut;
    
    //8 bits address: offset (4 bits) + bank (4 bits)
    
    logic[3:0] web_q, wea_q;
    
    
    always_ff @(posedge clk)
    begin
        for(int i = 0; i < 16; i++)
        begin
            for(int j = 0; j < 4; j= j+4)
            begin
                {q_tile_lut[i][j], q_tile_lut[i][j+1]} <= dout_q_1[i];
                {q_tile_lut[i][j+2], q_tile_lut[i][j+3]} <= dout_q_2[i];
                {k_tile_lut[j][i], k_tile_lut[j+1][i]} <= dout_k_1[i];
                {k_tile_lut[j+2][i], k_tile_lut[j+3][i]} <= dout_k_2[i];
            end
            
        end
        
       
    end
    
    
    
    genvar i;
    
    generate
        for(i = 0; i < 4; i++)
        begin
            Q_bank Q_bank_1_inst(
                .clka(clk),
                .addra(addr_q_1[i]),//addr
                .dina(),//write
                .douta(dout_q_1[i]),//read
                .rsta(Reset),//reset
                .wea(wea_q),
                .clkb(clk),
                .addrb(addr_q_2[i]),//addr
                .dinb(),//write
                .doutb(dout_q_2[i]),//read
                .rstb(Reset),//reset
                .web(web_q)  
            );
            
            K_bank K_bank_1_inst(
                .clka(clk),
                .addra(addr_k_1[i]),//addr
                .dina(),//write
                .douta(dout_k_1[i]),//read
                .rsta(Reset),//reset
                .wea(wea_k),
                .clkb(clk),
                .addrb(addr_k_2[i]),//addr
                .dinb(),//write
                .doutb(dout_k_2[i]),//read
                .rstb(Reset),//reset
                .web(web_k)  
            );
        end
        
    endgenerate
    
//    k_tile k_tile_inst(
//        .clkb(clk),
//        .addrb(addr_k),
//        .doutb(dout_k)
//    );
    
//    V_tile v_tile_inst(
//        .clkb(clk),
//        .addrb(addr_v),
//        .doutb(dout_v)
//    );
endmodule
