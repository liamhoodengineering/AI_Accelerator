`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: top
// Description: SRAM (BRAM IP) -> LUTRAM tile loader for Q and K.
//   - 4 banks per matrix, low-order 4-way interleaved (addr[1:0] = bank).
//   - Dual-port BRAM: port A = SRAM block 1, port B = SRAM block 2.
//   - Each port delivers 32 bits = 2 BF16 (little-endian:
//     lower-address word in [15:0], next-address word in [31:16]).
//   - Bank b, port A -> LUT columns {2b, 2b+1}.
//   - Bank b, port B -> LUT columns {2b+8, 2b+9}.
//   - K LUT is loaded transposed: source row r lands in LUT column r.
//
// Two phases (selected by preload_en):
//   - Preload phase (preload_en = 1): TB drives port A's addr / data / wea on
//     every bank to write known contents into all four Q banks and all four K
//     banks. The single Q_bank.xci / K_bank.xci IPs don't have separate init
//     files per bank, so the TB writes the per-bank data through the write
//     port instead.
//   - Test phase (preload_en = 0): load_row walks 0..15, BRAM dout streams
//     into the LUTRAM tiles via the load_row_d1 / load_en_d1 pipeline.
//////////////////////////////////////////////////////////////////////////////////

module top(
    input  logic        clk,
    input  logic        Reset,

    // Test-phase controls
    input  logic [3:0]  load_row,
    input  logic        load_en,

    // Preload-phase controls (port A of every bank is shared; per-bank data
    // because each bank holds a different slice of the matrix).
    input  logic        preload_en,
    input  logic [5:0]  preload_addr,
    input  logic [31:0] preload_q [4],
    input  logic [31:0] preload_k [4]
);

    // ---- Per-bank wires (4 banks, ports A and B) -----------------------------
    logic [5:0]  addr_q_1 [4], addr_q_2 [4];
    logic [5:0]  addr_k_1 [4], addr_k_2 [4];
    logic [31:0] din_q_1  [4], din_k_1  [4];
    logic [31:0] dout_q_1 [4], dout_q_2 [4];
    logic [31:0] dout_k_1 [4], dout_k_2 [4];

    logic [3:0] wea_q, web_q;
    logic [3:0] wea_k, web_k;

    // ---- LUTRAM tiles --------------------------------------------------------
    logic [15:0] q_tile_lut [16][16];
    logic [15:0] k_tile_lut [16][16];

    // ---- Address / data / write-enable mux (preload vs test) -----------------
    always_comb begin
        if (preload_en) begin
            // Preload: write the same address on all four banks of port A,
            // each carrying its own per-bank data. Port B is parked.
            wea_q = 4'b1111;
            web_q = 4'b0;
            wea_k = 4'b1111;
            web_k = 4'b0;
            for (int b = 0; b < 4; b++) begin
                addr_q_1[b] = preload_addr;
                addr_q_2[b] = 6'b0;
                addr_k_1[b] = preload_addr;
                addr_k_2[b] = 6'b0;
                din_q_1[b]  = preload_q[b];
                din_k_1[b]  = preload_k[b];
            end
        end
        else begin
            // Test: both ports of every bank read at offsets 2*load_row and
            // 2*load_row + 1 respectively. No writes.
            wea_q = 4'b0;
            web_q = 4'b0;
            wea_k = 4'b0;
            web_k = 4'b0;
            for (int b = 0; b < 4; b++) begin
                addr_q_1[b] = {1'b0, load_row, 1'b0};
                addr_q_2[b] = {1'b0, load_row, 1'b1};
                addr_k_1[b] = {1'b0, load_row, 1'b0};
                addr_k_2[b] = {1'b0, load_row, 1'b1};
                din_q_1[b]  = 32'b0;
                din_k_1[b]  = 32'b0;
            end
        end
    end

    // ---- BRAM-latency pipeline ----------------------------------------------
    // BRAM read latency is 1 cycle. The LUT-write target index has to follow
    // the data (which lags addr by one cycle), not the address.
    logic [3:0] load_row_d1;
    logic       load_en_d1;
    always_ff @(posedge clk) begin
        load_row_d1 <= load_row;
        load_en_d1  <= load_en;
    end

    // ---- LUTRAM load (Q untransposed, K transposed) --------------------------
    // Little-endian unpack: dout[15:0] is the BF16 at the lower address.
    // Concatenation puts the HIGHER index first: {col_hi, col_lo} <= dout.
    always_ff @(posedge clk) begin
        if (load_en_d1) begin
            for (int b = 0; b < 4; b++) begin
                // Q: bank b feeds cols {2b, 2b+1} (port A) and {2b+8, 2b+9} (port B)
                {q_tile_lut[load_row_d1][2*b+1], q_tile_lut[load_row_d1][2*b]  } <= dout_q_1[b];
                {q_tile_lut[load_row_d1][2*b+9], q_tile_lut[load_row_d1][2*b+8]} <= dout_q_2[b];

                // K (transposed): source row feeds LUT column load_row_d1
                {k_tile_lut[2*b+1][load_row_d1], k_tile_lut[2*b][load_row_d1]  } <= dout_k_1[b];
                {k_tile_lut[2*b+9][load_row_d1], k_tile_lut[2*b+8][load_row_d1]} <= dout_k_2[b];
            end
        end
    end

    // ---- BRAM IP instances (Q and K, 4 banks each, true dual-port) -----------
    genvar bank;
    generate
        for (bank = 0; bank < 4; bank++) begin : q_banks
            Q_bank Q_bank_inst (
                .clka (clk),  
                .addra(addr_q_1[bank]), 
                .dina(din_q_1[bank]),
                .douta(dout_q_1[bank]), 
                .rsta(Reset), 
                .wea(wea_q),
                .clkb (clk),  
                .addrb(addr_q_2[bank]), 
                .dinb(32'b0),
                .doutb(dout_q_2[bank]), 
                .rstb(Reset), 
                .web(web_q)
            );
        end

        for (bank = 0; bank < 4; bank++) begin : k_banks
            K_bank K_bank_inst (
                .clka (clk),  
                .addra(addr_k_1[bank]), 
                .dina(din_k_1[bank]),
                .douta(dout_k_1[bank]), 
                .rsta(Reset), 
                .wea(wea_k),
                .clkb (clk),  
                .addrb(addr_k_2[bank]), 
                .dinb(32'b0),
                .doutb(dout_k_2[bank]), 
                .rstb(Reset), 
                .web(web_k)
            );
        end
    endgenerate
    
    logic[15:0] logits[16][16];
    
    
    systolic_array_mult systolic_array_mult_inst(
        .reset(Reset),
        .clk(clk),
        .array_A(q_tile_lut),
        .array_B(k_tile_lut),
        .c_matrix(logits)
    );
    
    logic[15:0] logits_normalized[16][16];
    
    genvar softmax;
    generate
        for(softmax = 0; softmax < 16; softmax++)
        begin
            softermax normalized_inst(
                .logits(logits[softmax]),
                .clk(clk),
                .Reset(Reset),
                .logits_out(logits_normalized[softmax])
            );
        end
    endgenerate

endmodule
