`timescale 1ns / 1ps

module skew_buffer_vertical_tb(
    );

    localparam int ROWS   = 16;
    localparam int COLS   = 16;
    localparam int DATA_W = 16;
    localparam int OUT_R  = ROWS + COLS - 1;   // 31

    logic                clk;
    logic                reset;
    logic [DATA_W-1:0]   in_data      [ROWS][COLS];
    logic [DATA_W-1:0]   out_data     [OUT_R][COLS];
    logic [DATA_W-1:0]   expected_out [OUT_R][COLS];
    int                  errors;

    skew_buffer_vertical #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .reset(reset),
        .in_data(in_data),
        .out_data(out_data));

    always #5 clk = ~clk;

    initial begin
        clk    = 1'b0;
        reset  = 1'b1;
        errors = 0;

        // Populate input with a deterministic non-zero pattern: 1..256.
        for (int i = 0; i < ROWS; i++) begin
            for (int j = 0; j < COLS; j++) begin
                in_data[i][j] = DATA_W'(i * COLS + j + 1);
            end
        end

        // Golden output: column j shifted down by (COLS-1-j), zeros elsewhere.
        for (int j = 0; j < COLS; j++) begin
            int shift;
            shift = COLS - 1 - j;
            for (int r = 0; r < OUT_R; r++) begin
                if (r >= shift && r < shift + ROWS)
                    expected_out[r][j] = in_data[r - shift][j];
                else
                    expected_out[r][j] = '0;
            end
        end

        @(negedge clk); reset = 1'b1;
        @(negedge clk); reset = 1'b0;

        // One rising edge to latch matrix_tmp, then settle.
        @(posedge clk); #1;

        for (int r = 0; r < OUT_R; r++) begin
            for (int j = 0; j < COLS; j++) begin
                if (out_data[r][j] !== expected_out[r][j]) begin
                    $display("FAIL row=%0d col=%0d got=%0d exp=%0d",
                             r, j, out_data[r][j], expected_out[r][j]);
                    errors++;
                end
            end
        end

        // Reset sanity check.
        @(negedge clk); reset = 1'b1;
        @(negedge clk); reset = 1'b0;
        #1;
        for (int r = 0; r < OUT_R; r++) begin
            for (int j = 0; j < COLS; j++) begin
                if (out_data[r][j] !== '0) begin
                    $display("FAIL reset row=%0d col=%0d got=%0d exp=0",
                             r, j, out_data[r][j]);
                    errors++;
                end
            end
        end

        if (errors == 0)
            $display("==== PASS: skew_buffer_vertical ROWS=%0d COLS=%0d matches expected skew layout ====",
                     ROWS, COLS);
        else
            $display("==== FAIL: %0d skew_buffer_vertical mismatches ====", errors);

        $finish;
    end

endmodule
