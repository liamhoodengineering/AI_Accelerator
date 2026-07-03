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
  //  output logic [255:0] read_data_out,
    output logic [1:0]   read_resp_out,
    output logic         apb_complete_0  // HBM calibration done

);
   
    logic [255:0] read_data_out;
    
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
    
    logic[31:0] dout_1[4];
    logic[31:0] dout_2[4];
    
    //splits into 4 banks
    genvar bank;
    generate
        for (bank = 0; bank < 4; bank++) begin : q_banks
            Q_bank Q_bank_inst (
                .clka  (clk),
                .rsta  (reset),
                .wea   (wea_q),
                .addra (row<<1),
                .dina  (read_data_out[bank*64      +: 32]),
                .douta (dout_1[bank]),
                .clkb  (clk),
                .rstb  (reset),
                .web   (web_q),
                .addrb ((row<<1)+6'd1),
                .dinb  (read_data_out[bank*64 + 32 +: 32]),
                .doutb (dout_2[bank])
            );
        end
    endgenerate

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
    
    
    logic[3:0] wea_q, web_q;

BRAM_parsing BRAM_parsing_inst(
    .clk(clk),
    .reset(reset),
    .wea_q(wea_q),
    .web_q(web_q),
    .row(),
    .input_data(),
    .dout_1(),
    .dout_2()
    
);

    
endmodule

module BRAM_parsing(
    input  logic         clk,
    input  logic         reset,
    input  logic [3:0]   wea_q,
    input  logic [3:0]   web_q,
    input  logic [5:0]   row,
    input  logic [255:0] input_data,
    output logic [31:0]  dout_1 [16][4],   // port A from each bank
    output logic [31:0]  dout_2 [16][4]    // port B from each bank
);

    genvar bank;
    generate
        for (bank = 0; bank < 4; bank++) begin : q_banks
            Q_bank Q_bank_inst (
                .clka  (clk),
                .rsta  (reset),
                .wea   (wea_q),
                .addra (row<<1),
                .dina  (input_data[bank*64      +: 32]),
                .douta (dout_1[bank]),
                .clkb  (clk),
                .rstb  (reset),
                .web   (web_q),
                .addrb ((row<<1)+6'h1),
                .dinb  (input_data[bank*64 + 32 +: 32]),
                .doutb (dout_2[bank])
            );
        end
    endgenerate

endmodule


module FSM_tile_counter
(
     input logic clk,
     input logic reset,
     output logic[5:0] row
     
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
                state <= ROW_1;
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

endmodule

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
        for(int j = 0; j < 16; j++)
        begin
            {Q_LUTRAM[i][j+1],Q_LUTRAM[i][j]}  <= (j[0] == 0) ? Q_bank_dout_1[i][j] : Q_bank_dout_2[i][j];
        end
        
    end
end
endmodule
