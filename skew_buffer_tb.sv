`timescale 1ns / 1ps

module skew_buffer_tb(
    );

    localparam int ROWS   = 16;
    localparam int COLS   = 16;
    localparam int DATA_W = 16;
    localparam int OUT_C  = COLS + ROWS - 1;   // 31

    logic                clk;
    logic                reset;
    logic [DATA_W-1:0]   in_data      [ROWS][COLS];
    logic [DATA_W-1:0]   out_data     [ROWS][OUT_C];
    logic [DATA_W-1:0]   expected_out [ROWS][OUT_C];
    int                  errors;

    skew_buffer_horizontal #(
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

        // Compute golden output: row i shifted right by i, zeros elsewhere.
        // (Canonical output-stationary skew: row 0 has no delay, row ROWS-1
        // is delayed by ROWS-1 cycles -- matches skew_buffer_horizontal's
        // out_data[i][j+i] = in_data[i][j].)
        for (int i = 0; i < ROWS; i++) begin
            int shift;
            shift = i;
            for (int k = 0; k < OUT_C; k++) begin
                if (k >= shift && k < shift + COLS)
                    expected_out[i][k] = in_data[i][k - shift];
                else
                    expected_out[i][k] = '0;
            end
        end

        @(negedge clk); reset = 1'b1;
        @(negedge clk); reset = 1'b0;

        // One rising edge to latch matrix_tmp from in_data, then settle.
        @(posedge clk); #1;

        for (int i = 0; i < ROWS; i++) begin
            for (int k = 0; k < OUT_C; k++) begin
                if (out_data[i][k] !== expected_out[i][k]) begin
                    $display("FAIL row=%0d col=%0d got=%0d exp=%0d",
                             i, k, out_data[i][k], expected_out[i][k]);
                    errors++;
                end
            end
        end

        // Zero-input sanity check: the DUT is combinational, so out_data
        // follows in_data; clear in_data and verify out_data goes to zero.
        for (int i = 0; i < ROWS; i++)
            for (int j = 0; j < COLS; j++)
                in_data[i][j] = '0;
        #1;
        for (int i = 0; i < ROWS; i++) begin
            for (int k = 0; k < OUT_C; k++) begin
                if (out_data[i][k] !== '0) begin
                    $display("FAIL zero-input row=%0d col=%0d got=%0d exp=0",
                             i, k, out_data[i][k]);
                    errors++;
                end
            end
        end

        if (errors == 0)
            $display("==== PASS: skew_buffer_horizontal ROWS=%0d COLS=%0d matches expected skew layout ====",
                     ROWS, COLS);
        else
            $display("==== FAIL: %0d skew_buffer_horizontal mismatches ====", errors);

        $finish;
    end

endmodule
