`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/28/2026 09:39:35 PM
// Design Name: 
// Module Name: BRAM_TO_LUT_TB
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


module BRAM_TO_LUT_TB();

logic clk;
logic reset;
logic[5:0] addr_1;
logic[5:0] addr_2;
logic[31:0] din_2;
logic[31:0] din_1;
logic[31:0] dout_1;
logic[31:0] dout_2;
logic[3:0] wea;
logic[3:0] web;

BRAM_to_LUTRAM br_to_lut_inst(
    .addr_1(addr_1),
    .reset(reset),
    .wea_q(wea),
    .web_q(web),
    .din_1(din_1),
    .dout_1(dout_1),
    .addr_2(addr_2),
    .dout_2(dout_2),
    .din_2(din_2),
    .clk(clk)
);


initial begin
    clk =  1'b0;
    reset = 1'b0;
    web = 4'd15;
    wea = 4'd15;
    #1
    reset = 1'b1;
    #4
    reset = 1'b0;
    addr_1 = 6'd0;
    addr_2 = 5'd1;
    
    #5
    
    din_1 = 32'd1;
    din_2 = 32'd1;
    
    #5
    
    

end

always #5 clk = ~clk;

endmodule
