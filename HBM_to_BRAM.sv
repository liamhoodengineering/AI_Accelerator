`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/15/2026 10:30:35 PM
// Design Name: 
// Module Name: HBM_to_BRAM
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


module HBM_to_BRAM(
//     put 
        
    input logic[33:0] read_address,
    input logic[33:0] write_address,
    input logic[255:0] write_data,
    input logic write_start,
    input logic clk,
    input logic reset

);
    
    logic S_AXI_00_AREADY;
    logic S_AXI_00_ARVALID;
    logic[33:0] S_AXI_READ_ADDR_00;
    
    logic S_AXI_CLK;
    assign S_AXI_CLK = clk;
    
    
    logic S_AXI_00_AWREADY;
    logic S_AXI_00_AWVALID;
    logic[33:0] S_AXI_00_AWADDR;
    logic[255:0] S_AXI_00_WDATA; 
    logic S_AXI_00_WLAST;
    logic S_AXI_00_WREADY;
    logic S_AXI_00_WVALID;
    logic[31:0] S_AXI_00_WSTRB;
    
    logic S_AXI_00_BREADY;
    logic S_AXI_00_BVALID;
    logic[1:0] S_AXI_00_BRESP;
    
    
    hbm_0 hbm_inst(
        .AXI_00_ARADDR(S_AXI_00_READ_ADDR),
        .AXI_00_ARVALID(),
        .AXI_00_ARREADY(),
        
        
        .AXI_00_ARBURST(),
        .AXI_00_ARID(),
        .AXI_00_ARLEN(),
        
        
        .AXI_00_ARSIZE(),
        .AXI_00_ACLK(S_AXI_CLK),
        .AXI_00_ARESET_N(reset),
        
        //write signals
        .AXI_00_WDATA_PARITY(),//32 bits    
        .AXI_00_AWADDR(),
        .AXI_00_AWBURST(),
        .AXI_00_AWID(), 
        .AXI_00_AWLEN(),
        .AXI_00_AWVALID(),
        .AXI_00_AWREADY(),
        .AXI_00_WDATA(),
        .AXI_00_WLAST(),
        .AXI_00_WREADY(),
        .AXI_00_WSTRB(),
        .AXI_00_WVALID(),
        
        //response signals
        .AXI_00_BID(),
        .AXI_00_BREADY(),
        .AXI_00_BRESP(),
        .AXI_00_BVALID()
        
        
    );
    
    parameter[1:0] IDLE = 2'b00, WRITE_ADDRESS= 2'b01, WRITE_DATA= 2'b10, WRITE_RESP= 2'b11;
    logic state;
    //states:IDLE, receive write address, write data, response
    //write transaction
    always_ff @(posedge S_AXI_CLK)//state transition logic
    begin
        if(reset)
            state <= IDLE;
        else if(state == IDLE)
            if( write_start)
                state <= WRITE_ADDRESS;
        else if(state == WRITE_ADDRESS)
        begin
            if(S_AXI_00_AWREADY && S_AXI_00_AWVALID)
                state <= WRITE_DATA;
        end
        else if(state == WRITE_DATA)
        begin
            if(S_AXI_00_WREADY && S_AXI_00_WVALID && S_AXI_00_WLAST)
                state <= WRITE_RESP;
        end
        else if(state == WRITE_RESP)
        begin
            if(S_AXI_00_BREADY && S_AXI_00_BVALID && (S_AXI_00_BRESP == 3'b0))
                state <= IDLE;
        end
    end
    
    always_comb
    begin
        case(state)
//            IDLE:
//            begin
//                S_AXI_00_AWVALID = 1'b0;
//                S_AXI_00_WVALID = 1'b0;
//                S_AXI_00_WLAST = 1'b0;
//                S_AXI_00_WSTRB = 32'h00000000;
//            end
            WRITE_ADDRESS:
            begin
                S_AXI_00_AWVALID = 1'b1;
                S_AXI_00_AWADDR = write_address;
                
            end
            WRITE_DATA:
            begin
                S_AXI_00_WLAST = 1'b1;
                S_AXI_00_WSTRB = 32'hFFFFFFFF;
                S_AXI_00_WVALID = 1'b1;
                S_AXI_00_WDATA = write_data;
                S_AXI_00_BREADY = 1'b1;
            end
            WRITE_RESP:
            begin
                S_AXI_00_BREADY = 1'b1;
            end
            default:
            begin
                S_AXI_00_AWVALID = 1'b0;
                S_AXI_00_WVALID = 1'b0;
                S_AXI_00_WLAST = 1'b0;
               // S_AXI_00_WSTRB = 32'h00000000;
                S_AXI_00_BREADY = 1'b0;
                
            end
        endcase
    end
    
    
endmodule
