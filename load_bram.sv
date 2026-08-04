`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: load_bram
// Description:
//   Second stage of the tile load pipeline (HBM -> BRAM -> LUTRAM).
//   Stages one 16x16 BF16 tile - delivered as 16 x 256-bit HBM beats - through a
//   4-bank, true-dual-port on-chip BRAM, then reads it back for the LUTRAM loader.
//
//   Column / bank layout (matches BRAM_TO_LUTRAM's unpack so its output feeds
//   straight into the LUTRAM tile):
//     bank b, port A  @ addr 2*row   -> row cols {4b,   4b+1}  = beat[64b      +: 32]
//     bank b, port B  @ addr 2*row+1 -> row cols {4b+2, 4b+3}  = beat[64b + 32 +: 32]
//   Each 32-bit word is two BF16, little-endian (lower column in [15:0]).
//
//   Sequencing (started by a 1-cycle `start` pulse):
//     WRITE : rows 0..15, both ports write their words into the four banks.
//     READ  : rows 0..15, both ports read; captured 1 cycle later (BRAM latency).
//     DRAIN : capture the final row's read-back.
//     DONE  : `done` pulses for one cycle with dout_1/dout_2 valid.
//
//   IS_K selects the K_bank IP core instead of Q_bank (identical 32b x 64
//   true-dual-port blk_mem_gen configuration) so Q and K stay on separate cores.
//////////////////////////////////////////////////////////////////////////////////

module load_bram #(parameter bit IS_K = 0)(
    input  logic         clk,
    input  logic         reset,
    input  logic         start,
    input  logic [255:0] beats_in [16],   // one 256-bit beat per tile row
    output logic [31:0]  dout_1 [16][4],  // port-A read-back, per row/bank
    output logic [31:0]  dout_2 [16][4],  // port-B read-back, per row/bank
    output logic         done
);

    localparam logic [2:0]
        IDLE  = 3'd0,
        WRITE = 3'd1,
        READ  = 3'd2,
        DRAIN = 3'd3,
        DONE  = 3'd4;

    logic [2:0] state;
    logic [3:0] cnt;                 // row walk (0..15) within WRITE / READ
    logic [3:0] row;
    assign row = cnt;

    // ---- Phase sequencer -----------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            cnt   <= 4'd0;
        end else begin
            case (state)
                IDLE:  if (start) begin state <= WRITE; cnt <= 4'd0; end
                WRITE: if (cnt == 4'd15) begin state <= READ;  cnt <= 4'd0; end
                       else                    cnt <= cnt + 4'd1;
                READ:  if (cnt == 4'd15) begin state <= DRAIN; cnt <= 4'd0; end
                       else                    cnt <= cnt + 4'd1;
                DRAIN: state <= DONE;
                DONE:  state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    // ---- Per-bank port wires -------------------------------------------------
    logic [5:0]  addr_a [4], addr_b [4];
    logic [31:0] din_a  [4], din_b  [4];
    logic [31:0] douta  [4], doutb  [4];
    logic [3:0]  wea, web;

    always_comb begin
        wea = (state == WRITE) ? 4'hF : 4'h0;
        web = (state == WRITE) ? 4'hF : 4'h0;
        for (int b = 0; b < 4; b++) begin
            addr_a[b] = {row, 1'b0};                 // 2*row
            addr_b[b] = {row, 1'b1};                 // 2*row + 1
            din_a[b]  = beats_in[row][64*b      +: 32];
            din_b[b]  = beats_in[row][64*b + 32 +: 32];
        end
    end

    // ---- BRAM 1-cycle read-latency pipeline ----------------------------------
    // The read data lags the address by one cycle, so the capture index must
    // follow the data, not the address.
    logic [3:0] row_d1;
    logic       read_d1;
    always_ff @(posedge clk) begin
        row_d1  <= row;
        read_d1 <= (state == READ);
    end

    // Capture read-back into the per-row/bank arrays. Variable-index writes are
    // legal here: this is a procedural write to a reg array, not a structural
    // net-select on the BRAM's `douta`/`doutb` outputs.
    always_ff @(posedge clk) begin
        if (read_d1) begin
            for (int b = 0; b < 4; b++) begin
                dout_1[row_d1][b] <= douta[b];
                dout_2[row_d1][b] <= doutb[b];
            end
        end
    end

    assign done = (state == DONE);

    // ---- BRAM IP banks (Q_bank or K_bank, 4 banks, true dual-port) -----------
    genvar bank;
    generate
        if (IS_K) begin : k_banks
            for (bank = 0; bank < 4; bank++) begin : b
                K_bank K_bank_inst (
                    .clka (clk), .rsta(reset), .wea(wea),
                    .addra(addr_a[bank]), .dina(din_a[bank]), .douta(douta[bank]),
                    .clkb (clk), .rstb(reset), .web(web),
                    .addrb(addr_b[bank]), .dinb(din_b[bank]), .doutb(doutb[bank])
                );
            end
        end else begin : q_banks
            for (bank = 0; bank < 4; bank++) begin : b
                Q_bank Q_bank_inst (
                    .clka (clk), .rsta(reset), .wea(wea),
                    .addra(addr_a[bank]), .dina(din_a[bank]), .douta(douta[bank]),
                    .clkb (clk), .rstb(reset), .web(web),
                    .addrb(addr_b[bank]), .dinb(din_b[bank]), .doutb(doutb[bank])
                );
            end
        end
    endgenerate

endmodule
