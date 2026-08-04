`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: FSM_tiling
// Description:
//   Top-level control for the tiled QK^T (logit) computation. For each output
//   tile (i,j) it accumulates, over the contraction tiles k, the 16x16 product
//   q_tile[i,k] @ k_tile[j,k].T  (matrix_QT in python_verification/
//   dot_product_attention.py).
//
//   The per-tile load path is now three separate, per-matrix stages, each
//   instantiated twice (Q untransposed, K transposed) with a clean start/done
//   handshake:
//     LD_HBM    : HBM_to_BRAM   -> 16 x 256-bit beats           (read_data_out)
//     LD_BRAM   : load_bram     -> BRAM write/read-back         (dout_1/dout_2)
//     LD_LUTRAM : BRAM_TO_LUTRAM-> 16x16 LUTRAM tile            (q/k_tile_lut)
//   followed by SYST_MULT (systolic_array_mult) and ACCUMULATE (fold the
//   product into the running logit tile).
//
//   State flow: IDLE -> LD_HBM -> LD_BRAM -> LD_LUTRAM -> SYST_MULT
//               -> ACCUMULATE -> (LD_HBM for the next tile | IDLE when done).
//////////////////////////////////////////////////////////////////////////////////

module FSM_tiling #(
    // Tiling bounds (block units): Q/K rows = seq/16, contraction = D/16.
    // Parameterized so a testbench can shrink the tile grid (control logic is
    // size-invariant); defaults are the full-matrix values (synthesis unchanged).
    parameter int ROWS = 512,   // row-blocks (i, and j over K rows)
    parameter int COLS = 256,   // contraction blocks (k)
    // Sim-only: fast behavioral HBM memory image per matrix (see SIM_FAST_HBM in
    // HBM_to_BRAM.sv). Ignored when the real hbm_0 IP is compiled in.
    parameter string Q_MEM_FILE = "",
    parameter string K_MEM_FILE = ""
)(
    input  logic        start,
    input  logic        reset,
    input  logic        clk,
    // Exposed for verification: the running logit tile and a completion strobe.
    output logic [15:0] logit_tile_out [16][16],
    output logic        tile_valid,
    output logic        busy
    );

    // ---- FSM states ----------------------------------------------------------
    localparam logic [6:0]
        IDLE       = 7'b0000000,
        LD_HBM     = 7'b0000001,
        LD_BRAM    = 7'b0000010,
        LD_LUTRAM  = 7'b0000100,
        SYST_MULT  = 7'b0001000,
        ACCUMULATE = 7'b0010000;

    logic [6:0] state, state_d1;

    // ---- Load-stage handshake signals ---------------------------------------
    logic LD_HBM_start_q,    LD_HBM_start_k;
    logic LD_HBM_done_q,     LD_HBM_done_k;
    logic LD_BRAM_start_q,   LD_BRAM_start_k;
    logic LD_BRAM_done_q,    LD_BRAM_done_k;
    logic LD_LUTRAM_start_q, LD_LUTRAM_start_k;
    logic LD_LUTRAM_done_q,  LD_LUTRAM_done_k;

    logic systolic_mult_start;
    logic logit_mult_done;
    logic acc_start;
    logic logit_acc_done;

    // ---- Tile index counters (i: Q row, j: K row, k: contraction) -----------
    logic [16:0] i, j, k;

    logic tile_complete;    // one (i,j) logit tile finished (k swept all COLS)
    logic matrix_complete;  // last tile of the whole matrix
    assign tile_complete   = logit_acc_done && (k == 17'(COLS - 1));
    assign matrix_complete = tile_complete && (j == 17'(ROWS - 1))
                                           && (i == 17'(ROWS - 1));

    // ---- Row-major block addresses: block = {row[8:0], col[7:0]} -------------
    // Q tile (row-block i, contraction block k); K tile (row-block j, block k).
    // Parenthesised shift fixes the '+' > '<<' precedence bug of the old code.
    logic [16:0] block_addr_q, block_addr_k;
    assign block_addr_q = (i << 8) + k;
    assign block_addr_k = (j << 8) + k;

    // ---- Next-state logic ----------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else begin
            case (state)
                IDLE:       state <= start ? LD_HBM : IDLE;
                LD_HBM:     state <= (LD_HBM_done_q    && LD_HBM_done_k)    ? LD_BRAM    : LD_HBM;
                LD_BRAM:    state <= (LD_BRAM_done_q   && LD_BRAM_done_k)   ? LD_LUTRAM  : LD_BRAM;
                LD_LUTRAM:  state <= (LD_LUTRAM_done_q && LD_LUTRAM_done_k) ? SYST_MULT  : LD_LUTRAM;
                SYST_MULT:  state <= logit_mult_done ? ACCUMULATE : SYST_MULT;
                ACCUMULATE: state <= logit_acc_done
                                       ? (matrix_complete ? IDLE : LD_HBM)
                                       : ACCUMULATE;
                default:    state <= IDLE;
            endcase
        end
    end

    always_ff @(posedge clk)
        state_d1 <= reset ? IDLE : state;

    assign busy = (state != IDLE);

    // ---- Per-stage START pulses (1 cycle on state entry) --------------------
    // Level-holding a start into the load modules would re-trigger them when
    // they return to IDLE, so each stage is kicked with a single-cycle pulse.
    logic entered_hbm, entered_bram, entered_lutram, entered_syst, entered_acc;
    assign entered_hbm    = (state == LD_HBM)    && (state_d1 != LD_HBM);
    assign entered_bram   = (state == LD_BRAM)   && (state_d1 != LD_BRAM);
    assign entered_lutram = (state == LD_LUTRAM) && (state_d1 != LD_LUTRAM);
    assign entered_syst   = (state == SYST_MULT) && (state_d1 != SYST_MULT);
    assign entered_acc    = (state == ACCUMULATE)&& (state_d1 != ACCUMULATE);

    assign LD_HBM_start_q    = entered_hbm;
    assign LD_HBM_start_k    = entered_hbm;
    assign LD_BRAM_start_q   = entered_bram;
    assign LD_BRAM_start_k   = entered_bram;
    assign LD_LUTRAM_start_q = entered_lutram;
    assign LD_LUTRAM_start_k = entered_lutram;
    assign systolic_mult_start = entered_syst;
    assign acc_start           = entered_acc;

    // ---- Tile index advance --------------------------------------------------
    // Nested counters: k (contraction) innermost, then j (K row), then i (Q row).
    always_ff @(posedge clk) begin
        if (reset) begin
            i <= 17'd0;
            j <= 17'd0;
            k <= 17'd0;
        end else if (logit_acc_done) begin
            if (k == 17'(COLS - 1)) begin
                k <= 17'd0;
                if (j == 17'(ROWS - 1)) begin
                    j <= 17'd0;
                    i <= (i == 17'(ROWS - 1)) ? 17'd0 : i + 17'd1;
                end else
                    j <= j + 17'd1;
            end else
                k <= k + 17'd1;
        end
    end

    // =========================================================================
    // Stage 1: HBM -> beats  (reuse HBM_to_BRAM read path, read-only)
    // =========================================================================
    logic [255:0] beats_q [16], beats_k [16];
    logic [1:0]   read_resp_q [16], read_resp_k [16];
    logic         apb_complete_q, apb_complete_k;

    // Read-only: RW_en all-0, write side tied off.
    logic         rw_read [16];
    logic [255:0] wdata_zero [16];
    always_comb begin
        for (int c = 0; c < 16; c++) begin
            rw_read[c]    = 1'b0;
            wdata_zero[c] = 256'h0;
        end
    end

    HBM_to_BRAM #(.MEM_FILE(Q_MEM_FILE), .NUM_TC(COLS)) HBM_to_BRAM_q (
        .read_block_address (block_addr_q),
        .write_block_address(17'h0),
        .write_data         (wdata_zero),
        .RW_en              (rw_read),
        .start              (LD_HBM_start_q),
        .clk                (clk),
        .reset              (reset),
        .HBM_REF_CLK_0      (clk),
        .APB_0_PCLK         (clk),
        .read_data_out      (beats_q),
        .read_resp_out      (read_resp_q),
        .apb_complete_0     (apb_complete_q),
        .AWADDR_TEST        (),
        .ARADDR_TEST        (),
        .done               (LD_HBM_done_q)
    );

    HBM_to_BRAM #(.MEM_FILE(K_MEM_FILE), .NUM_TC(COLS)) HBM_to_BRAM_k (
        .read_block_address (block_addr_k),
        .write_block_address(17'h0),
        .write_data         (wdata_zero),
        .RW_en              (rw_read),
        .start              (LD_HBM_start_k),
        .clk                (clk),
        .reset              (reset),
        .HBM_REF_CLK_0      (clk),
        .APB_0_PCLK         (clk),
        .read_data_out      (beats_k),
        .read_resp_out      (read_resp_k),
        .apb_complete_0     (apb_complete_k),
        .AWADDR_TEST        (),
        .ARADDR_TEST        (),
        .done               (LD_HBM_done_k)
    );

    // =========================================================================
    // Stage 2: beats -> BRAM -> read-back  (load_bram, per matrix)
    // =========================================================================
    logic [31:0] q_dout_1 [16][4], q_dout_2 [16][4];
    logic [31:0] k_dout_1 [16][4], k_dout_2 [16][4];

    load_bram #(.IS_K(1'b0)) load_bram_q (
        .clk(clk), .reset(reset), .start(LD_BRAM_start_q),
        .beats_in(beats_q),
        .dout_1(q_dout_1), .dout_2(q_dout_2),
        .done(LD_BRAM_done_q)
    );

    load_bram #(.IS_K(1'b1)) load_bram_k (
        .clk(clk), .reset(reset), .start(LD_BRAM_start_k),
        .beats_in(beats_k),
        .dout_1(k_dout_1), .dout_2(k_dout_2),
        .done(LD_BRAM_done_k)
    );

    // =========================================================================
    // Stage 3: BRAM read-back -> LUTRAM tile  (BRAM_TO_LUTRAM, K transposed)
    // =========================================================================
    logic [15:0] q_tile_lut [16][16];
    logic [15:0] k_tile_lut [16][16];

    BRAM_TO_LUTRAM #(.ROW(16)) lutram_q (
        .start(LD_LUTRAM_start_q),
        .is_transpose(1'b0),
        .clk(clk),
        .Q_bank_dout_1(q_dout_1),
        .Q_bank_dout_2(q_dout_2),
        .Q_LUTRAM(q_tile_lut),
        .done(LD_LUTRAM_done_q)
    );

    BRAM_TO_LUTRAM #(.ROW(16)) lutram_k (
        .start(LD_LUTRAM_start_k),
        .is_transpose(1'b1),          // K loaded transposed for q @ k.T
        .clk(clk),
        .Q_bank_dout_1(k_dout_1),
        .Q_bank_dout_2(k_dout_2),
        .Q_LUTRAM(k_tile_lut),
        .done(LD_LUTRAM_done_k)
    );

    // =========================================================================
    // Stage 4: systolic multiply  q_tile @ k_tile(.T loaded) -> temp product
    // =========================================================================
    logic [15:0] temp_logit_tile_lut [16][16];

    systolic_array_mult #(.ROWS(16), .COLS(16)) logit_mult (
        .reset(reset),
        .clk(clk),
        .start(systolic_mult_start),
        .array_A(q_tile_lut),
        .array_B(k_tile_lut),
        .c_matrix(temp_logit_tile_lut),
        .done_out(logit_mult_done)
    );

    // =========================================================================
    // Stage 5: accumulate the product into the running logit tile
    // =========================================================================
    // Registered accumulate (breaks the read+write comb loop of the old code).
    // `first` (k==0) seeds the tile with the systolic product; later k-tiles add.
    logic [15:0] logit_tile_lut [16][16];

    accumulate_tile_output accumulate_tile_output_inst (
        .clk(clk),
        .reset(reset),
        .start(acc_start),
        .first(k == 17'd0),
        .array_in(temp_logit_tile_lut),
        .array_out(logit_tile_lut),
        .done(logit_acc_done)
    );

    assign logit_tile_out = logit_tile_lut;
    assign tile_valid     = tile_complete;

endmodule


// ---------------------------------------------------------------------------
// Registered tile accumulator: array_out += array_in on each `start` pulse,
// or is seeded with array_in when `first` is asserted (start of a new (i,j)
// tile). Feedback through the register avoids the combinational loop the old
// always_comb version had (it aliased array_out to one of its own inputs).
// ---------------------------------------------------------------------------
module accumulate_tile_output
(
    input  logic        clk,
    input  logic        reset,
    input  logic        start,          // 1-cycle: fold array_in into the tile
    input  logic        first,          // 1: seed (ignore accumulator); 0: add
    input  logic [15:0] array_in  [16][16],
    output logic [15:0] array_out [16][16],
    output logic        done
);
    always_ff @(posedge clk) begin
        if (reset)
            done <= 1'b0;
        else if (start) begin
            for (int r = 0; r < 16; r++)
                for (int c = 0; c < 16; c++)
                    array_out[r][c] <= first ? array_in[r][c]
                                             : (array_out[r][c] + array_in[r][c]);
            done <= 1'b1;
        end
        else
            done <= 1'b0;
    end
endmodule
