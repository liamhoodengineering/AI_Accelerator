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
    input logic RW_en, //1: write, 0:read
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
    logic S_AXI_00_ARREADY;
    logic[33:0] S_AXI_00_AWADDR;
    logic[255:0] S_AXI_00_WDATA; 
    logic[255:0] S_AXI_00_RDATA; 
    logic S_AXI_00_WLAST;
    logic S_AXI_00_WREADY;
    logic S_AXI_00_WVALID;
    logic S_AXI_00_RREADY;
    logic S_AXI_00_RVALID;
    logic[31:0] S_AXI_00_WSTRB;
    logic[1:0] S_AXI_00_RRESP;
    logic S_AXI_00_RLAST;
    logic[5:0] S_AXI_00_RID;
    
    logic S_AXI_00_BREADY;
    logic S_AXI_00_BVALID;
    logic[1:0] S_AXI_00_BRESP;

    
    
    hbm_0 hbm_inst(
        // --- Global ---
        .AXI_00_ACLK        (S_AXI_CLK),
        .AXI_00_ARESET_N    (reset),

        // --- Read Address Channel (unused — tied off) ---
        .AXI_00_ARADDR      (34'b0),
        .AXI_00_ARLEN       (4'h0),
        .AXI_00_ARSIZE      (3'b101),
        .AXI_00_ARBURST     (2'b01),
        .AXI_00_ARID        (6'b0),
        .AXI_00_ARVALID     (1'b0),
        .AXI_00_ARREADY     (),

        // --- Write Address Channel ---
        .AXI_00_AWADDR      (S_AXI_00_AWADDR),
        .AXI_00_AWLEN       (4'h0),
        .AXI_00_AWSIZE      (3'b101),
        .AXI_00_AWBURST     (2'b01),
        .AXI_00_AWID        (6'b0),
        .AXI_00_AWVALID     (S_AXI_00_AWVALID),
        .AXI_00_AWREADY     (S_AXI_00_AWREADY),

        // --- Write Data Channel ---
        .AXI_00_WDATA       (S_AXI_00_WDATA),
        .AXI_00_WSTRB       (S_AXI_00_WSTRB),
        .AXI_00_WLAST       (S_AXI_00_WLAST),
        .AXI_00_WVALID      (S_AXI_00_WVALID),
        .AXI_00_WREADY      (S_AXI_00_WREADY),
        .AXI_00_WDATA_PARITY(32'h0),
        
        // --- Write Response Channel ---
        .AXI_00_BRESP       (S_AXI_00_BRESP),
        .AXI_00_BVALID      (S_AXI_00_BVALID),
        .AXI_00_BREADY      (S_AXI_00_BREADY),
        .AXI_00_BID         (),
        
         // --- Read Address Channel ---
        .AXI_00_ARADDR      (S_AXI_00_ARADDR),
        .AXI_00_ARLEN       (4'h0),
        .AXI_00_ARSIZE      (3'b101),
        .AXI_00_ARBURST     (2'b01),
        .AXI_00_ARID        (6'b0),
        .AXI_00_ARVALID     (S_AXI_00_ARVALID),
        .AXI_00_ARREADY     (S_AXI_00_ARREADY),

        // --- Read Data Channel ---
        .AXI_00_RDATA       (S_AXI_00_RDATA),
        .AXI_00_RLAST       (S_AXI_00_RLAST),
        .AXI_00_RRESP       (S_AXI_00_RRESP),
        .AXI_00_RVALID      (S_AXI_00_RVALID),
        .AXI_00_RREADY      (S_AXI_00_RREADY),
        .AXI_00_RID         ()
       

        
    );
    
    parameter[2:0] IDLE = 3'b000, WRITE_ADDRESS= 3'b001, READ_ADDRESS= 3'b010, READ_DATA = 3'b011, WRITE_DATA= 3'b10, WRITE_RESP= 3'b101;
    logic [2:0] state;
    //states:IDLE, receive write address, write data, response
    //write transaction
    always_ff @(posedge S_AXI_CLK)//state transition logic
    begin
        if(reset)
            state <= IDLE;
        else if(state == IDLE)
        begin
            if( RW_en)
                state <= WRITE_ADDRESS;
            else
                state <= READ_ADDRESS;
        end
        else if(state == WRITE_ADDRESS)
        begin
            if(S_AXI_00_AWREADY && S_AXI_00_AWVALID)
                state <= WRITE_DATA;
        end
        else if(state == READ_ADDRESS)
        begin
            if(S_AXI_00_ARREADY && S_AXI_00_ARVALID)
                state <= READ_DATA;
        end
        else if(state == WRITE_DATA)
        begin
            if(S_AXI_00_WREADY && S_AXI_00_WVALID && S_AXI_00_WLAST)
                state <= WRITE_RESP;
        end
        else if(state == READ_DATA)
        begin
            if(S_AXI_00_RREADY && S_AXI_00_RVALID)
                state <= IDLE;
        end
        else if(state == WRITE_RESP)
        begin
            if(S_AXI_00_BREADY && S_AXI_00_BVALID && (S_AXI_00_BRESP == 2'b00))
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
            READ_ADDRESS:
            begin
                S_AXI_00_AWVALID = 1'b1;
                S_AXI_00_AWADDR = read_address;   
            end
            WRITE_DATA:
            begin
                S_AXI_00_WLAST = 1'b1;
                S_AXI_00_WSTRB = 32'hFFFFFFFF;
                S_AXI_00_WVALID = 1'b1;
                S_AXI_00_WDATA = write_data;
                S_AXI_00_BREADY = 1'b1;
            end
            READ_DATA:
            begin
                S_AXI_00_RLAST = 1'b1;
                S_AXI_00_RVALID = 1'b1;
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
                S_AXI_00_BREADY = 1'b0;
            end
        endcase
    end
    
    
endmodule
