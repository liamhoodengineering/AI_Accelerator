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


module HBM_to_BRAM #(
    // Sim-only params (used only under `SIM_FAST_HBM; ignored for the real IP,
    // so synthesis is unaffected). MEM_FILE is a $readmemh image of this
    // matrix's HBM contents; NUM_TC is the number of column-tiles (= COLS) used
    // to flatten the (tr,tc,row) address into a linear index.
    parameter string MEM_FILE      = "",
    parameter int    NUM_TC        = 256,
    parameter int    SIM_MEM_DEPTH = 4096
)(
//     put

//    input  logic [33:0]  read_address,
//    input  logic [33:0]  write_address,
    input logic[16:0] read_block_address,//rows: 4096   col: 8192
    input logic[16:0] write_block_address,//rows: 4096   col: 8192
    input  logic [255:0] write_data[16],
    input  logic         RW_en[16], //1: write, 0:read
    input  logic         start, // 1-cycle pulse to launch one transaction
    input  logic         clk,
    input  logic         reset,
    input  logic         HBM_REF_CLK_0,  // 100 MHz HBM PLL reference
    input  logic         APB_0_PCLK,     // 100 MHz APB clock
    output logic [255:0] read_data_out[16],
    output logic [1:0]   read_resp_out[16],
    output logic         apb_complete_0,  // HBM calibration done
    output logic[33:0] AWADDR_TEST[16],
    output logic[33:0] ARADDR_TEST[16],
    output logic done


);

   logic [29:0]  read_address,write_address;
   
