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
    // out_data starting at column i (canonical output-stationary skew --
    // row 0 has no delay, row ROWS-1 is delayed by ROWS-1 cycles). The
    // wavefront propagates left-to-right from PE(0,0) when consumed by a
    // systolic grid.
    always_comb begin
        foreach (out_data[i, j])
            out_data[i][j] = '0;
        foreach (in_data[i, j])
            out_data[i][j + i] = in_data[i][j];
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
    // in_data is overlaid into out_data starting at row j (canonical
    // output-stationary skew -- col 0 has no delay, col COLS-1 is delayed by
    // COLS-1 cycles). Pairs with horizontal's row-i offset so PE(i,j)
    // sees A[i][k] and B[k][j] aligned in the same cycle.
    always_comb begin
        foreach (out_data[i, j])
            out_data[i][j] = '0;
        foreach (in_data[i, j])
            out_data[i + j][j] = in_data[i][j];
    end

endmodule
