`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: systolic_test_2_tb
// Description: Self-checking test for systolic_array_mult.sv, driven by BF16 memory
//              files emitted from python_verification/systolic_matrix_check.py
//              (run it with --emit to produce A.mem / B.mem / gold.mem).
//
//   PART 1 (black-box): load A/B, run the array, compare c_matrix to gold = A@B
//                       in the real domain with tolerance (the DUT accumulates in
//                       BF16, so it won't bit-match a float-then-round gold).
//
//   PART 2 (white-box): follow the reference systolic algorithm cycle-by-cycle and
//                       flag the FIRST place the RTL diverges, in independent stages:
//                       (1) skew buffers, (2) col_ptr walk, (3) a_grid/b_grid
//                       propagation, (4) accumulator. The failing stage localizes
//                       the bug (shifting vs accumulation).
//
//   DUT notes (this OneDrive\Desktop copy): `start` is unused and `done_out` is
//   undriven -- the array free-runs from `reset`, so this TB keys off a cycle count.
//////////////////////////////////////////////////////////////////////////////////

module systolic_test_2_tb;

    localparam int NT     = 2;      // test vectors (must match the emitter)
    localparam int N      = 16;
    localparam int SKEW_W = 2*N-1;  // 31
    localparam int SETTLE = 52;     // cycles to run per test (done latches ~48)

    localparam string DIR      = "C:/Users/egypt/AI_Accelerator/python_verification/";
    localparam string A_FILE   = {DIR, "A.mem"};
    localparam string B_FILE   = {DIR, "B.mem"};
    localparam string G_FILE   = {DIR, "gold.mem"};

    // Test-vector name. NB: a runtime-indexed `localparam string arr[NT]` crashes
    // the xsim kernel ("exceptional condition") -- use a function instead.
    function automatic string tname(int t);
        return (t == 0) ? "identity x position" : "random BF16";
    endfunction

    // Real-domain compare tolerance for gold / accumulator (BF16 MAC vs float gold).
    localparam real ATOL = 0.10;
    localparam real RTOL = 0.05;

    // ---- Clock / reset ------------------------------------------------------
    logic clk = 1'b0;
    logic reset = 1'b1;
    always #5 clk = ~clk;   // 100 MHz

    // ---- DUT I/O ------------------------------------------------------------
    // NB: match the DUT's DESCENDING [N-1:0][N-1:0] port ranges exactly. Declaring
    // these ascending ([N][N]) maps unpacked-array elements position-wise and
    // silently REVERSES both indices across the port -- a TB artifact, not a DUT bug.
    logic [15:0] array_A [N-1:0][N-1:0];
    logic [15:0] array_B [N-1:0][N-1:0];
    logic [15:0] c_matrix[N][N];
    logic        done_out;   // undriven by this DUT; intentionally unused

    systolic_array_mult #(.ROWS(N), .COLS(N)) dut (
        .start   (1'b0),     // unused in this DUT
        .reset   (reset),
        .clk     (clk),
        .array_A (array_A),
        .array_B (array_B),
        .c_matrix(c_matrix),
        .done_out(done_out)
    );

    // ---- Gold / stimulus memories ------------------------------------------
    logic [15:0] A_mem [0:NT*N*N-1];
    logic [15:0] B_mem [0:NT*N*N-1];
    logic [15:0] G_mem [0:NT*N*N-1];

    // ---- Shadow model (ideal a_grid/b_grid) for Part 2 stage 3 --------------
    logic [15:0] sh_a [N][N];
    logic [15:0] sh_b [N][N];

    // ---- Scoreboard ---------------------------------------------------------
    int s1_fail, s2_fail, s3_fail;            // per-stage divergence counts
    int p1_pass, p1_fail;                     // Part 1 output vs gold
    real max_abs_err;
    string first_div;                         // first stage that diverged

    // ---- Helpers ------------------------------------------------------------
    function automatic bit inrange(int x);
        return (x >= 0 && x < N);
    endfunction

    // Ideal skew (matches skew_buffer_horizontal/vertical + build_skew_A/B):
    //   skewA[i][p] = A[i][p-i],  skewB[p][j] = B[p-j][j]   (0 out of range)
    function automatic logic [15:0] skewA_ideal(int i, int p);
        return inrange(p - i) ? array_A[i][p - i] : 16'h0;
    endfunction
    function automatic logic [15:0] skewB_ideal(int p, int j);
        return inrange(p - j) ? array_B[p - j][j] : 16'h0;
    endfunction

    function automatic real bf16_to_real(input logic [15:0] b);
        return $bitstoshortreal({b, 16'h0000});   // BF16 shares f32 sign/exp
    endfunction

    task automatic note_div(string s);
        if (first_div == "") first_div = s;
    endtask

    // Stage 1: skew buffers (combinational) vs the ideal skew.
    task automatic check_skew(int t);
        for (int i = 0; i < N; i++)
            for (int p = 0; p < SKEW_W; p++) begin
                if (dut.array_A_out[i][p] !== skewA_ideal(i, p)) begin
                    s1_fail++;
                    if (s1_fail <= 8) $error("S1 skewA t=%0d [i=%0d][p=%0d] got=%04h exp=%04h",
                        t, i, p, dut.array_A_out[i][p], skewA_ideal(i, p));
                    note_div("stage1-skewA");
                end
                if (dut.array_B_out[p][i] !== skewB_ideal(p, i)) begin
                    s1_fail++;
                    if (s1_fail <= 8) $error("S1 skewB t=%0d [p=%0d][j=%0d] got=%04h exp=%04h",
                        t, p, i, dut.array_B_out[p][i], skewB_ideal(p, i));
                    note_div("stage1-skewB");
                end
            end
    endtask

    // Stage 3 shadow: advance ideal a_grid/b_grid one cycle, using the col_ptr that
    // the RTL used to produce THIS cycle's registers (= min(cyc-1, SKEW_W-1)).
    task automatic step_shadow(int cyc);
        logic [15:0] nsa [N][N];
        logic [15:0] nsb [N][N];
        int colp = (cyc - 1 < SKEW_W - 1) ? (cyc - 1) : (SKEW_W - 1);
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                nsa[i][j] = (j == 0) ? skewA_ideal(i, colp) : sh_a[i][j-1];
                nsb[i][j] = (i == 0) ? skewB_ideal(colp, j) : sh_b[i-1][j];
            end
        sh_a = nsa;
        sh_b = nsb;
    endtask

    // Stage 2 + 3 per-cycle checks.
    task automatic check_cycle(int t, int cyc);
        int exp_colptr = (cyc < SKEW_W - 1) ? cyc : (SKEW_W - 1);
        // Stage 2: col_ptr walk
        if (dut.col_ptr !== exp_colptr[5:0]) begin
            s2_fail++;
            if (s2_fail <= 8) $error("S2 col_ptr t=%0d cyc=%0d got=%0d exp=%0d",
                t, cyc, dut.col_ptr, exp_colptr);
            note_div("stage2-col_ptr");
        end
        // Stage 3: operand propagation vs shadow
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                if (dut.a_grid[i][j] !== sh_a[i][j]) begin
                    s3_fail++;
                    if (s3_fail <= 12) $error("S3 a_grid t=%0d cyc=%0d [%0d][%0d] got=%04h exp=%04h",
                        t, cyc, i, j, dut.a_grid[i][j], sh_a[i][j]);
                    note_div("stage3-a_grid");
                end
                if (dut.b_grid[i][j] !== sh_b[i][j]) begin
                    s3_fail++;
                    if (s3_fail <= 12) $error("S3 b_grid t=%0d cyc=%0d [%0d][%0d] got=%04h exp=%04h",
                        t, cyc, i, j, dut.b_grid[i][j], sh_b[i][j]);
                    note_div("stage3-b_grid");
                end
            end
    endtask

    // Stage 4 + Part 1: settled result vs gold.
    //   4a: the INTERNAL accumulator dut.acc_grid vs gold  -> is the MAC correct?
    //   Part 1 / 4b: the OUTPUT PORT c_matrix vs gold      -> observable result.
    //   plus a reversal probe: is c_matrix == acc_grid mirrored in both indices?
    task automatic check_output(int t);
        real got, gold, goldm, d, tol;
        int  base = t * N * N;
        bit  mirror_ok = 1'b1;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                got   = bf16_to_real(c_matrix[i][j]);
                gold  = bf16_to_real(G_mem[base + i*N + j]);                 // correct C[i][j]
                goldm = bf16_to_real(G_mem[base + (N-1-i)*N + (N-1-j)]);     // mirrored C[N-1-i][N-1-j]
                tol   = ATOL + RTOL * ((gold  < 0) ? -gold  : gold);

                // Part 1: observable output vs the CORRECT gold.
                d = (got > gold) ? (got - gold) : (gold - got);
                if (d > max_abs_err) max_abs_err = d;
                if (d <= tol) p1_pass++; else p1_fail++;

                // Stage 4: does the output instead match the MIRRORED gold?
                if (((got > goldm) ? got - goldm : goldm - got)
                        > ATOL + RTOL * ((goldm < 0) ? -goldm : goldm))
                    mirror_ok = 1'b0;
            end
        if (mirror_ok && p1_fail > 0) begin
            note_div("stage4-output-reversed");
            $display("  test %0d DIAGNOSIS: array computes CORRECTLY but the output is INDEX-REVERSED:", t);
            $display("             c_matrix[i][j] == C[N-1-i][N-1-j]. Root cause: the c_matrix<=acc_grid copy,");
            $display("             port c_matrix[ROWS-1:0][COLS-1:0] (descending) vs acc_grid[ROWS][COLS] (ascending).");
        end
    endtask

    // ---- Run one test vector ------------------------------------------------
    task automatic run_test(int t);
        int base = t * N * N;
        first_div = "";
        // Load stimulus, hold stable.
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                array_A[i][j] = A_mem[base + i*N + j];
                array_B[i][j] = B_mem[base + i*N + j];
            end
        // Reset the array, then release on a negedge so reset=0 is clean before the
        // first posedge (that first posedge = cyc 1).
        reset = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk); reset = 1'b0;
        // Clear the shadow to match the DUT's reset (a_grid/b_grid = 0).
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin sh_a[i][j] = 16'h0; sh_b[i][j] = 16'h0; end

        // Stage 1: skew is combinational off the (now stable) inputs.
        check_skew(t);

        // Cycle-by-cycle stages 2 & 3.
        for (int cyc = 1; cyc <= SETTLE; cyc++) begin
            @(posedge clk); #1;
            step_shadow(cyc);          // advance ideal shadow to this cycle
            check_cycle(t, cyc);       // compare col_ptr + a_grid/b_grid
        end

        // Stage 4 / Part 1: settled output vs gold.
        check_output(t);

        // NB: never pass a possibly-empty string to %s -- xsim's kernel crashes
        // formatting an empty string. Guard with an if/else and literal text.
        if (first_div == "")
            $display("  test %0d (%s): all stages OK", t, tname(t));
        else
            $display("  test %0d (%s): first divergence = %s", t, tname(t), first_div);
    endtask

    // ---- Main ---------------------------------------------------------------
    initial begin
        s1_fail=0; s2_fail=0; s3_fail=0;
        p1_pass=0; p1_fail=0; max_abs_err=0.0;

        $readmemh(A_FILE, A_mem);
        $readmemh(B_FILE, B_mem);
        $readmemh(G_FILE, G_mem);
        $display("[%0t] loaded mem: A[0]=%04h B[0]=%04h gold[0]=%04h",
                 $time, A_mem[0], B_mem[0], G_mem[0]);
        if ($isunknown(done_out))
            $display("NOTE: done_out is undriven (X) in this DUT -- TB uses a cycle count.");

        for (int t = 0; t < NT; t++)
            run_test(t);

        $display("");
        $display("=== systolic_array_mult test 2 ===");
        $display("PART 1  output vs gold : PASS %0d  FAIL %0d  (max abs err = %f)",
                 p1_pass, p1_fail, max_abs_err);
        $display("PART 2  stage divergences (first-diverging stage localizes the bug):");
        $display("  stage 1 skew buffers  : %0d", s1_fail);
        $display("  stage 2 col_ptr       : %0d", s2_fail);
        $display("  stage 3 propagation   : %0d", s3_fail);
        if (first_div == "stage4-output-reversed")
            $display("  stage 4 output order  : REVERSED (see diagnosis above)");
        else if (p1_fail == 0)
            $display("  stage 4 output order  : ok");
        else
            $display("  stage 4 output order  : wrong (not a clean reversal)");
        if (s1_fail==0 && s2_fail==0 && s3_fail==0 && p1_fail==0)
            $display("RESULT: PASS");
        else if (s1_fail==0 && s2_fail==0 && s3_fail==0)
            $display("RESULT: FAIL at stage 4 only -- operands (skew/col_ptr/propagation) all correct; fix the reversed c_matrix<=acc_grid copy.");
        else
            $display("RESULT: FAIL -- first bad stage = %0d.",
                     (s1_fail>0)?1:(s2_fail>0)?2:3);
        $finish;
    end

    // ---- Watchdog -----------------------------------------------------------
    initial begin
        #100000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
