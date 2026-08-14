`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: fsm_tiling_tb
// Description: Self-checking testbench for the tiled QK^T datapath (FSM_tiling),
//              run at SHRUNKEN dimensions against the fast behavioral HBM model.
//
//   Compile with +define+SIM_FAST_HBM so HBM_to_BRAM uses the 1-cycle behavioral
//   memory (no ~43.8us calibration, no page bug). The two HBM images are loaded
//   by the DUT itself via the Q_MEM_FILE/K_MEM_FILE params ($readmemh inside the
//   behavioral model). Gold QK^T tiles come from
//   python_verification/dot_product_attention.py --emit.
//
//   Two orthogonal checks (both dimension-independent, so small proves large):
//     * SCHEDULE/ADDRESS : independently reproduces the (i,j,k) tile schedule and
//       cross-checks the DUT counters + block addresses on every accumulate.
//     * DATA (CHECK_DATA) : on each tile_valid, compares logit_tile_out to the
//       BF16 gold for (i,j) with a tolerance (BF16 MAC vs float32 reference).
//
//   Reconfigure via xelab --generic_top for the address-gen scaling run, e.g.
//     ROWS_TB=4 COLS_TB=4 CHECK_DATA=0  (exhaustive 64-tile schedule check).
//////////////////////////////////////////////////////////////////////////////////

module fsm_tiling_tb;
    // Config: default = functional data run (2x1, exact single-k QK^T check).
    // Compile with -d ADDR_SCALING for the exhaustive 4x4 schedule/address run.
`ifdef ADDR_SCALING
    localparam int ROWS_TB    = 16;
    localparam int COLS_TB    = 8;
    localparam bit CHECK_DATA = 1'b0;
