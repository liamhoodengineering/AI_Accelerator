`timescale 1ns / 1ps

module skew_buffer_horizontal #(
    parameter int ROWS   = 16,
    parameter int COLS   = 16,
    parameter int DATA_W = 16
) (
    input  logic                clk,
    input  logic                reset,
    input  logic [DATA_W-1:0]   in_data  [ROWS-1:0][COLS-1:0],
    output logic [15:0]         out_data [ROWS-1:0][ROWS+COLS-2:0]
);

    int i, j;

    // Pure combinational 2-D reshape: row i of in_data is overlaid into
    // out_data starting at column (DATA_W-1-i). Default the rest to zero so
    // the unwritten cells of the skewed layout read as 0. No clock / reset
    // dependency -- consumers see a valid skewed view in the same delta
    // cycle that in_data is driven.
    always_comb begin
        foreach (out_data[i, j])
            out_data[i][j] = '0;
        foreach (in_data[i, j])
            out_data[i][j + (DATA_W - 1 - i)] = in_data[i][j];
    end

endmodule


module skew_buffer_vertical #(
    parameter int ROWS   = 16,
    parameter int COLS   = 16,
    parameter int DATA_W = 16
) (
    input  logic                clk,
    input  logic                reset,
    input  logic [DATA_W-1:0]   in_data  [ROWS-1:0][COLS-1:0],
    output logic [15:0]         out_data [ROWS+COLS-2:0][COLS-1:0]
);

    int i, j;

    // Symmetric combinational reshape on the column axis: column j of
    // in_data is overlaid into out_data starting at row (DATA_W-2-j).
    always_comb begin
        foreach (out_data[i, j])
            out_data[i][j] = '0;
        foreach (in_data[i, j])
            out_data[i + (DATA_W - 2 - j)][j] = in_data[i][j];
    end

endmodule
