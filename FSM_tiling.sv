`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: FSM_tiling
// Description:
//   Tiled flash-attention control. For each query block i it sweeps key blocks j;
//   for each (i,j) it builds the 16x16 logit tile QK^T over the contraction tiles
//   k, scales it by 1/sqrt(D), then runs softermax (fused softmax + V multiply)
//   for the 16 query rows, CARRYING the running (max,sum,output) across j (online /
//   flash attention). When j sweeps all key blocks, o[16][16] is the attention
//   output tile for query block i.
//
//   State flow: IDLE -> [ LD_HBM -> LD_BRAM -> LD_LUTRAM -> SYST_MULT -> ACCUMULATE ]
//               (repeat over k to build the logit tile) -> SOFTMAX_V (flash update
//               over 16 rows) -> next j (carry stats) or next i (emit out_tile,
//               reset stats) -> IDLE when done.
//
//   Reference: python_verification/dot_product_attention.py (online tiled attention)
//   and verify_flash_v.py (base-2 per-row flash recursion, matches softermax.sv).
//////////////////////////////////////////////////////////////////////////////////

module FSM_tiling #(
    
    parameter int ROWS = 512,   // row-blocks (query i, key j)
    parameter int COLS = 256,   // contraction blocks (k) for QK^T
    parameter int SCALE_SHIFT = 2, // logit scale = 1/2^SCALE_SHIFT (=/4 for D=16)
    // Sim-only fast-HBM images (see SIM_FAST_HBM in HBM_to_BRAM.sv).
    parameter string Q_MEM_FILE = "",
    parameter string K_MEM_FILE = "",
    parameter string V_MEM_FILE = ""
)(
    input  logic        start,
    input  logic        reset,
    input  logic        clk,
    // Logit tile (QK^T) + strobe — kept for regression against the logit gold.
    output logic [15:0] logit_tile_out [16][16],
    output logic        tile_valid,
    // Flash-attention output tile for a query block + strobe.
    output logic [15:0] out_tile [16][16],
    output logic        out_valid,
    output logic        busy
    );

    // ---- FSM states ----------------------------------------------------------
    localparam logic [6:0]
        IDLE       = 7'b0000000,
        LD_HBM     = 7'b0000001,
        LD_BRAM    = 7'b0000010,
        LD_LUTRAM  = 7'b0000100,
        SYST_MULT  = 7'b0001000,
        ACCUMULATE = 7'b0010000,
        SOFTMAX_V  = 7'b0100000;

    logic [6:0] state, state_d1;

    // ---- Load-stage handshakes (Q, K, V) -------------------------------------
    logic LD_HBM_start_q,    LD_HBM_start_k,    LD_HBM_start_v;
    logic LD_HBM_done_q,     LD_HBM_done_k,     LD_HBM_done_v;
    logic LD_BRAM_start_q,   LD_BRAM_start_k,   LD_BRAM_start_v;
    logic LD_BRAM_done_q,    LD_BRAM_done_k,    LD_BRAM_done_v;
    logic LD_LUTRAM_start_q, LD_LUTRAM_start_k, LD_LUTRAM_start_v;
    logic LD_LUTRAM_done_q,  LD_LUTRAM_done_k,  LD_LUTRAM_done_v;

    logic systolic_mult_start;
    logic logit_mult_done;
    logic acc_start;
    logic logit_acc_done;

    // ---- Tile index counters -------------------------------------------------
    logic [16:0] i, j, k;   // i: query row-block, j: key row-block, k: contraction

    logic tile_complete;    // logit tile (i,j) done (k swept COLS)
    logic softv_done;       // flash update for (i,j) done (all 16 rows)
    logic matrix_complete;  // whole attention output finished
    assign tile_complete   = logit_acc_done && (k == 17'(COLS - 1));//finished the accumulation and on the last block of the row
    assign matrix_complete = softv_done && (j == 17'(ROWS - 1)) && (i == 17'(ROWS - 1));

    // ---- Row-major block addresses: block = {row[8:0], col[7:0]} -------------
    logic [16:0] block_addr_q, block_addr_k, block_addr_v;
    assign block_addr_q = (i << 8) + k;   // Q tile (row i, contraction k)
    assign block_addr_k = (j << 8) + k;   // K tile (row j, contraction k)
    assign block_addr_v = (j << 8);       // V tile (row j, feature block 0; D=16)

    // ---- Next-state logic ----------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset)
            state <= IDLE;
        else begin
            case (state)
                IDLE:       state <= start ? LD_HBM : IDLE;
                LD_HBM:     state <= (LD_HBM_done_q && LD_HBM_done_k && LD_HBM_done_v)
                                        ? LD_BRAM : LD_HBM;//loads from HBM
                LD_BRAM:    state <= (LD_BRAM_done_q && LD_BRAM_done_k && LD_BRAM_done_v)
                                        ? LD_LUTRAM : LD_BRAM;//loads into BRAM
                LD_LUTRAM:  state <= (LD_LUTRAM_done_q && LD_LUTRAM_done_k && LD_LUTRAM_done_v)
                                        ? SYST_MULT : LD_LUTRAM;//loads BRAM into LUTRAM
                SYST_MULT:  state <= logit_mult_done ? ACCUMULATE : SYST_MULT;//multiplies query and key transpose matrices
                ACCUMULATE: state <= logit_acc_done
                                        ? (tile_complete ? SOFTMAX_V : LD_HBM)  // next k, or flash
                                        : ACCUMULATE;
                SOFTMAX_V:  state <= softv_done
                                        ? (matrix_complete ? IDLE : LD_HBM)     // next (i,j)
                                        : SOFTMAX_V;
                default:    state <= IDLE;
            endcase
        end
    end

    always_ff @(posedge clk)
        state_d1 <= reset ? IDLE : state;

    assign busy = (state != IDLE);

    // ---- Per-stage START pulses (1 cycle on state entry) --------------------
    logic entered_hbm, entered_bram, entered_lutram, entered_syst, entered_acc, entered_softv;
    assign entered_hbm    = (state == LD_HBM)    && (state_d1 != LD_HBM);
    assign entered_bram   = (state == LD_BRAM)   && (state_d1 != LD_BRAM);
    assign entered_lutram = (state == LD_LUTRAM) && (state_d1 != LD_LUTRAM);
    assign entered_syst   = (state == SYST_MULT) && (state_d1 != SYST_MULT);
    assign entered_acc    = (state == ACCUMULATE)&& (state_d1 != ACCUMULATE);
    assign entered_softv  = (state == SOFTMAX_V) && (state_d1 != SOFTMAX_V);

    assign LD_HBM_start_q    = entered_hbm;
    assign LD_HBM_start_k    = entered_hbm;
    assign LD_HBM_start_v    = entered_hbm;
    assign LD_BRAM_start_q   = entered_bram;
    assign LD_BRAM_start_k   = entered_bram;
    assign LD_BRAM_start_v   = entered_bram;
    assign LD_LUTRAM_start_q = entered_lutram;
    assign LD_LUTRAM_start_k = entered_lutram;
    assign LD_LUTRAM_start_v = entered_lutram;
    assign systolic_mult_start = entered_syst;
    assign acc_start           = entered_acc;

    // ---- Tile index advance --------------------------------------------------
    // k advances while building the logit tile; j/i advance after the flash stage.
    always_ff @(posedge clk) begin
        if (reset) begin
            i <= 17'd0; j <= 17'd0; k <= 17'd0;
        end else begin
            if (logit_acc_done)
                k <= (k == 17'(COLS - 1)) ? 17'd0 : k + 17'd1;//last block in row
            if (softv_done) begin
                if (j == 17'(ROWS - 1)) begin
                    j <= 17'd0;
                    i <= (i == 17'(ROWS - 1)) ? 17'd0 : i + 17'd1;
                end else
                    j <= j + 17'd1;
            end
        end
    end

    // =========================================================================
    // Stage 1: HBM -> beats  (HBM_to_BRAM read path, per matrix)
    // =========================================================================
    logic [255:0] beats_q [16], beats_k [16], beats_v [16];
    logic [1:0]   read_resp_q [16], read_resp_k [16], read_resp_v [16];
    logic         apb_complete_q, apb_complete_k, apb_complete_v;

    logic         rw_read [16];
    logic [255:0] wdata_zero [16];
    always_comb begin
        for (int c = 0; c < 16; c++) begin
            rw_read[c]    = 1'b0;
            wdata_zero[c] = 256'h0;
        end
    end

    HBM_to_BRAM #(.MEM_FILE(Q_MEM_FILE), .NUM_TC(COLS)) HBM_to_BRAM_q (
        .read_block_address(block_addr_q), .write_block_address(17'h0),
        .write_data(wdata_zero), .RW_en(rw_read), .start(LD_HBM_start_q),
        .clk(clk), .reset(reset), .HBM_REF_CLK_0(clk), .APB_0_PCLK(clk),
        .read_data_out(beats_q), .read_resp_out(read_resp_q),
        .apb_complete_0(apb_complete_q), .AWADDR_TEST(), .ARADDR_TEST(),
        .done(LD_HBM_done_q)
    );
    HBM_to_BRAM #(.MEM_FILE(K_MEM_FILE), .NUM_TC(COLS)) HBM_to_BRAM_k (
        .read_block_address(block_addr_k), .write_block_address(17'h0),
        .write_data(wdata_zero), .RW_en(rw_read), .start(LD_HBM_start_k),
        .clk(clk), .reset(reset), .HBM_REF_CLK_0(clk), .APB_0_PCLK(clk),
        .read_data_out(beats_k), .read_resp_out(read_resp_k),
        .apb_complete_0(apb_complete_k), .AWADDR_TEST(), .ARADDR_TEST(),
        .done(LD_HBM_done_k)
    );
    HBM_to_BRAM #(.MEM_FILE(V_MEM_FILE), .NUM_TC(COLS)) HBM_to_BRAM_v (
        .read_block_address(block_addr_v), .write_block_address(17'h0),
        .write_data(wdata_zero), .RW_en(rw_read), .start(LD_HBM_start_v),
        .clk(clk), .reset(reset), .HBM_REF_CLK_0(clk), .APB_0_PCLK(clk),
        .read_data_out(beats_v), .read_resp_out(read_resp_v),
        .apb_complete_0(apb_complete_v), .AWADDR_TEST(), .ARADDR_TEST(),
        .done(LD_HBM_done_v)
    );

    // =========================================================================
    // Stage 2: beats -> BRAM -> read-back  (load_bram, per matrix)
    // =========================================================================
    logic [31:0] q_dout_1 [16][4], q_dout_2 [16][4];
    logic [31:0] k_dout_1 [16][4], k_dout_2 [16][4];
    logic [31:0] v_dout_1 [16][4], v_dout_2 [16][4];

    load_bram #(.IS_K(1'b0)) load_bram_q (
        .clk(clk), .reset(reset), .start(LD_BRAM_start_q),
        .beats_in(beats_q), .dout_1(q_dout_1), .dout_2(q_dout_2), .done(LD_BRAM_done_q));
    load_bram #(.IS_K(1'b1)) load_bram_k (
        .clk(clk), .reset(reset), .start(LD_BRAM_start_k),
        .beats_in(beats_k), .dout_1(k_dout_1), .dout_2(k_dout_2), .done(LD_BRAM_done_k));
    load_bram #(.IS_K(1'b0)) load_bram_v (      // V untransposed
        .clk(clk), .reset(reset), .start(LD_BRAM_start_v),
        .beats_in(beats_v), .dout_1(v_dout_1), .dout_2(v_dout_2), .done(LD_BRAM_done_v));

    // =========================================================================
    // Stage 3: BRAM read-back -> LUTRAM tile  (BRAM_TO_LUTRAM)
    // =========================================================================
    logic [15:0] q_tile_lut [16][16];
    logic [15:0] k_tile_lut [16][16];
    logic [15:0] v_tile_lut [16][16];

    BRAM_TO_LUTRAM #(.ROW(16)) lutram_q (
        .start(LD_LUTRAM_start_q), .is_transpose(1'b0), .clk(clk),
        .Q_bank_dout_1(q_dout_1), .Q_bank_dout_2(q_dout_2),
        .Q_LUTRAM(q_tile_lut), .done(LD_LUTRAM_done_q));
    BRAM_TO_LUTRAM #(.ROW(16)) lutram_k (
        .start(LD_LUTRAM_start_k), .is_transpose(1'b1),   // K transposed for q @ k.T
        .clk(clk), .Q_bank_dout_1(k_dout_1), .Q_bank_dout_2(k_dout_2),
        .Q_LUTRAM(k_tile_lut), .done(LD_LUTRAM_done_k));
    BRAM_TO_LUTRAM #(.ROW(16)) lutram_v (
        .start(LD_LUTRAM_start_v), .is_transpose(1'b0),   // V untransposed: V[key][feature]
        .clk(clk), .Q_bank_dout_1(v_dout_1), .Q_bank_dout_2(v_dout_2),
        .Q_LUTRAM(v_tile_lut), .done(LD_LUTRAM_done_v));

    // =========================================================================
    // Stage 4: systolic multiply  q_tile @ k_tile(.T) -> logit product
    // =========================================================================
    logic [15:0] temp_logit_tile_lut [16][16];
    logic [15:0] logit_tile_lut [16][16];
    

    systolic_array_mult #(.ROWS(16), .COLS(16)) logit_mult (
        .reset(reset), .clk(clk), .start(systolic_mult_start),
        .array_A(q_tile_lut), .array_B(k_tile_lut),
        .c_matrix(temp_logit_tile_lut), .done_out(logit_mult_done));

    // =========================================================================
    // Stage 5: accumulate the product into the running logit tile (over k)
    // =========================================================================
    accumulate_tile_output accumulate_logit_output_inst (
        .clk(clk), .reset(reset), .start(acc_start), .first(k == 17'd0),
        .array_in(temp_logit_tile_lut), .array_out(logit_tile_lut), .done(logit_acc_done));

    // Scaling factor source (unused in the logit-only run; restore with the
    // scaled_logit block below once square_root.sv is in the build).
    // logic[15:0] scaling_factor;
    // logic sqrt_done;
    // square_root #(.dimension(COLS)) sqrt_unit
    //     (.clk(clk), .dim_sqrt(scaling_factor), .done(sqrt_done));

    assign logit_tile_out = logit_tile_lut;
    assign tile_valid     = tile_complete;

    // =========================================================================
    // Stage 6: flash-attention output — scale logits, run softermax per row,
    //          carry (m,d,o) across j.
    // =========================================================================
    // Scale the logit tile by 1/2^SCALE_SHIFT via BF16 exponent subtraction
    // (exact for the /4 power-of-two case; underflow -> signed zero).
    logic [15:0] scaled_logit [16][16];
    // Logit-only test: bypass the 1/sqrt(D) scale (softmax/output path not checked
    // in this run). Restore the square_root + BF16_DIV_Unit scaling below once
    // square_root.sv exists in the build. (Also fixes logit -> logit_tile_lut.)
    // logic[15:0] scaling_factor;
    // square_root #(.dimension(COLS)) sqrt_scaling_unit
    //     (.clk(clk), .dim_sqrt(scaling_factor), .done());
     genvar gen_i, gen_j;
     generate
         for (gen_i = 0; gen_i < 16; gen_i++) begin
             for (gen_j = 0; gen_j < 16; gen_j++) begin
                 BF16_DIV_Unit scaling_div (.A(logit_tile_lut[gen_i][gen_j]),
                     .B(scaling_factor), .C(scaled_logit[gen_i][gen_j]));
             end
         end
     endgenerate
    logic[15:0] scaling_factor;
//    always_comb begin
//        for (int r = 0; r < 16; r++)
//            for (int c = 0; c < 16; c++) begin
//                logic [7:0] e;
//                e = logit_tile_lut[r][c][14:7];
//                if (logit_tile_lut[r][c][14:0] == 15'd0)
//                    scaled_logit[r][c] = logit_tile_lut[r][c];                 // +/-0
//                else if (e <= SCALE_SHIFT[7:0])
//                    scaled_logit[r][c] = {logit_tile_lut[r][c][15], 15'd0};    // underflow -> 0
//                else
//                    scaled_logit[r][c] = {logit_tile_lut[r][c][15],
//                                          e - SCALE_SHIFT[7:0],
//                                          logit_tile_lut[r][c][6:0]};
//            end
//    end

    // Running flash state per query row (carried across j, reset per query block i).
    logic [15:0] m [16];        // running max
    logic [15:0] d [16];        // running sum
    logic [15:0] o [16][16];    // running output
    logic sm_start_sqrt_gated;
    logic sqrt_done;
    

    // softermax I/O (one row per pass).
    logic [3:0]  sm_row;
    logic        sm_start, sm_done, sm_done_d1;
    logic [15:0] sm_m_out, sm_d_out, sm_o_out [16];
    logic [15:0] sm_logits [15:0];      // matches softermax's descending logits port

    assign sm_start_sqrt_gated = sm_start && sqrt_done;

    always_comb
        for (int c = 0; c < 16; c++)
            sm_logits[c] = scaled_logit[sm_row][c];

    logic sm_capture;
    assign sm_capture = sm_done && !sm_done_d1;   // rising edge = pass complete

    softermax softermax_inst (
        .logits(sm_logits), .V_matrix(v_tile_lut), .clk(clk), .Reset(reset),
        .row_idx(sm_row), .scaling_factor(scaling_factor),
        .start(sm_start_sqrt_gated), .m_in(m[sm_row]), .d_in(d[sm_row]), .o_in(o[sm_row]),
        .m_out(sm_m_out), .d_out(sm_d_out), .o_out(sm_o_out),
        .logits_out(), .done(sm_done), .V_out()
    );
    
    square_root #(.dimension(COLS))
    sqrt_scale_inst
    (
        .clk(clk),
        .dim_sqrt(scaling_factor),
        .done(sqrt_done)
    );

    // Row sequencer: pulse start per row, capture on done, advance until row 15.
    always_ff @(posedge clk) begin
        if (reset) begin
            sm_row <= 4'd0; sm_start <= 1'b0; softv_done <= 1'b0; sm_done_d1 <= 1'b1;
        end else begin
            sm_start   <= 1'b0;         // 1-cycle pulse
            softv_done <= 1'b0;
            sm_done_d1 <= sm_done;
            if (entered_softv) begin
                sm_row <= 4'd0; sm_start <= 1'b1;         // launch row 0
            end else if (sm_capture) begin
                if (sm_row == 4'd15) softv_done <= 1'b1;  // last row: flash tile done
                else begin sm_row <= sm_row + 4'd1; sm_start <= 1'b1; end
            end
        end
    end

    // Flash-state registers: seed (-inf,0,0) at a new query block (j==0), else
    // fold in each row's softermax result.
    always_ff @(posedge clk) begin
        if (reset || (entered_softv && (j == 17'd0))) begin
            for (int r = 0; r < 16; r++) begin
                m[r] <= 16'hFF80;  // -inf
                d[r] <= 16'h0000;
                for (int c = 0; c < 16; c++) o[r][c] <= 16'h0000;
            end
        end else if (sm_capture) begin
            m[sm_row] <= sm_m_out;
            d[sm_row] <= sm_d_out;
            for (int c = 0; c < 16; c++) o[sm_row][c] <= sm_o_out[c];
        end
    end

    assign out_tile  = o;
    assign out_valid = softv_done && (j == 17'(ROWS - 1));
    
    
    

endmodule


// ---------------------------------------------------------------------------
// Registered tile accumulator: seed with array_in when `first`, else add.
// ---------------------------------------------------------------------------
module accumulate_tile_output
(
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        first,
    input  logic [15:0] array_in  [16][16],
    output logic [15:0] array_out [16][16],
    output logic        done
);
    logic[15:0] temp_array[16][16];
    
    always_ff @(posedge clk) begin
        if (reset)
            done <= 1'b0;
        else if (start) begin
            for (int r = 0; r < 16; r++)
                for (int c = 0; c < 16; c++)
                    array_out[r][c] <= first ? array_in[r][c]
                                             : temp_array[r][c];
            done <= 1'b1;
        end
        else
            done <= 1'b0;
    end
    
    generate 
        for (genvar r = 0; r < 16; r++)
                for (genvar c = 0; c < 16; c++)
                    BF16_Add_Unit acc_adder_unit(.A(array_in[r][c]), .B(array_out[r][c]), .C(temp_array[r][c]));
    endgenerate 
                   
    
    
endmodule
