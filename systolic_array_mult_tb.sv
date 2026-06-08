`timescale 1ns / 1ps

module systolic_array_mult_tb(
    );

    logic        clk;
    logic        reset;
    logic [15:0] array_A  [16][16];
    logic [15:0] array_B  [16][16];
    logic [15:0] c_matrix [16][16];
    logic [15:0] expected [16][16];
    int          errors;

    systolic_array_mult dut(
        .clk(clk),
        .reset(reset),
        .array_A(array_A),
        .array_B(array_B),
        .c_matrix(c_matrix));

    always #5 clk = ~clk;

    initial begin
        clk    = 1'b0;
        reset  = 1'b0;
        errors = 0;

        // All-1.0 x all-1.0  -> every C[i][j] = sum of 16 (1*1) = 16.0
        for (int i = 0; i < 16; i++) begin
            for (int j = 0; j < 16; j++) begin
                array_A[i][j]  = 16'h3F80;   // BF16 1.0
                array_B[i][j]  = 16'h3F80;   // BF16 1.0
                expected[i][j] = 16'h4180;   // BF16 16.0
            end
        end

        @(negedge clk); reset = 1'b1;
        @(negedge clk); reset = 1'b0;

        // Wait for skew + grid fill + K accumulation + final c_matrix latch.
        repeat (50) @(posedge clk);

        for (int i = 0; i < 16; i++) begin
            for (int j = 0; j < 16; j++) begin
                if (c_matrix[i][j] !== expected[i][j]) begin
                    $display("MISMATCH c_matrix[%0d][%0d]: got %h, expected %h",
                             i, j, c_matrix[i][j], expected[i][j]);
                    errors++;
                end
            end
        end

        // Spot-check dump of row 0
        $display("c_matrix[0] = %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                 c_matrix[0][0],  c_matrix[0][1],  c_matrix[0][2],  c_matrix[0][3],
                 c_matrix[0][4],  c_matrix[0][5],  c_matrix[0][6],  c_matrix[0][7],
                 c_matrix[0][8],  c_matrix[0][9],  c_matrix[0][10], c_matrix[0][11],
                 c_matrix[0][12], c_matrix[0][13], c_matrix[0][14], c_matrix[0][15]);

        if (errors == 0)
            $display("==== PASS: c_matrix matches expected (all 16.0) ====");
        else
            $display("==== FAIL: %0d mismatches ====", errors);

        $finish;
    end

endmodule
