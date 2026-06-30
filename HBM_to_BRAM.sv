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
        
    input  logic [33:0]  read_address,
    input  logic [33:0]  write_address,
    input  logic [255:0] write_data,
    input  logic         RW_en, //1: write, 0:read
    input  logic         start, // 1-cycle pulse to launch one transaction
    input  logic         clk,
    input  logic         reset,
    input  logic         HBM_REF_CLK_0,  // 100 MHz HBM PLL reference
    input  logic         APB_0_PCLK,     // 100 MHz APB clock
    output logic [255:0] read_data_out,
    output logic [1:0]   read_resp_out,
    output logic         apb_complete_0  // HBM calibration done

);
    
    logic S_AXI_00_ARVALID;
    logic[33:0] S_AXI_00_ARADDR;
    
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
        .AXI_00_ARESET_N    (~reset),
        .HBM_REF_CLK_0      (HBM_REF_CLK_0),

        // --- APB Channel (idle — sim model auto-calibrates) ---
        .APB_0_PCLK         (APB_0_PCLK),
        .APB_0_PRESET_N     (~reset),
        .APB_0_PSEL         (1'b0),
        .APB_0_PENABLE      (1'b0),
        .APB_0_PWRITE       (1'b0),
        .APB_0_PADDR        (22'h0),
        .APB_0_PWDATA       (32'h0),
        .APB_0_PRDATA       (),
        .APB_0_PREADY       (),
        .APB_0_PSLVERR      (),
        .apb_complete_0     (apb_complete_0),

        // --- HBM stack status ---
        .DRAM_0_STAT_CATTRIP(),
        .DRAM_0_STAT_TEMP   (),

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
        .AXI_00_RDATA_PARITY(),

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
    
    parameter [2:0]
        IDLE                 = 3'b000,
        START_IO_TRANSACTION = 3'b001,
        WRITE_ADDRESS        = 3'b010,
        WRITE_DATA           = 3'b011,
        WRITE_RESP           = 3'b100,
        READ_ADDRESS         = 3'b101,
        READ_DATA            = 3'b110;

    logic [2:0] state;

    // Next-state logic
    always_ff @(posedge S_AXI_CLK) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE:                  if (start)
                                           state <= START_IO_TRANSACTION;
                START_IO_TRANSACTION:  state <= RW_en ? WRITE_ADDRESS : READ_ADDRESS;
                WRITE_ADDRESS:         if (S_AXI_00_AWVALID && S_AXI_00_AWREADY)
                                           state <= WRITE_DATA;
                WRITE_DATA:            if (S_AXI_00_WVALID && S_AXI_00_WREADY && S_AXI_00_WLAST)
                                           state <= WRITE_RESP;
                WRITE_RESP:            if (S_AXI_00_BVALID && S_AXI_00_BREADY && (S_AXI_00_BRESP == 2'b00))
                                           state <= IDLE;
                READ_ADDRESS:          if (S_AXI_00_ARVALID && S_AXI_00_ARREADY)
                                           state <= READ_DATA;
                READ_DATA:             if (S_AXI_00_RVALID && S_AXI_00_RREADY && S_AXI_00_RLAST)
                                           state <= IDLE;
                default:               state <= IDLE;
            endcase
        end
    end

    // Output logic — safe defaults then per-state overrides
    always_comb begin
        S_AXI_00_AWVALID = 1'b0;
        S_AXI_00_AWADDR  = 34'h0;
        S_AXI_00_WVALID  = 1'b0;
        S_AXI_00_WDATA   = 256'h0;
        S_AXI_00_WSTRB   = 32'h0;
        S_AXI_00_WLAST   = 1'b0;
        S_AXI_00_BREADY  = 1'b0;
        S_AXI_00_ARVALID = 1'b0;
        S_AXI_00_ARADDR  = 34'h0;
        S_AXI_00_RREADY  = 1'b0;

        case (state)
            WRITE_ADDRESS: begin
                S_AXI_00_AWVALID = 1'b1;
                S_AXI_00_AWADDR  = write_address;
                S_AXI_00_WVALID  = 1'b1;
                S_AXI_00_WDATA   = write_data;
                S_AXI_00_WSTRB   = 32'hFFFFFFFF;
                S_AXI_00_WLAST   = 1'b1;
            end
            WRITE_DATA: begin
                S_AXI_00_WVALID  = 1'b1;
                S_AXI_00_WDATA   = write_data;
                S_AXI_00_WSTRB   = 32'hFFFFFFFF;
                S_AXI_00_WLAST   = 1'b1;
                S_AXI_00_BREADY  = 1'b1;   // pre-assert
            end
            WRITE_RESP: begin
                S_AXI_00_BREADY  = 1'b1;
            end
            READ_ADDRESS: begin
                S_AXI_00_ARVALID = 1'b1;
                S_AXI_00_ARADDR  = read_address;
                S_AXI_00_RREADY  = 1'b1;   // pre-assert
            end
            READ_DATA: begin
                S_AXI_00_RREADY  = 1'b1;
            end
            default: ;
        endcase
    end

    // Latch read data on R-channel handshake
    always_ff @(posedge S_AXI_CLK) begin
        if (reset) begin
            read_data_out <= 256'h0;
            read_resp_out <= 2'h0;
        end else if (S_AXI_00_RVALID && S_AXI_00_RREADY) begin
            read_data_out <= S_AXI_00_RDATA;
            read_resp_out <= S_AXI_00_RRESP;
        end
    end



    
endmodule



module BRAM_parsing(
    input logic[255:0] data_i,
    output logic[31:0] data_o[8]);
    
   generate
    genvar i;
        for(i = 0; i < 8; i++)
        begin
            assign data_o[i] = data_i[(15+(i*16)):(i*16)];
        end
    endgenerate
    
endmodule