//   assign read_address = ;
   // logic [255:0] read_data_out;
    
    // ---- AXI pseudo-channel signals: index [0]..[15] ----
    logic         S_AXI_AWREADY [16];
    logic         S_AXI_AWVALID [16];
    logic [33:0]  S_AXI_AWADDR  [16];
    logic [255:0] S_AXI_WDATA   [16];
    logic [31:0]  S_AXI_WSTRB   [16];
    logic         S_AXI_WLAST   [16];
    logic         S_AXI_WREADY  [16];
    logic         S_AXI_WVALID  [16];
    logic         S_AXI_BREADY  [16];
    logic         S_AXI_BVALID  [16];
    logic [1:0]   S_AXI_BRESP   [16];
    logic         S_AXI_ARVALID [16];
    logic         S_AXI_ARREADY [16];
    logic [33:0]  S_AXI_ARADDR  [16];
    logic [255:0] S_AXI_RDATA   [16];
    logic         S_AXI_RREADY  [16];
    logic         S_AXI_RVALID  [16];
    logic [1:0]   S_AXI_RRESP   [16];
    logic         S_AXI_RLAST   [16];
    logic [5:0]   S_AXI_RID     [16];
    
    logic S_AXI_CLK;
    assign S_AXI_CLK = clk;
    always_comb begin 
        foreach(AWADDR_TEST[i])begin
            AWADDR_TEST[i] = S_AXI_AWADDR[i];
            ARADDR_TEST[i] = S_AXI_ARADDR[i];end

    end

    
    // Row-major HBM address generation (single always_comb, no other drivers).
    //   byte_addr(i) = (16*tr + i)*8192 + 32*tc
    //                = (tr<<17) + (i<<13) + (tc<<5)
    //   block T = {tr[8:0], tc[7:0]}  =>  tr = block[16:8], tc = block[7:0]
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            S_AXI_ARADDR[i] = (34'(read_block_address[16:8])  << 17)
                            + (34'(read_block_address[7:0])   << 5)
                            + (34'(i)                         << 13);
            S_AXI_AWADDR[i] = (34'(write_block_address[16:8]) << 17)
                            + (34'(write_block_address[7:0])  << 5)
                            + (34'(i)                         << 13);
        end
    end
    
    
    
`ifndef SIM_FAST_HBM
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
        .AXI_00_AWADDR      (S_AXI_AWADDR[0]),
        .AXI_00_AWLEN       (4'h0),
        .AXI_00_AWSIZE      (3'b101),
        .AXI_00_AWBURST     (2'b01),
        .AXI_00_AWID        (6'b0),
        .AXI_00_AWVALID     (S_AXI_AWVALID[0]),
        .AXI_00_AWREADY     (S_AXI_AWREADY[0]),

        // --- Write Data Channel ---
        .AXI_00_WDATA       (S_AXI_WDATA[0]),
        .AXI_00_WSTRB       (S_AXI_WSTRB[0]),
        .AXI_00_WLAST       (S_AXI_WLAST[0]),
        .AXI_00_WVALID      (S_AXI_WVALID[0]),
        .AXI_00_WREADY      (S_AXI_WREADY[0]),
        .AXI_00_WDATA_PARITY(32'h0),
        .AXI_00_RDATA_PARITY(),

        // --- Write Response Channel ---
        .AXI_00_BRESP       (S_AXI_BRESP[0]),
        .AXI_00_BVALID      (S_AXI_BVALID[0]),
        .AXI_00_BREADY      (S_AXI_BREADY[0]),
        .AXI_00_BID         (),
        
         // --- Read Address Channel ---
        .AXI_00_ARADDR      (S_AXI_ARADDR[0]),
        .AXI_00_ARLEN       (4'h0),
        .AXI_00_ARSIZE      (3'b101),
        .AXI_00_ARBURST     (2'b01),
        .AXI_00_ARID        (6'b0),
        .AXI_00_ARVALID     (S_AXI_ARVALID[0]),
        .AXI_00_ARREADY     (S_AXI_ARREADY[0]),

        // --- Read Data Channel ---
        .AXI_00_RDATA       (S_AXI_RDATA[0]),
        .AXI_00_RLAST       (S_AXI_RLAST[0]),
        .AXI_00_RRESP       (S_AXI_RRESP[0]),
        .AXI_00_RVALID      (S_AXI_RVALID[0]),
        .AXI_00_RREADY      (S_AXI_RREADY[0]),
        .AXI_00_RID         (),

        // --- Channel 01 ---
        .AXI_01_ACLK        (S_AXI_CLK),
        .AXI_01_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_01_AWADDR      (S_AXI_AWADDR[1]),
        .AXI_01_AWLEN       (4'h0),
        .AXI_01_AWSIZE      (3'b101),
        .AXI_01_AWBURST     (2'b01),
        .AXI_01_AWID        (6'b0),
        .AXI_01_AWVALID     (S_AXI_AWVALID[1]),
        .AXI_01_AWREADY     (S_AXI_AWREADY[1]),

        // Write Data Channel
        .AXI_01_WDATA       (S_AXI_WDATA[1]),
        .AXI_01_WSTRB       (S_AXI_WSTRB[1]),
        .AXI_01_WLAST       (S_AXI_WLAST[1]),
        .AXI_01_WVALID      (S_AXI_WVALID[1]),
        .AXI_01_WREADY      (S_AXI_WREADY[1]),
        .AXI_01_WDATA_PARITY(32'h0),
        .AXI_01_RDATA_PARITY(),

        // Write Response Channel
        .AXI_01_BRESP       (S_AXI_BRESP[1]),
        .AXI_01_BVALID      (S_AXI_BVALID[1]),
        .AXI_01_BREADY      (S_AXI_BREADY[1]),
        .AXI_01_BID         (),

        // Read Address Channel
        .AXI_01_ARADDR      (S_AXI_ARADDR[1]),
        .AXI_01_ARLEN       (4'h0),
        .AXI_01_ARSIZE      (3'b101),
        .AXI_01_ARBURST     (2'b01),
        .AXI_01_ARID        (6'b0),
        .AXI_01_ARVALID     (S_AXI_ARVALID[1]),
        .AXI_01_ARREADY     (S_AXI_ARREADY[1]),

        // Read Data Channel
        .AXI_01_RDATA       (S_AXI_RDATA[1]),
        .AXI_01_RLAST       (S_AXI_RLAST[1]),
        .AXI_01_RRESP       (S_AXI_RRESP[1]),
        .AXI_01_RVALID      (S_AXI_RVALID[1]),
        .AXI_01_RREADY      (S_AXI_RREADY[1]),
        .AXI_01_RID         ()
,

        // --- Channel 02 ---
        .AXI_02_ACLK        (S_AXI_CLK),
        .AXI_02_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_02_AWADDR      (S_AXI_AWADDR[2]),
        .AXI_02_AWLEN       (4'h0),
        .AXI_02_AWSIZE      (3'b101),
        .AXI_02_AWBURST     (2'b01),
        .AXI_02_AWID        (6'b0),
        .AXI_02_AWVALID     (S_AXI_AWVALID[2]),
        .AXI_02_AWREADY     (S_AXI_AWREADY[2]),

        // Write Data Channel
        .AXI_02_WDATA       (S_AXI_WDATA[2]),
        .AXI_02_WSTRB       (S_AXI_WSTRB[2]),
        .AXI_02_WLAST       (S_AXI_WLAST[2]),
        .AXI_02_WVALID      (S_AXI_WVALID[2]),
        .AXI_02_WREADY      (S_AXI_WREADY[2]),
        .AXI_02_WDATA_PARITY(32'h0),
        .AXI_02_RDATA_PARITY(),

        // Write Response Channel
        .AXI_02_BRESP       (S_AXI_BRESP[2]),
        .AXI_02_BVALID      (S_AXI_BVALID[2]),
        .AXI_02_BREADY      (S_AXI_BREADY[2]),
        .AXI_02_BID         (),

        // Read Address Channel
        .AXI_02_ARADDR      (S_AXI_ARADDR[2]),
        .AXI_02_ARLEN       (4'h0),
        .AXI_02_ARSIZE      (3'b101),
        .AXI_02_ARBURST     (2'b01),
        .AXI_02_ARID        (6'b0),
        .AXI_02_ARVALID     (S_AXI_ARVALID[2]),
        .AXI_02_ARREADY     (S_AXI_ARREADY[2]),

        // Read Data Channel
        .AXI_02_RDATA       (S_AXI_RDATA[2]),
        .AXI_02_RLAST       (S_AXI_RLAST[2]),
        .AXI_02_RRESP       (S_AXI_RRESP[2]),
        .AXI_02_RVALID      (S_AXI_RVALID[2]),
        .AXI_02_RREADY      (S_AXI_RREADY[2]),
        .AXI_02_RID         ()
,

        // --- Channel 03 ---
        .AXI_03_ACLK        (S_AXI_CLK),
        .AXI_03_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_03_AWADDR      (S_AXI_AWADDR[3]),
        .AXI_03_AWLEN       (4'h0),
        .AXI_03_AWSIZE      (3'b101),
        .AXI_03_AWBURST     (2'b01),
        .AXI_03_AWID        (6'b0),
        .AXI_03_AWVALID     (S_AXI_AWVALID[3]),
        .AXI_03_AWREADY     (S_AXI_AWREADY[3]),

        // Write Data Channel
        .AXI_03_WDATA       (S_AXI_WDATA[3]),
        .AXI_03_WSTRB       (S_AXI_WSTRB[3]),
        .AXI_03_WLAST       (S_AXI_WLAST[3]),
        .AXI_03_WVALID      (S_AXI_WVALID[3]),
        .AXI_03_WREADY      (S_AXI_WREADY[3]),
        .AXI_03_WDATA_PARITY(32'h0),
        .AXI_03_RDATA_PARITY(),

        // Write Response Channel
        .AXI_03_BRESP       (S_AXI_BRESP[3]),
        .AXI_03_BVALID      (S_AXI_BVALID[3]),
        .AXI_03_BREADY      (S_AXI_BREADY[3]),
        .AXI_03_BID         (),

        // Read Address Channel
        .AXI_03_ARADDR      (S_AXI_ARADDR[3]),
        .AXI_03_ARLEN       (4'h0),
        .AXI_03_ARSIZE      (3'b101),
        .AXI_03_ARBURST     (2'b01),
        .AXI_03_ARID        (6'b0),
        .AXI_03_ARVALID     (S_AXI_ARVALID[3]),
        .AXI_03_ARREADY     (S_AXI_ARREADY[3]),

        // Read Data Channel
        .AXI_03_RDATA       (S_AXI_RDATA[3]),
        .AXI_03_RLAST       (S_AXI_RLAST[3]),
        .AXI_03_RRESP       (S_AXI_RRESP[3]),
        .AXI_03_RVALID      (S_AXI_RVALID[3]),
        .AXI_03_RREADY      (S_AXI_RREADY[3]),
        .AXI_03_RID         ()
,

        // --- Channel 04 ---
        .AXI_04_ACLK        (S_AXI_CLK),
        .AXI_04_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_04_AWADDR      (S_AXI_AWADDR[4]),
        .AXI_04_AWLEN       (4'h0),
        .AXI_04_AWSIZE      (3'b101),
        .AXI_04_AWBURST     (2'b01),
        .AXI_04_AWID        (6'b0),
        .AXI_04_AWVALID     (S_AXI_AWVALID[4]),
        .AXI_04_AWREADY     (S_AXI_AWREADY[4]),

        // Write Data Channel
        .AXI_04_WDATA       (S_AXI_WDATA[4]),
        .AXI_04_WSTRB       (S_AXI_WSTRB[4]),
        .AXI_04_WLAST       (S_AXI_WLAST[4]),
        .AXI_04_WVALID      (S_AXI_WVALID[4]),
        .AXI_04_WREADY      (S_AXI_WREADY[4]),
        .AXI_04_WDATA_PARITY(32'h0),
        .AXI_04_RDATA_PARITY(),

        // Write Response Channel
        .AXI_04_BRESP       (S_AXI_BRESP[4]),
        .AXI_04_BVALID      (S_AXI_BVALID[4]),
        .AXI_04_BREADY      (S_AXI_BREADY[4]),
        .AXI_04_BID         (),

        // Read Address Channel
        .AXI_04_ARADDR      (S_AXI_ARADDR[4]),
        .AXI_04_ARLEN       (4'h0),
        .AXI_04_ARSIZE      (3'b101),
        .AXI_04_ARBURST     (2'b01),
        .AXI_04_ARID        (6'b0),
        .AXI_04_ARVALID     (S_AXI_ARVALID[4]),
        .AXI_04_ARREADY     (S_AXI_ARREADY[4]),

        // Read Data Channel
        .AXI_04_RDATA       (S_AXI_RDATA[4]),
        .AXI_04_RLAST       (S_AXI_RLAST[4]),
        .AXI_04_RRESP       (S_AXI_RRESP[4]),
        .AXI_04_RVALID      (S_AXI_RVALID[4]),
        .AXI_04_RREADY      (S_AXI_RREADY[4]),
        .AXI_04_RID         ()
,

        // --- Channel 05 ---
        .AXI_05_ACLK        (S_AXI_CLK),
        .AXI_05_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_05_AWADDR      (S_AXI_AWADDR[5]),
        .AXI_05_AWLEN       (4'h0),
        .AXI_05_AWSIZE      (3'b101),
        .AXI_05_AWBURST     (2'b01),
        .AXI_05_AWID        (6'b0),
        .AXI_05_AWVALID     (S_AXI_AWVALID[5]),
        .AXI_05_AWREADY     (S_AXI_AWREADY[5]),

        // Write Data Channel
        .AXI_05_WDATA       (S_AXI_WDATA[5]),
        .AXI_05_WSTRB       (S_AXI_WSTRB[5]),
        .AXI_05_WLAST       (S_AXI_WLAST[5]),
        .AXI_05_WVALID      (S_AXI_WVALID[5]),
        .AXI_05_WREADY      (S_AXI_WREADY[5]),
        .AXI_05_WDATA_PARITY(32'h0),
        .AXI_05_RDATA_PARITY(),

        // Write Response Channel
        .AXI_05_BRESP       (S_AXI_BRESP[5]),
        .AXI_05_BVALID      (S_AXI_BVALID[5]),
        .AXI_05_BREADY      (S_AXI_BREADY[5]),
        .AXI_05_BID         (),

        // Read Address Channel
        .AXI_05_ARADDR      (S_AXI_ARADDR[5]),
        .AXI_05_ARLEN       (4'h0),
        .AXI_05_ARSIZE      (3'b101),
        .AXI_05_ARBURST     (2'b01),
        .AXI_05_ARID        (6'b0),
        .AXI_05_ARVALID     (S_AXI_ARVALID[5]),
        .AXI_05_ARREADY     (S_AXI_ARREADY[5]),

        // Read Data Channel
        .AXI_05_RDATA       (S_AXI_RDATA[5]),
        .AXI_05_RLAST       (S_AXI_RLAST[5]),
        .AXI_05_RRESP       (S_AXI_RRESP[5]),
        .AXI_05_RVALID      (S_AXI_RVALID[5]),
        .AXI_05_RREADY      (S_AXI_RREADY[5]),
        .AXI_05_RID         ()
,

        // --- Channel 06 ---
        .AXI_06_ACLK        (S_AXI_CLK),
        .AXI_06_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_06_AWADDR      (S_AXI_AWADDR[6]),
        .AXI_06_AWLEN       (4'h0),
        .AXI_06_AWSIZE      (3'b101),
        .AXI_06_AWBURST     (2'b01),
        .AXI_06_AWID        (6'b0),
        .AXI_06_AWVALID     (S_AXI_AWVALID[6]),
        .AXI_06_AWREADY     (S_AXI_AWREADY[6]),

        // Write Data Channel
        .AXI_06_WDATA       (S_AXI_WDATA[6]),
        .AXI_06_WSTRB       (S_AXI_WSTRB[6]),
        .AXI_06_WLAST       (S_AXI_WLAST[6]),
        .AXI_06_WVALID      (S_AXI_WVALID[6]),
        .AXI_06_WREADY      (S_AXI_WREADY[6]),
        .AXI_06_WDATA_PARITY(32'h0),
        .AXI_06_RDATA_PARITY(),

        // Write Response Channel
        .AXI_06_BRESP       (S_AXI_BRESP[6]),
        .AXI_06_BVALID      (S_AXI_BVALID[6]),
        .AXI_06_BREADY      (S_AXI_BREADY[6]),
        .AXI_06_BID         (),

        // Read Address Channel
        .AXI_06_ARADDR      (S_AXI_ARADDR[6]),
        .AXI_06_ARLEN       (4'h0),
        .AXI_06_ARSIZE      (3'b101),
        .AXI_06_ARBURST     (2'b01),
        .AXI_06_ARID        (6'b0),
        .AXI_06_ARVALID     (S_AXI_ARVALID[6]),
        .AXI_06_ARREADY     (S_AXI_ARREADY[6]),

        // Read Data Channel
        .AXI_06_RDATA       (S_AXI_RDATA[6]),
        .AXI_06_RLAST       (S_AXI_RLAST[6]),
        .AXI_06_RRESP       (S_AXI_RRESP[6]),
        .AXI_06_RVALID      (S_AXI_RVALID[6]),
        .AXI_06_RREADY      (S_AXI_RREADY[6]),
        .AXI_06_RID         ()
,

        // --- Channel 07 ---
        .AXI_07_ACLK        (S_AXI_CLK),
        .AXI_07_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_07_AWADDR      (S_AXI_AWADDR[7]),
        .AXI_07_AWLEN       (4'h0),
        .AXI_07_AWSIZE      (3'b101),
        .AXI_07_AWBURST     (2'b01),
        .AXI_07_AWID        (6'b0),
        .AXI_07_AWVALID     (S_AXI_AWVALID[7]),
        .AXI_07_AWREADY     (S_AXI_AWREADY[7]),

        // Write Data Channel
        .AXI_07_WDATA       (S_AXI_WDATA[7]),
        .AXI_07_WSTRB       (S_AXI_WSTRB[7]),
        .AXI_07_WLAST       (S_AXI_WLAST[7]),
        .AXI_07_WVALID      (S_AXI_WVALID[7]),
        .AXI_07_WREADY      (S_AXI_WREADY[7]),
        .AXI_07_WDATA_PARITY(32'h0),
        .AXI_07_RDATA_PARITY(),

        // Write Response Channel
        .AXI_07_BRESP       (S_AXI_BRESP[7]),
        .AXI_07_BVALID      (S_AXI_BVALID[7]),
        .AXI_07_BREADY      (S_AXI_BREADY[7]),
        .AXI_07_BID         (),

        // Read Address Channel
        .AXI_07_ARADDR      (S_AXI_ARADDR[7]),
        .AXI_07_ARLEN       (4'h0),
        .AXI_07_ARSIZE      (3'b101),
        .AXI_07_ARBURST     (2'b01),
        .AXI_07_ARID        (6'b0),
        .AXI_07_ARVALID     (S_AXI_ARVALID[7]),
        .AXI_07_ARREADY     (S_AXI_ARREADY[7]),

        // Read Data Channel
        .AXI_07_RDATA       (S_AXI_RDATA[7]),
        .AXI_07_RLAST       (S_AXI_RLAST[7]),
        .AXI_07_RRESP       (S_AXI_RRESP[7]),
        .AXI_07_RVALID      (S_AXI_RVALID[7]),
        .AXI_07_RREADY      (S_AXI_RREADY[7]),
        .AXI_07_RID         ()
,

        // --- Channel 08 ---
        .AXI_08_ACLK        (S_AXI_CLK),
        .AXI_08_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_08_AWADDR      (S_AXI_AWADDR[8]),
        .AXI_08_AWLEN       (4'h0),
        .AXI_08_AWSIZE      (3'b101),
        .AXI_08_AWBURST     (2'b01),
        .AXI_08_AWID        (6'b0),
        .AXI_08_AWVALID     (S_AXI_AWVALID[8]),
        .AXI_08_AWREADY     (S_AXI_AWREADY[8]),

        // Write Data Channel
        .AXI_08_WDATA       (S_AXI_WDATA[8]),
        .AXI_08_WSTRB       (S_AXI_WSTRB[8]),
        .AXI_08_WLAST       (S_AXI_WLAST[8]),
        .AXI_08_WVALID      (S_AXI_WVALID[8]),
        .AXI_08_WREADY      (S_AXI_WREADY[8]),
        .AXI_08_WDATA_PARITY(32'h0),
        .AXI_08_RDATA_PARITY(),

        // Write Response Channel
        .AXI_08_BRESP       (S_AXI_BRESP[8]),
        .AXI_08_BVALID      (S_AXI_BVALID[8]),
        .AXI_08_BREADY      (S_AXI_BREADY[8]),
        .AXI_08_BID         (),

        // Read Address Channel
        .AXI_08_ARADDR      (S_AXI_ARADDR[8]),
        .AXI_08_ARLEN       (4'h0),
        .AXI_08_ARSIZE      (3'b101),
        .AXI_08_ARBURST     (2'b01),
        .AXI_08_ARID        (6'b0),
        .AXI_08_ARVALID     (S_AXI_ARVALID[8]),
        .AXI_08_ARREADY     (S_AXI_ARREADY[8]),

        // Read Data Channel
        .AXI_08_RDATA       (S_AXI_RDATA[8]),
        .AXI_08_RLAST       (S_AXI_RLAST[8]),
        .AXI_08_RRESP       (S_AXI_RRESP[8]),
        .AXI_08_RVALID      (S_AXI_RVALID[8]),
        .AXI_08_RREADY      (S_AXI_RREADY[8]),
        .AXI_08_RID         ()
,

        // --- Channel 09 ---
        .AXI_09_ACLK        (S_AXI_CLK),
        .AXI_09_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_09_AWADDR      (S_AXI_AWADDR[9]),
        .AXI_09_AWLEN       (4'h0),
        .AXI_09_AWSIZE      (3'b101),
        .AXI_09_AWBURST     (2'b01),
        .AXI_09_AWID        (6'b0),
        .AXI_09_AWVALID     (S_AXI_AWVALID[9]),
        .AXI_09_AWREADY     (S_AXI_AWREADY[9]),

        // Write Data Channel
        .AXI_09_WDATA       (S_AXI_WDATA[9]),
        .AXI_09_WSTRB       (S_AXI_WSTRB[9]),
        .AXI_09_WLAST       (S_AXI_WLAST[9]),
        .AXI_09_WVALID      (S_AXI_WVALID[9]),
        .AXI_09_WREADY      (S_AXI_WREADY[9]),
        .AXI_09_WDATA_PARITY(32'h0),
        .AXI_09_RDATA_PARITY(),

        // Write Response Channel
        .AXI_09_BRESP       (S_AXI_BRESP[9]),
        .AXI_09_BVALID      (S_AXI_BVALID[9]),
        .AXI_09_BREADY      (S_AXI_BREADY[9]),
        .AXI_09_BID         (),

        // Read Address Channel
        .AXI_09_ARADDR      (S_AXI_ARADDR[9]),
        .AXI_09_ARLEN       (4'h0),
        .AXI_09_ARSIZE      (3'b101),
        .AXI_09_ARBURST     (2'b01),
        .AXI_09_ARID        (6'b0),
        .AXI_09_ARVALID     (S_AXI_ARVALID[9]),
        .AXI_09_ARREADY     (S_AXI_ARREADY[9]),

        // Read Data Channel
        .AXI_09_RDATA       (S_AXI_RDATA[9]),
        .AXI_09_RLAST       (S_AXI_RLAST[9]),
        .AXI_09_RRESP       (S_AXI_RRESP[9]),
        .AXI_09_RVALID      (S_AXI_RVALID[9]),
        .AXI_09_RREADY      (S_AXI_RREADY[9]),
        .AXI_09_RID         ()
,

        // --- Channel 10 ---
        .AXI_10_ACLK        (S_AXI_CLK),
        .AXI_10_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_10_AWADDR      (S_AXI_AWADDR[10]),
        .AXI_10_AWLEN       (4'h0),
        .AXI_10_AWSIZE      (3'b101),
        .AXI_10_AWBURST     (2'b01),
        .AXI_10_AWID        (6'b0),
        .AXI_10_AWVALID     (S_AXI_AWVALID[10]),
        .AXI_10_AWREADY     (S_AXI_AWREADY[10]),

        // Write Data Channel
        .AXI_10_WDATA       (S_AXI_WDATA[10]),
        .AXI_10_WSTRB       (S_AXI_WSTRB[10]),
        .AXI_10_WLAST       (S_AXI_WLAST[10]),
        .AXI_10_WVALID      (S_AXI_WVALID[10]),
        .AXI_10_WREADY      (S_AXI_WREADY[10]),
        .AXI_10_WDATA_PARITY(32'h0),
        .AXI_10_RDATA_PARITY(),

        // Write Response Channel
        .AXI_10_BRESP       (S_AXI_BRESP[10]),
        .AXI_10_BVALID      (S_AXI_BVALID[10]),
        .AXI_10_BREADY      (S_AXI_BREADY[10]),
        .AXI_10_BID         (),

        // Read Address Channel
        .AXI_10_ARADDR      (S_AXI_ARADDR[10]),
        .AXI_10_ARLEN       (4'h0),
        .AXI_10_ARSIZE      (3'b101),
        .AXI_10_ARBURST     (2'b01),
        .AXI_10_ARID        (6'b0),
        .AXI_10_ARVALID     (S_AXI_ARVALID[10]),
        .AXI_10_ARREADY     (S_AXI_ARREADY[10]),

        // Read Data Channel
        .AXI_10_RDATA       (S_AXI_RDATA[10]),
        .AXI_10_RLAST       (S_AXI_RLAST[10]),
        .AXI_10_RRESP       (S_AXI_RRESP[10]),
        .AXI_10_RVALID      (S_AXI_RVALID[10]),
        .AXI_10_RREADY      (S_AXI_RREADY[10]),
        .AXI_10_RID         ()
,

        // --- Channel 11 ---
        .AXI_11_ACLK        (S_AXI_CLK),
        .AXI_11_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_11_AWADDR      (S_AXI_AWADDR[11]),
        .AXI_11_AWLEN       (4'h0),
        .AXI_11_AWSIZE      (3'b101),
        .AXI_11_AWBURST     (2'b01),
        .AXI_11_AWID        (6'b0),
        .AXI_11_AWVALID     (S_AXI_AWVALID[11]),
        .AXI_11_AWREADY     (S_AXI_AWREADY[11]),

        // Write Data Channel
        .AXI_11_WDATA       (S_AXI_WDATA[11]),
        .AXI_11_WSTRB       (S_AXI_WSTRB[11]),
        .AXI_11_WLAST       (S_AXI_WLAST[11]),
        .AXI_11_WVALID      (S_AXI_WVALID[11]),
        .AXI_11_WREADY      (S_AXI_WREADY[11]),
        .AXI_11_WDATA_PARITY(32'h0),
        .AXI_11_RDATA_PARITY(),

        // Write Response Channel
        .AXI_11_BRESP       (S_AXI_BRESP[11]),
        .AXI_11_BVALID      (S_AXI_BVALID[11]),
        .AXI_11_BREADY      (S_AXI_BREADY[11]),
        .AXI_11_BID         (),

        // Read Address Channel
        .AXI_11_ARADDR      (S_AXI_ARADDR[11]),
        .AXI_11_ARLEN       (4'h0),
        .AXI_11_ARSIZE      (3'b101),
        .AXI_11_ARBURST     (2'b01),
        .AXI_11_ARID        (6'b0),
        .AXI_11_ARVALID     (S_AXI_ARVALID[11]),
        .AXI_11_ARREADY     (S_AXI_ARREADY[11]),

        // Read Data Channel
        .AXI_11_RDATA       (S_AXI_RDATA[11]),
        .AXI_11_RLAST       (S_AXI_RLAST[11]),
        .AXI_11_RRESP       (S_AXI_RRESP[11]),
        .AXI_11_RVALID      (S_AXI_RVALID[11]),
        .AXI_11_RREADY      (S_AXI_RREADY[11]),
        .AXI_11_RID         ()
,

        // --- Channel 12 ---
        .AXI_12_ACLK        (S_AXI_CLK),
        .AXI_12_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_12_AWADDR      (S_AXI_AWADDR[12]),
        .AXI_12_AWLEN       (4'h0),
        .AXI_12_AWSIZE      (3'b101),
        .AXI_12_AWBURST     (2'b01),
        .AXI_12_AWID        (6'b0),
        .AXI_12_AWVALID     (S_AXI_AWVALID[12]),
        .AXI_12_AWREADY     (S_AXI_AWREADY[12]),

        // Write Data Channel
        .AXI_12_WDATA       (S_AXI_WDATA[12]),
        .AXI_12_WSTRB       (S_AXI_WSTRB[12]),
        .AXI_12_WLAST       (S_AXI_WLAST[12]),
        .AXI_12_WVALID      (S_AXI_WVALID[12]),
        .AXI_12_WREADY      (S_AXI_WREADY[12]),
        .AXI_12_WDATA_PARITY(32'h0),
        .AXI_12_RDATA_PARITY(),

        // Write Response Channel
        .AXI_12_BRESP       (S_AXI_BRESP[12]),
        .AXI_12_BVALID      (S_AXI_BVALID[12]),
        .AXI_12_BREADY      (S_AXI_BREADY[12]),
        .AXI_12_BID         (),

        // Read Address Channel
        .AXI_12_ARADDR      (S_AXI_ARADDR[12]),
        .AXI_12_ARLEN       (4'h0),
        .AXI_12_ARSIZE      (3'b101),
        .AXI_12_ARBURST     (2'b01),
        .AXI_12_ARID        (6'b0),
        .AXI_12_ARVALID     (S_AXI_ARVALID[12]),
        .AXI_12_ARREADY     (S_AXI_ARREADY[12]),

        // Read Data Channel
        .AXI_12_RDATA       (S_AXI_RDATA[12]),
        .AXI_12_RLAST       (S_AXI_RLAST[12]),
        .AXI_12_RRESP       (S_AXI_RRESP[12]),
        .AXI_12_RVALID      (S_AXI_RVALID[12]),
        .AXI_12_RREADY      (S_AXI_RREADY[12]),
        .AXI_12_RID         ()
,

        // --- Channel 13 ---
        .AXI_13_ACLK        (S_AXI_CLK),
        .AXI_13_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_13_AWADDR      (S_AXI_AWADDR[13]),
        .AXI_13_AWLEN       (4'h0),
        .AXI_13_AWSIZE      (3'b101),
        .AXI_13_AWBURST     (2'b01),
        .AXI_13_AWID        (6'b0),
        .AXI_13_AWVALID     (S_AXI_AWVALID[13]),
        .AXI_13_AWREADY     (S_AXI_AWREADY[13]),

        // Write Data Channel
        .AXI_13_WDATA       (S_AXI_WDATA[13]),
        .AXI_13_WSTRB       (S_AXI_WSTRB[13]),
        .AXI_13_WLAST       (S_AXI_WLAST[13]),
        .AXI_13_WVALID      (S_AXI_WVALID[13]),
        .AXI_13_WREADY      (S_AXI_WREADY[13]),
        .AXI_13_WDATA_PARITY(32'h0),
        .AXI_13_RDATA_PARITY(),

        // Write Response Channel
        .AXI_13_BRESP       (S_AXI_BRESP[13]),
        .AXI_13_BVALID      (S_AXI_BVALID[13]),
        .AXI_13_BREADY      (S_AXI_BREADY[13]),
        .AXI_13_BID         (),

        // Read Address Channel
        .AXI_13_ARADDR      (S_AXI_ARADDR[13]),
        .AXI_13_ARLEN       (4'h0),
        .AXI_13_ARSIZE      (3'b101),
        .AXI_13_ARBURST     (2'b01),
        .AXI_13_ARID        (6'b0),
        .AXI_13_ARVALID     (S_AXI_ARVALID[13]),
        .AXI_13_ARREADY     (S_AXI_ARREADY[13]),

        // Read Data Channel
        .AXI_13_RDATA       (S_AXI_RDATA[13]),
        .AXI_13_RLAST       (S_AXI_RLAST[13]),
        .AXI_13_RRESP       (S_AXI_RRESP[13]),
        .AXI_13_RVALID      (S_AXI_RVALID[13]),
        .AXI_13_RREADY      (S_AXI_RREADY[13]),
        .AXI_13_RID         ()
,

        // --- Channel 14 ---
        .AXI_14_ACLK        (S_AXI_CLK),
        .AXI_14_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_14_AWADDR      (S_AXI_AWADDR[14]),
        .AXI_14_AWLEN       (4'h0),
        .AXI_14_AWSIZE      (3'b101),
        .AXI_14_AWBURST     (2'b01),
        .AXI_14_AWID        (6'b0),
        .AXI_14_AWVALID     (S_AXI_AWVALID[14]),
        .AXI_14_AWREADY     (S_AXI_AWREADY[14]),

        // Write Data Channel
        .AXI_14_WDATA       (S_AXI_WDATA[14]),
        .AXI_14_WSTRB       (S_AXI_WSTRB[14]),
        .AXI_14_WLAST       (S_AXI_WLAST[14]),
        .AXI_14_WVALID      (S_AXI_WVALID[14]),
        .AXI_14_WREADY      (S_AXI_WREADY[14]),
        .AXI_14_WDATA_PARITY(32'h0),
        .AXI_14_RDATA_PARITY(),

        // Write Response Channel
        .AXI_14_BRESP       (S_AXI_BRESP[14]),
        .AXI_14_BVALID      (S_AXI_BVALID[14]),
        .AXI_14_BREADY      (S_AXI_BREADY[14]),
        .AXI_14_BID         (),

        // Read Address Channel
        .AXI_14_ARADDR      (S_AXI_ARADDR[14]),
        .AXI_14_ARLEN       (4'h0),
        .AXI_14_ARSIZE      (3'b101),
        .AXI_14_ARBURST     (2'b01),
        .AXI_14_ARID        (6'b0),
        .AXI_14_ARVALID     (S_AXI_ARVALID[14]),
        .AXI_14_ARREADY     (S_AXI_ARREADY[14]),

        // Read Data Channel
        .AXI_14_RDATA       (S_AXI_RDATA[14]),
        .AXI_14_RLAST       (S_AXI_RLAST[14]),
        .AXI_14_RRESP       (S_AXI_RRESP[14]),
        .AXI_14_RVALID      (S_AXI_RVALID[14]),
        .AXI_14_RREADY      (S_AXI_RREADY[14]),
        .AXI_14_RID         ()
,

        // --- Channel 15 ---
        .AXI_15_ACLK        (S_AXI_CLK),
        .AXI_15_ARESET_N    (~reset),

        // Write Address Channel
        .AXI_15_AWADDR      (S_AXI_AWADDR[15]),
        .AXI_15_AWLEN       (4'h0),
        .AXI_15_AWSIZE      (3'b101),
        .AXI_15_AWBURST     (2'b01),
        .AXI_15_AWID        (6'b0),
        .AXI_15_AWVALID     (S_AXI_AWVALID[15]),
        .AXI_15_AWREADY     (S_AXI_AWREADY[15]),

        // Write Data Channel
        .AXI_15_WDATA       (S_AXI_WDATA[15]),
        .AXI_15_WSTRB       (S_AXI_WSTRB[15]),
        .AXI_15_WLAST       (S_AXI_WLAST[15]),
        .AXI_15_WVALID      (S_AXI_WVALID[15]),
        .AXI_15_WREADY      (S_AXI_WREADY[15]),
        .AXI_15_WDATA_PARITY(32'h0),
        .AXI_15_RDATA_PARITY(),

        // Write Response Channel
        .AXI_15_BRESP       (S_AXI_BRESP[15]),
        .AXI_15_BVALID      (S_AXI_BVALID[15]),
        .AXI_15_BREADY      (S_AXI_BREADY[15]),
        .AXI_15_BID         (),

        // Read Address Channel
        .AXI_15_ARADDR      (S_AXI_ARADDR[15]),
        .AXI_15_ARLEN       (4'h0),
        .AXI_15_ARSIZE      (3'b101),
        .AXI_15_ARBURST     (2'b01),
        .AXI_15_ARID        (6'b0),
        .AXI_15_ARVALID     (S_AXI_ARVALID[15]),
        .AXI_15_ARREADY     (S_AXI_ARREADY[15]),

        // Read Data Channel
        .AXI_15_RDATA       (S_AXI_RDATA[15]),
        .AXI_15_RLAST       (S_AXI_RLAST[15]),
        .AXI_15_RRESP       (S_AXI_RRESP[15]),
        .AXI_15_RVALID      (S_AXI_RVALID[15]),
        .AXI_15_RREADY      (S_AXI_RREADY[15]),
        .AXI_15_RID         ()




    );
`else
    // ======================================================================
    // Fast behavioral HBM read model (simulation only, `SIM_FAST_HBM).
    // Drop-in for the hbm_0 IP: instant calibration, 1-cycle-latency AXI reads
    // from a $readmemh image, and a faithful flat row-major address decode
    // (unlike the real sim model's open-page behaviour). Only the read path is
    // modelled (the FSM never writes: RW_en is held 0).
    // ======================================================================
    logic [255:0] hbm_mem [0:SIM_MEM_DEPTH-1];
    initial if (MEM_FILE != "") $readmemh(MEM_FILE, hbm_mem);

    assign apb_complete_0 = 1'b1;   // calibration complete immediately

    localparam logic B_IDLE = 1'b0, B_RESP = 1'b1;
    logic         bstate    [16];
    logic [255:0] rdata_reg [16];

    // ARADDR = (tr<<17) + (row<<13) + (tc<<5)  ->  linear image index
    //          [(tr*NUM_TC + tc)*16 + row].
    function automatic int unsigned decode_idx(input logic [33:0] araddr);
        int unsigned tr, tc, ch;
        tr = araddr >> 17;
        ch = (araddr >> 13) & 34'hF;
        tc = (araddr >> 5)  & 34'hFF;
        return (tr * NUM_TC + tc) * 16 + ch;
    endfunction

    always_ff @(posedge S_AXI_CLK) begin
        for (int ch = 0; ch < 16; ch++) begin
            if (reset) begin
                bstate[ch]       <= B_IDLE;
                S_AXI_RVALID[ch] <= 1'b0;
                rdata_reg[ch]    <= 256'h0;
            end else begin
                case (bstate[ch])
                    B_IDLE:
                        if (S_AXI_ARVALID[ch]) begin
                            automatic int unsigned idx;
                            idx              = decode_idx(S_AXI_ARADDR[ch]);
                            rdata_reg[ch]    <= (idx < SIM_MEM_DEPTH) ? hbm_mem[idx] : 256'h0;
                            S_AXI_RVALID[ch] <= 1'b1;
                            bstate[ch]       <= B_RESP;
                        end
                    B_RESP:
                        if (S_AXI_RREADY[ch]) begin
                            S_AXI_RVALID[ch] <= 1'b0;
                            bstate[ch]       <= B_IDLE;
                        end
                    default: bstate[ch] <= B_IDLE;
                endcase
            end
        end
    end

    always_comb begin
        for (int ch = 0; ch < 16; ch++) begin
            S_AXI_ARREADY[ch] = (bstate[ch] == B_IDLE);  // ready for a new address
            S_AXI_RDATA[ch]   = rdata_reg[ch];
            S_AXI_RRESP[ch]   = 2'b00;
            S_AXI_RLAST[ch]   = S_AXI_RVALID[ch];        // single-beat bursts
            // Write path unused; tie responses to benign values.
            S_AXI_AWREADY[ch] = 1'b1;
            S_AXI_WREADY[ch]  = 1'b1;
            S_AXI_BVALID[ch]  = 1'b0;
            S_AXI_BRESP[ch]   = 2'b00;
        end
    end
`endif

        logic [5:0] row;   // tile write index (from FSM_tile_counter)

    
    parameter [2:0]
        IDLE                 = 3'b000,
        START_IO_TRANSACTION = 3'b001,
        WRITE_ADDRESS        = 3'b010,
        WRITE_DATA           = 3'b011,
        WRITE_RESP           = 3'b100,
        READ_ADDRESS         = 3'b101,
        READ_DATA            = 3'b110;

    logic [2:0] state[16];

    // Next-state logic
    always_ff @(posedge S_AXI_CLK) begin
        if (reset) begin
            foreach(state[i])
                state[i] <= IDLE;
        end else begin
            foreach(state[i])begin
                case (state[i])
                    IDLE:                  if (start)
                                               state[i] <= START_IO_TRANSACTION;
                    START_IO_TRANSACTION:  state[i] <= RW_en[i] ? WRITE_ADDRESS : READ_ADDRESS;
                    WRITE_ADDRESS:         if (S_AXI_AWVALID[i] && S_AXI_AWREADY[i])
                                               state[i] <= WRITE_DATA;
                    WRITE_DATA:            if (S_AXI_WVALID[i] && S_AXI_WREADY[i] && S_AXI_WLAST[i])
                                               state[i] <= WRITE_RESP;
                    WRITE_RESP:            if (S_AXI_BVALID[i] && S_AXI_BREADY[i] && (S_AXI_BRESP[i] == 2'b00))
                                               state[i] <= IDLE;
                    READ_ADDRESS:          if (S_AXI_ARVALID[i] && S_AXI_ARREADY[i])
                                               state[i] <= READ_DATA;
                    READ_DATA:             if (S_AXI_RVALID[i] && S_AXI_RREADY[i] && S_AXI_RLAST[i])
                                               state[i] <= IDLE;
                    default:               state[i] <= IDLE;
                endcase
           end
        end
    end
    
    // NOTE: a dead, duplicate Q_bank generate block previously lived here. Its
    // outputs (dout_1/dout_2) were wired nowhere (the BRAM_TO_LUTRAM consumers
    // are commented out), and it failed elaboration ('dout_1[row]' is a variable
    // index on a structural output connection). The real BRAM path is
    // BRAM_parsing_inst below, so the dead block was removed. This does not touch
    // the deferred tile write-index sequencing (BRAM_parsing / FSM_tile_counter).

//    BRAM_TO_LUTRAM BRAM_TO_Q_LUTRAM(.clk(clk), .dout_1(dout_1), .dout_2(dout_2), .LUTRAM(Q_LUTRAM));
//    BRAM_TO_LUTRAM BRAM_TO_K_LUTRAM(.clk(clk), .dout_1(dout_1), .dout_2(dout_2), .LUTRAM(K_LUTRAM));

    // Output logic — safe defaults then per-state overrides
    always_comb begin
        foreach(state[i])
        begin
            S_AXI_AWVALID[i] = 1'b0;
            S_AXI_WVALID[i]  = 1'b0;
            S_AXI_WDATA[i]   = 256'h0;
            S_AXI_WSTRB[i]   = 32'h0;
            S_AXI_WLAST[i]   = 1'b0;
            S_AXI_BREADY[i]  = 1'b0;
            S_AXI_ARVALID[i] = 1'b0;
            S_AXI_RREADY[i]  = 1'b0;
            // S_AXI_ARADDR / S_AXI_AWADDR driven solely by the address always_comb above
        
            case (state[i])
                WRITE_ADDRESS: begin
                    S_AXI_AWVALID[i] = 1'b1;
                    S_AXI_WVALID[i]  = 1'b1;
                    S_AXI_WDATA[i]   = write_data[i];
                    S_AXI_WSTRB[i]   = 32'hFFFFFFFF;
                    S_AXI_WLAST[i]   = 1'b1;
                end
                WRITE_DATA: begin
                    S_AXI_WVALID[i]  = 1'b1;
                    S_AXI_WDATA[i]   = write_data[i];
                    S_AXI_WSTRB[i]   = 32'hFFFFFFFF;
                    S_AXI_WLAST[i]   = 1'b1;
                    S_AXI_BREADY[i]  = 1'b1;   // pre-assert
                end
                WRITE_RESP: begin
                    S_AXI_BREADY[i]  = 1'b1;
                end
                READ_ADDRESS: begin
                    S_AXI_ARVALID[i] = 1'b1;
                    S_AXI_RREADY[i]  = 1'b1;   // pre-assert
                end
                READ_DATA: begin
                    S_AXI_RREADY[i]  = 1'b1;
                end
                default: ;
            endcase
        end
    end

    // Latch read data on R-channel handshake
    always_ff @(posedge S_AXI_CLK) 
    begin
        for(int i = 0; i < 16; i++)begin
                if (reset) begin
                    read_data_out[i] <= 256'h0;
                    read_resp_out[i] <= 2'h0;
                end
                else if (S_AXI_RVALID[i] && S_AXI_RREADY[i]) begin
                    read_data_out[i] <= S_AXI_RDATA[i];
                    read_resp_out[i] <= S_AXI_RRESP[i];
                end
        end
    end

    // Clean transaction-complete pulse (single driver; replaces the old
    // multi-driver `done`). Asserts for one cycle when all 16 channels return to
    // IDLE after a launched transaction — by then read_data_out holds all 16
    // latched beats. Works for both the real IP and the SIM_FAST_HBM model.
    logic all_idle_c, busy_seen_r;
    always_comb begin
        all_idle_c = 1'b1;
        for (int i = 0; i < 16; i++)
            if (state[i] != IDLE) all_idle_c = 1'b0;
    end
    always_ff @(posedge S_AXI_CLK) begin
        if (reset) begin
            busy_seen_r <= 1'b0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;
            if (!all_idle_c)      busy_seen_r <= 1'b1;
            else if (busy_seen_r) begin
                done        <= 1'b1;
                busy_seen_r <= 1'b0;
            end
        end
    end

    FSM_tile_counter FSM_tile_counter_inst(
        .clk(clk),
        .reset(reset),
        .row(row)
    );
    
    
    logic[3:0] wea_q;
    logic[3:0] web_q;


    // Fix 3: drive the Q_bank byte write-enables (previously floating at X).
    // Full 32-bit enable while any channel is capturing R-channel data.
    // NOTE: the BRAM write-address sequencing (FSM_tile_counter / BRAM_parsing
    // 'row') is intentionally left untouched (user-owned) — see plan.
    logic bram_we;
    always_comb begin
        bram_we = 1'b0;
        for (int i = 0; i < 16; i++)
            if (S_AXI_RVALID[i] && S_AXI_RREADY[i])
                bram_we = 1'b1;
    end
    assign wea_q = bram_we ? 4'hF : 4'h0;
    assign web_q = bram_we ? 4'hF : 4'h0;

    logic[31:0] port_A_out[16][4];   // matches BRAM_parsing dout_1 [16][4]
    logic[31:0] port_B_out[16][4];   // matches BRAM_parsing dout_2 [16][4]
    

    // ------------------------------------------------------------------------
    // BRAM-write section (tile write-index sequencing) — USER-OWNED / WIP.
    // Temporarily disabled so the HBM read path can be verified (Tiers A/B/D).
    // It does NOT elaborate as written: BRAM_parsing structurally connects a
    // Q_bank output to dout_1[row][bank]/dout_2[row][bank] with a *runtime* row
    // index (HBM_to_BRAM.sv ~1023/1029: "'row' is not a constant") — a structural
    // output net-select must be static. Resolving this (the write-index / BRAM
    // output structure) is left to the user. The read datapath (read_data_out)
    // is independent of this block.
    // BRAM_parsing BRAM_parsing_inst(
    //     .clk(clk),
    //     .reset(reset),
    //     .wea_q(wea_q),
    //     .web_q(web_q),
    //     .row(row),
    //     .input_data(read_data_out),
    //     .dout_1(port_A_out),
    //     .dout_2(port_B_out)
    // );
    
    
endmodule

//module BRAM_parsing(
//    input  logic         clk,
//    input  logic         reset,
//    input  logic [3:0]   wea_q,
//    input  logic [3:0]   web_q,
//    input  logic [5:0]   row,
//    input  logic [255:0] input_data[16],
//    output logic [31:0]  dout_1 [16][4],   // port A from each bank
//    output logic [31:0]  dout_2 [16][4]    // port B from each bank
//);

////    BRAM_TO_LUTRAM BRAM_TO_Q_LUTRAM(.clk(clk), .dout_1(dout_1), .dout_2(dout_2), .LUTRAM(Q_LUTRAM));
////    BRAM_TO_LUTRAM BRAM_TO_K_LUTRAM(.clk(clk), .dout_1(dout_1), .dout_2(dout_2), .LUTRAM(K_LUTRAM));


//    genvar bank;
//    generate
//        for (bank = 0; bank < 4; bank++) begin : k_banks

//            Q_bank Q_bank_inst (
//                .clka  (clk),
//                .rsta  (reset),
//                .wea   (wea_q),
//                .addra (row<<1),
//                .dina  (input_data[row][bank*64      +: 32]),
//                .douta (dout_1[row][bank]),
//                .clkb  (clk),
//                .rstb  (reset),
//                .web   (web_q),
//                .addrb ((row<<1)+6'h1),
//                .dinb  (input_data[row][bank*64 + 32 +: 32]),
//                .doutb (dout_2[row][bank])
//            );
//        end
//    endgenerate

//endmodule


module FSM_tile_counter
(
     input logic start,
     input logic clk,
     input logic reset,
     output logic[7:0] row
     
);

parameter [4:0]
        IDLE  = 5'b00000,
        ROW_1 = 5'b00001,
        ROW_2 = 5'b00010,
        ROW_3 = 5'b00011,
        ROW_4 = 5'b00100,
        ROW_5 = 5'b00101,
        ROW_6 = 5'b00110,
        ROW_7 = 5'b00111,
        ROW_8 = 5'b01000,
        ROW_9 = 5'b01001,
        ROW_10 = 5'b01010,
        ROW_11 = 5'b01011,
        ROW_12 = 5'b01100,
        ROW_13 = 5'b01101,
        ROW_14 = 5'b01110,
        ROW_15 = 5'b01111,
        ROW_16 = 5'b10000;

logic [4:0] state;

always_ff @(posedge clk)
begin
    if(reset)
        state <= IDLE;
    else
    begin
        case(state)
            IDLE:
                state <=  start ? ROW_1 : IDLE;
            ROW_1:
                state <= ROW_2;
            ROW_2:
                state <= ROW_3;
            ROW_3:
                state <= ROW_4;
            ROW_4:
                state <= ROW_5;
            ROW_5:
                state <= ROW_6;
            ROW_6:
                state <= ROW_7;
            ROW_7:
                state <= ROW_8;
            ROW_8:
                state <= ROW_9;
            ROW_9:
                state <= ROW_10;
            ROW_10:
                state <= ROW_11;
            ROW_11:
                state <= ROW_12;
            ROW_12:
                state <= ROW_13;
            ROW_13:
                state <= ROW_14;
            ROW_14:
                state <= ROW_15;
            ROW_15:
                state <= ROW_16;
            ROW_16:
                state <= IDLE;

            default:
                state <= IDLE;
        endcase
    end
end

always_comb
begin
    case(state)
        IDLE:
            row = 6'd0;
        ROW_1:
            row = 6'd0;
        ROW_2:
            row = 6'd1;
        ROW_3:
            row = 6'd2;
        ROW_4:
            row = 6'd3;
        ROW_5:
            row = 6'd4;
        ROW_6:
            row = 6'd5;
        ROW_7:
            row = 6'd6;
        ROW_8:
            row = 6'd7;
        ROW_9:
            row = 6'd8;
        ROW_10:
            row = 6'd9;
        ROW_11:
            row = 6'd10;
        ROW_12:
            row = 6'd11;
        ROW_13:
            row = 6'd12;
        ROW_14:
            row = 6'd13;
        ROW_15:
            row = 6'd14;
        ROW_16:
            row = 6'd15;

        default:
            row = 6'd0;
    endcase
end
//logic[15:0] Q_LUTRAM[16][16];
//logic[15:0] K_LUTRAM[16][16];



endmodule

//module BRAM_TO_LUTRAM
//(
//    input logic clk,
//    input logic[31:0] dout_1[16][4],
//    input logic[31:0] dout_2[16][4],
//    output logic[15:0] LUTRAM[16][16]
//);
// always_ff @(posedge clk)
// begin
//    for(int i = 0; i < 16; i++)
//    begin
//        for(int b = 0; b < 4; b++)
//        begin
//            // bank-major, port A then port B; little-endian (low half -> lower slot)
//            LUTRAM[i][4*b + 0] <= dout_1[i][b][15:0];    // bank b, port A, BF16 low
//            LUTRAM[i][4*b + 1] <= dout_1[i][b][31:16];   // bank b, port A, BF16 high
//            LUTRAM[i][4*b + 2] <= dout_2[i][b][15:0];    // bank b, port B, BF16 low
//            LUTRAM[i][4*b + 3] <= dout_2[i][b][31:16];   // bank b, port B, BF16 high
//        end
//    end
//end
//endmodule
