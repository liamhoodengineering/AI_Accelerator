`timescale 1ns / 1ps

module b_grid_tb(
    );

    localparam int ROWS   = 16;
    localparam int COLS   = 16;
    localparam int SKEW_W = ROWS + COLS - 1;   // 31

    logic        clk;
    logic        reset;
    logic [15:0] array_A   [ROWS][COLS];
    logic [15:0] array_B   [ROWS][COLS];
    logic [15:0] c_matrix  [ROWS][COLS];
    int          errors;

    systolic_array_mult dut(
        .clk(clk),
        .reset(reset),
        .array_A(array_A),
        .array_B(array_B),
        .c_matrix(c_matrix));

    always #5 clk = ~clk;

    // Snapshots of prior-cycle values for cross-cycle comparison.
    logic [15:0] b_grid_prev      [ROWS][COLS];
    logic [15:0] array_B_out_prev [SKEW_W][COLS];
    logic [5:0]  col_ptr_prev;
    logic        reset_prev;

    always @(posedge clk) begin
        b_grid_prev      <= dut.b_grid;
        array_B_out_prev <= dut.array_B_out;
        col_ptr_prev     <= dut.col_ptr;
        reset_prev       <= reset;
    end

    initial begin
        clk    = 1'b0;
        reset  = 1'b1;
        errors = 0;

        // All-1.0 BF16 on both input matrices. array_A isn't needed for the
        // b_grid checks but must be driven to keep BF16_pe_unit from
        // propagating X back into the design.
        for (int i = 0; i < ROWS; i++) begin
            for (int j = 0; j < COLS; j++) begin
                array_A[i][j] = 16'h3F80;
                array_B[i][j] = 16'h3F80;
            end
        end

        @(negedge clk); reset = 1'b1;
        @(negedge clk); reset = 1'b0;

        // Walk 40 cycles -- enough to cover the full 0..30 col_ptr sweep plus
        // some margin past saturation.
        for (int cyc = 0; cyc < 40; cyc++) begin
            @(posedge clk); #1;

            // The first cycle after reset deassert has no usable prior sample
            // (reset_prev still high). Skip its checks.
            if (reset_prev) continue;

            // Top-edge: b_grid[0][j] should reflect the previous cycle's
            // array_B_out[col_ptr][j].
            for (int j = 0; j < COLS; j++) begin
                if (dut.b_grid[0][j] !== array_B_out_prev[col_ptr_prev][j]) begin
                    $display("FAIL cyc=%0d edge j=%0d b_grid[0][%0d]=%h exp=%h (array_B_out_prev[%0d][%0d])",
                             cyc, j, j, dut.b_grid[0][j],
                             array_B_out_prev[col_ptr_prev][j], col_ptr_prev, j);
                    errors++;
                end
            end

            // Shift propagation: b_grid[i>0][j] should reflect the previous
            // cycle's b_grid[i-1][j].
            for (int i = 1; i < ROWS; i++) begin
                for (int j = 0; j < COLS; j++) begin
                    if (dut.b_grid[i][j] !== b_grid_prev[i-1][j]) begin
                        $display("FAIL cyc=%0d shift i=%0d j=%0d b_grid[%0d][%0d]=%h exp=%h (b_grid_prev[%0d][%0d])",
                                 cyc, i, j, i, j, dut.b_grid[i][j],
                                 b_grid_prev[i-1][j], i-1, j);
                        errors++;
                    end
                end
            end
        end

        if (errors == 0)
            $display("==== PASS: b_grid top-edge + shift correctness over 40 cycles ====");
        else
            $display("==== FAIL: %0d b_grid mismatches ====", errors);

        $finish;
    end

endmodule
