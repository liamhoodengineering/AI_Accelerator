`timescale 1ns / 1ps

module a_grid_tb(
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
    logic [15:0] a_grid_prev      [ROWS][COLS];
    logic [15:0] array_A_out_prev [ROWS][SKEW_W];
    logic [5:0]  col_ptr_prev;
    logic        reset_prev;

    always @(posedge clk) begin
        a_grid_prev      <= dut.a_grid;
        array_A_out_prev <= dut.array_A_out;
        col_ptr_prev     <= dut.col_ptr;
        reset_prev       <= reset;
    end

    initial begin
        clk    = 1'b0;
        reset  = 1'b1;
        errors = 0;

        // All-1.0 BF16 on both input matrices. array_B isn't needed for the
        // a_grid checks but must be driven to keep BF16_pe_unit from
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

            // Left-edge: a_grid[i][0] should reflect the previous cycle's
            // array_A_out[i][col_ptr].
            for (int i = 0; i < ROWS; i++) begin
                if (dut.a_grid[i][0] !== array_A_out_prev[i][col_ptr_prev]) begin
                    $display("FAIL cyc=%0d edge i=%0d a_grid[%0d][0]=%h exp=%h (array_A_out_prev[%0d][%0d])",
                             cyc, i, i, dut.a_grid[i][0],
                             array_A_out_prev[i][col_ptr_prev], i, col_ptr_prev);
                    errors++;
                end
            end

            // Shift propagation: a_grid[i][j>0] should reflect the previous
            // cycle's a_grid[i][j-1].
            for (int i = 0; i < ROWS; i++) begin
                for (int j = 1; j < COLS; j++) begin
                    if (dut.a_grid[i][j] !== a_grid_prev[i][j-1]) begin
                        $display("FAIL cyc=%0d shift i=%0d j=%0d a_grid[%0d][%0d]=%h exp=%h (a_grid_prev[%0d][%0d])",
                                 cyc, i, j, i, j, dut.a_grid[i][j],
                                 a_grid_prev[i][j-1], i, j-1);
                        errors++;
                    end
                end
            end
        end

        if (errors == 0)
            $display("==== PASS: a_grid left-edge + shift correctness over 40 cycles ====");
        else
            $display("==== FAIL: %0d a_grid mismatches ====", errors);

        $finish;
    end

endmodule