`else
    localparam int ROWS_TB    = 16;   // N=256 / 16
    localparam int COLS_TB    = 8;    // D=128 / 16
    localparam bit CHECK_DATA = 1'b1;
`endif
    // Flash OUTPUT check: compares out_tile (16 query rows x 16 features = V feature
    // block 0) against gold_vout.mem. The DUT is un-scaled (square_root=1, softermax
    // scaling_factor unused), so the gold must be un-scaled softmax(Q@K^T) @ V[:,0:16].
    localparam bit CHECK_OUT = 1'b1;

    localparam string DIR       = "C:/Users/egypt/AI_Accelerator/python_verification/";
    localparam string Q_FILE    = {DIR, "q_hbm.mem"};
    localparam string K_FILE    = {DIR, "k_hbm.mem"};
    localparam string V_FILE    = {DIR, "v_hbm.mem"};
    localparam string GOLD_FILE   = {DIR, "logit_gold.mem"};
    localparam string SCORES_FILE = {DIR, "scores_gold.mem"};
    localparam string OUT_FILE    = {DIR, "gold_vout.mem"};

    // Logit tolerance: BF16 systolic MAC (DUT) vs float32 reference. At D=128 the
    // logits are ~±15 and accumulate over 8 BF16 tiles, so the abs floor is larger.
    localparam real ATOL = 0.75;
    localparam real RTOL = 0.05;
    // Output tolerance: looser — softermax uses base-2, a Horner 2^-f fit, and a
    // truncating divider (see verify_flash_v.py residual error).
    localparam real OATOL = 0.05;
    localparam real ORTOL = 0.15;

    // ---- Clock / reset ------------------------------------------------------
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT outputs --------------------------------------------------------
    logic [15:0] logit_out [16][16];
    logic        tile_valid;
    logic [15:0] out_tile  [16][16];
    logic        out_valid;
    logic        busy;

    FSM_tiling #(
        .ROWS       (ROWS_TB),
        .COLS       (COLS_TB),
        .Q_MEM_FILE (Q_FILE),
        .K_MEM_FILE (K_FILE),
        .V_MEM_FILE (V_FILE)
    ) dut (
        .start          (start),
        .reset          (reset),
        .clk            (clk),
        .logit_tile_out (logit_out),
        .tile_valid     (tile_valid),
        .out_tile       (out_tile),
        .out_valid      (out_valid),
        .busy           (busy)
    );

    // ---- Gold + scoreboard --------------------------------------------------
    logic [15:0] gold_mem   [0:ROWS_TB*ROWS_TB*256-1]; // 256 = 16x16 words per logit tile
    logic [15:0] scores_mem [0:ROWS_TB*ROWS_TB*256-1]; // full-matmul QK^T gold (scores_bf)
    logic [15:0] out_gold [0:ROWS_TB*16*16-1];         // flash output: 16 rows x 16 feats per block
    int sched_pass,  sched_fail;
    int addr_pass,   addr_fail;
    int data_pass,   data_fail;
    int scores_pass, scores_fail;
    int out_pass,    out_fail;
    int tiles_seen, out_blks;
    real max_abs_diff, max_scores_diff, max_out_err;

    // Expected tile schedule (independent reconstruction of the nested counters).
    int ei, ej, ek;

    function automatic real bf16_to_real(input logic [15:0] b);
        // BF16 shares float32's sign/exponent; zero-extend the mantissa to 32b.
        return $bitstoshortreal({b, 16'h0000});
    endfunction

    // ---- Per-accumulate checker (schedule + address + optional data) --------
    always @(posedge clk) begin
        if (!reset && dut.logit_acc_done) begin
            // 1) DUT counters must match the independently-tracked schedule.
            if (dut.i === ei && dut.j === ej && dut.k === ek) sched_pass++;
            else begin
                sched_fail++;
                $error("[%0t] SCHED got (i,j,k)=(%0d,%0d,%0d) exp (%0d,%0d,%0d)",
                       $time, dut.i, dut.j, dut.k, ei, ej, ek);
            end

            // 2) Block addresses = {row[8:0], col[7:0]} = (row<<8)+k.
            if (dut.block_addr_q === (17'(ei) << 8) + 17'(ek) &&
                dut.block_addr_k === (17'(ej) << 8) + 17'(ek)) addr_pass++;
            else begin
                addr_fail++;
                $error("[%0t] ADDR q=%05h k=%05h  exp q=%05h k=%05h",
                       $time, dut.block_addr_q, dut.block_addr_k,
                       (ei << 8) + ek, (ej << 8) + ek);
            end

            // 3) tile_valid must strobe only on the last contraction tile.
            if (tile_valid !== (dut.k === 17'(COLS_TB - 1)))
                $error("[%0t] tile_valid=%b but k=%0d (COLS-1=%0d)",
                       $time, tile_valid, dut.k, COLS_TB - 1);

            // 4) Data check on a completed (i,j) tile.
            if (CHECK_DATA && tile_valid) begin
                automatic int base = (ei * ROWS_TB + ej) * 256;   // 256 words per logit tile
                for (int r = 0; r < 16; r++)
                    for (int c = 0; c < 16; c++) begin
                        automatic real a_r = bf16_to_real(logit_out[r][c]);
                        automatic real g_r = bf16_to_real(gold_mem[base + r*16 + c]);
                        automatic real d   = (a_r > g_r) ? (a_r - g_r) : (g_r - a_r);
                        automatic real tol = ATOL + RTOL * ((g_r < 0) ? -g_r : g_r);
                        // Second, independent gold: scores_bf (single full-precision matmul).
                        automatic real s_r  = bf16_to_real(scores_mem[base + r*16 + c]);
                        automatic real sd   = (a_r > s_r) ? (a_r - s_r) : (s_r - a_r);
                        automatic real stol = ATOL + RTOL * ((s_r < 0) ? -s_r : s_r);
                        if (d > max_abs_diff) max_abs_diff = d;
                        if (d <= tol) data_pass++;
                        else begin
                            data_fail++;
                            if (data_fail <= 20)
                                $error("[%0t] DATA (i,j,r,c)=(%0d,%0d,%0d,%0d) got=%f gold=%f d=%f",
                                       $time, ei, ej, r, c, a_r, g_r, d);
                        end
                        if (sd > max_scores_diff) max_scores_diff = sd;
                        if (sd <= stol) scores_pass++;
                        else begin
                            scores_fail++;
                            if (scores_fail <= 20)
                                $error("[%0t] SCORES (i,j,r,c)=(%0d,%0d,%0d,%0d) got=%f gold=%f d=%f",
                                       $time, ei, ej, r, c, a_r, s_r, sd);
                        end
                    end
            end

            if (tile_valid) tiles_seen++;

            // 5) Advance the expected schedule (k -> j -> i).
            if (ek == COLS_TB - 1) begin
                ek = 0;
                if (ej == ROWS_TB - 1) begin
                    ej = 0;
                    ei = (ei == ROWS_TB - 1) ? 0 : ei + 1;
                end else ej++;
            end else ek++;
        end
    end

    // ---- Flash-attention output check (one out_tile per query block i) ------
    // out_tile = 16 query rows x 16 features (V feature block 0). gold_vout.mem is
    // row-major over global query rows, 16 features each -> block out_blks(=i) row r
    // feature c maps to gold row (16*out_blks + r) -> index out_blks*16*16 + r*16 + c.
    always @(posedge clk) begin
        if (!reset && CHECK_OUT && out_valid) begin
            automatic int obase = out_blks * 16 * 16;  // 16 features per query row
            for (int r = 0; r < 16; r++)
                for (int c = 0; c < 16; c++) begin
                    automatic real a_r = bf16_to_real(out_tile[r][c]);
                    automatic real g_r = bf16_to_real(out_gold[obase + r*16 + c]);
                    automatic real d   = (a_r > g_r) ? (a_r - g_r) : (g_r - a_r);
                    automatic real tol = OATOL + ORTOL * ((g_r < 0) ? -g_r : g_r);
                    if (d > max_out_err) max_out_err = d;
                    if (d <= tol) out_pass++;
                    else begin
                        out_fail++;
                        if (out_fail <= 20)
                            $error("[%0t] OUT (blk,r,c)=(%0d,%0d,%0d) got=%f gold=%f d=%f",
                                   $time, out_blks, r, c, a_r, g_r, d);
                    end
                end
            out_blks++;
        end
    end

    // ---- Main ---------------------------------------------------------------
    initial begin
        sched_pass=0;  sched_fail=0; addr_pass=0; addr_fail=0;
        data_pass=0;   data_fail=0;  tiles_seen=0; max_abs_diff=0.0;
        scores_pass=0; scores_fail=0; max_scores_diff=0.0;
        out_pass=0;    out_fail=0;   out_blks=0;   max_out_err=0.0;
        ei=0; ej=0; ek=0;

        if (CHECK_DATA)  $readmemh(GOLD_FILE,   gold_mem);
        if (CHECK_DATA)  $readmemh(SCORES_FILE, scores_mem);
        if (CHECK_OUT)   $readmemh(OUT_FILE,    out_gold);
        if (CHECK_DATA)  $display("[%0t] loaded logit gold: gold[0]=%04h scores[0]=%04h",
                                  $time, gold_mem[0], scores_mem[0]);

        repeat (4) @(posedge clk);
        reset <= 1'b0;
        @(posedge clk);

        // 1-cycle start pulse launches the whole (shrunken) matrix.
        start <= 1'b1; @(posedge clk); start <= 1'b0;

        // Wait until every logit tile has completed (+ output blocks if checked).
        wait (tiles_seen == ROWS_TB * ROWS_TB &&
              (!CHECK_OUT || out_blks == ROWS_TB));
        repeat (4) @(posedge clk);

        $display("");
        $display("=== FSM_tiling tiled QK^T test  (ROWS=%0d COLS=%0d, D=%0d) ===",
                 ROWS_TB, COLS_TB, COLS_TB*16);
        $display("Schedule : PASS %0d  FAIL %0d", sched_pass, sched_fail);
        $display("Addresses: PASS %0d  FAIL %0d", addr_pass, addr_fail);
        if (CHECK_DATA) begin
            $display("Logit data : PASS %0d  FAIL %0d  (max |diff| = %f)",
                     data_pass, data_fail, max_abs_diff);
            $display("Scores data: PASS %0d  FAIL %0d  (max |diff| = %f)",
                     scores_pass, scores_fail, max_scores_diff);
        end else
            $display("Logit data : SKIPPED (schedule/address scaling run)");
        if (CHECK_OUT)
            $display("Output data: PASS %0d  FAIL %0d  (max |diff| = %f)",
                     out_pass, out_fail, max_out_err);
        else
            $display("Output data: SKIPPED (CHECK_OUT=0)");

        if (sched_fail==0 && addr_fail==0 && (!CHECK_DATA || data_fail==0)
                                          && (!CHECK_DATA || scores_fail==0)
                                          && (!CHECK_OUT  || out_fail==0))
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

    // ---- Watchdog -----------------------------------------------------------
    initial begin
        #20000000;   // 20 ms: the 256-tile D=128 run is ~2.7 ms of sim time
        $error("TIMEOUT: testbench did not finish (tiles_seen=%0d)", tiles_seen);
        $finish;
    end

endmodule
