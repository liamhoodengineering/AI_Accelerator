`timescale 1ns / 1ps

//module BRAM_to_LUTRAM(
//    input  logic         clk,
//    input  logic         reset,
//    input  logic [3:0]   wea_q,
//    input  logic [3:0]   web_q,
//    input  logic [5:0]   row,
//    input  logic [255:0] input_data,
//    output logic [31:0]  dout_1 [4],   // port A from each bank
//    output logic [31:0]  dout_2 [4]    // port B from each bank
//);

    

    

//endmodule


//module LUTRAM(
//    input logic [31:0]  din_1 [4],   // port A from each bank
//    input logic [31:0]  din_2 [4]
//);
    
    
//endmodule


module BRAM_TO_LUTRAM #
(parameter int ROW = 16)
(
    input logic clk,
    input logic[31:0] Q_bank_dout_1[ROW][4],
    input logic[31:0] Q_bank_dout_2[ROW][4],
    output logic[15:0] Q_LUTRAM[ROW][16]
);
 always_ff @(posedge clk)
 begin
    for(int i = 0; i < ROW; i++)
    begin
        for(int bank = 0; bank < 4; bank++)
        begin
            {Q_LUTRAM[i][bank*4+1], Q_LUTRAM[i][bank*4]} <= Q_bank_dout_1[i][bank];
            {Q_LUTRAM[i][bank*4+3], Q_LUTRAM[i][bank*4+2]} <= Q_bank_dout_2[i][bank];
            
        end
        
    end
end
endmodule
