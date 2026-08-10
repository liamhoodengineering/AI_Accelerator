`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/18/2026 08:09:06 AM
// Design Name: 
// Module Name: Read_Blk_Addr_TB
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


module Read_Blk_Addr_TB;
logic clk = 1'b0;
logic pclk = 1'b0;
logic ref_clk = 1'b0;
logic reset = 1'b0;
logic start = 1'b0;

always #2.5 clk = ~clk;//200MHz
always #5 ref_clk = ~ref_clk;//100MHz
always #5 pclk = ~pclk;//100MHz


logic[16:0] read_block_address_test;//from 
logic[16:0] write_block_address_test;

logic[33:0] read_addr_test[16];
logic[33:0] write_addr_test[16];
logic apb_complete_0;

task automatic pulse_start();
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;
    @(posedge clk);
endtask

task automatic check_read_addr(
    input logic[33:0] read_addr_test[16],
    input logic[33:0] write_addr_test[16],
    input logic[16:0] read_block_address_test, 
    input logic[16:0] write_block_address_test
);
foreach(read_addr_test[i])
    if(read_addr_test[i] == ({17'b0,read_block_address_test}+(34'd4096*i)))
        $display("read row: [%0d] PASS", i);
    else 
        $display("read row: [%0d] FAIL", i);
foreach(write_addr_test[i])
    if(write_addr_test[i] == ({17'b0,write_block_address_test}+(34'd4096*i)))
        $display("write row: [%0d] PASS", i);
    else 
        $display("write row: [%0d] FAIL", i);  
endtask

logic RW_EN[16];
always_comb begin
for(int i = 0; i < 16; i++)
    RW_EN[i] = 1'b0;
end
HBM_to_BRAM dut(
//     put 
        
//    input  logic [33:0]  read_address,
//    input  logic [33:0]  write_address,
    .read_block_address(read_block_address_test),//rows: 4096   col: 8192
    .write_block_address(write_block_address_test),//rows: 4096   col: 8192
    .write_data(),
    .RW_en(RW_EN), //1: write, 0:read
    .start(start), // 1-cycle pulse to launch one transaction
    .clk(clk),
    .reset(reset),
    .HBM_REF_CLK_0(ref_clk),  // 100 MHz HBM PLL reference
    .APB_0_PCLK(pclk),     // 100 MHz APB clock
    .read_data_out(),
    .read_resp_out(),
    .apb_complete_0(apb_complete_0),  // HBM calibration done
    
    .AWADDR_TEST(read_addr_test),
    .ARADDR_TEST(write_addr_test)//34, 16

);

initial begin
    reset = 1'b1;
    #20
    reset = 1'b0;
    wait(apb_complete_0 == 1'b1);
    read_block_address_test = 17'd5;
    pulse_start();
    #1000;
    $finish;

end

initial begin//watchdog
    #50_000
    $finish;
end


endmodule
