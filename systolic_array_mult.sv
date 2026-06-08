`timescale 1ns / 1ps

module systolic_array_mult #(
    parameter int ROWS = 16,
    parameter int COLS = 16
)(
    input  logic         reset,
    input  logic         clk,
    input  logic [15:0]  array_A  [ROWS-1:0][COLS-1:0],
    input  logic [15:0]  array_B  [ROWS-1:0][COLS-1:0],
    output logic [15:0]  c_matrix [ROWS-1:0][COLS-1:0]
);

    localparam int SKEW_W = ROWS + COLS - 1;   // 31 for 16x16

    logic done;

    // Skewed views of the input matrices (combinational reshapes).
    logic [15:0] array_A_out [ROWS-1:0][SKEW_W-1:0];
    logic [15:0] array_B_out [SKEW_W-1:0][COLS-1:0];

    skew_buffer_horizontal skew_hor_inst (
        .clk(clk),
        .reset(reset),
        .in_data(array_A),
        .out_data(array_A_out));

    skew_buffer_vertical skew_vert_inst (
        .clk(clk),
        .reset(reset),
        .in_data(array_B),
        .out_data(array_B_out));

    counter counter_inst (
        .reset(reset),
        .clk(clk),
        .done(done));

    // -------------------------------------------------------------------------
    // Cycle pointer that walks the skewed buffers
    // -------------------------------------------------------------------------
    // col_ptr advances 0, 1, 2, ... up to SKEW_W-1, then holds. It is used to
    // index the column of array_A_out and the row of array_B_out that feed the
    // left / top edge of the PE grid this cycle.
    logic [5:0] col_ptr;
    always_ff @(posedge clk) begin
        if (reset)
            col_ptr <= '0;
        else if (col_ptr < (SKEW_W - 1))
            col_ptr <= col_ptr + 6'd1;
    end

    // -------------------------------------------------------------------------
    // PE-grid input registers (a_grid, b_grid) and accumulator (acc_grid)
    // -------------------------------------------------------------------------
    logic [15:0] a_grid   [ROWS][COLS];
    logic [15:0] b_grid   [ROWS][COLS];
    logic [15:0] acc_grid [ROWS][COLS];

    // a flows left -> right; left edge pulls from the skewed A buffer at col_ptr.
    // b flows top  -> bottom; top edge pulls from the skewed B buffer at col_ptr.
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < ROWS; i++)
                for (int j = 0; j < COLS; j++) begin
                    a_grid[i][j] <= 16'b0;
                    b_grid[i][j] <= 16'b0;
                end
        end
        else begin
            for (int i = 0; i < ROWS; i++)
                for (int j = 0; j < COLS; j++) begin
                    a_grid[i][j] <= (j == 0) ? array_A_out[i][col_ptr]
                                             : a_grid[i][j-1];
                    b_grid[i][j] <= (i == 0) ? array_B_out[col_ptr][j]
                                             : b_grid[i-1][j];
                end
        end
    end

    // -------------------------------------------------------------------------
    // PE grid: one BF16_pe_unit per (i,j). Single driver on acc_grid.
    // -------------------------------------------------------------------------
    genvar k, l;
    generate
        for (k = 0; k < ROWS; k++) begin : pe_row
            for (l = 0; l < COLS; l++) begin : pe_col
                BF16_pe_unit BF16_pe_unit_inst (
                    .clk(clk),
                    .reset(reset),
                    .A(a_grid[k][l]),
                    .B(b_grid[k][l]),
                    .S(acc_grid[k][l]));
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Final latch: snapshot acc_grid into c_matrix when done pulses high.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < ROWS; i++)
                for (int j = 0; j < COLS; j++)
                    c_matrix[i][j] <= 16'b0;
        end
        else if (done) begin
            c_matrix <= acc_grid;
        end
    end

endmodule


module counter(
    input  logic reset,
    input  logic clk,
    output logic done
);

    logic [5:0] counter;

    always_ff @(posedge clk) begin
        counter <= reset ? 6'b0 : (counter + 6'd1);
    end

    // 16x16 matmul completes after ~ROWS + COLS + K - 2 cycles. Assert done at
    // cycle 47 (one extra cycle of margin past the last MAC).
    assign done = (counter == 6'd47);

endmodule
