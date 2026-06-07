`timescale 1ns / 1ps

module skew_buffer_horizontal #(
    parameter int ROWS   = 16,
    parameter int COLS   = 16,
    parameter int DATA_W = 16
) (
    input  logic                clk,
    input  logic                reset,
    input  logic [DATA_W-1:0]   in_data  [ROWS-1:0][COLS-1:0],
    output logic [15:0] out_data [ROWS-1:0][ROWS+COLS-2:0]
);

  
   logic[15:0] matrix_tmp[ROWS][COLS+15];
    int i,j;
    always_ff @(posedge clk) begin
        if (reset) begin
           foreach(out_data[i,j])
                matrix_tmp[i][j] <= {DATA_W{1'b0}};
           
        end
        else begin
           foreach(in_data[i,j])
           begin
                matrix_tmp[i][j+(DATA_W-2-i)] = in_data[i][j];
           end
        end
    end

    always_comb begin

        foreach(out_data[i,j])
            out_data[i][j] = matrix_tmp[i][j];
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
    output logic [15:0] out_data [ROWS+COLS-2:0][COLS-1:0]
);


   logic[15:0] matrix_tmp[ROWS+15][COLS];
    int i,j;
    always_ff @(posedge clk) begin
        if (reset) begin
           foreach(out_data[i,j])
                matrix_tmp[i][j] <= {DATA_W{1'b0}};

        end
        else begin
           foreach(in_data[i,j])
           begin
                matrix_tmp[i+(DATA_W-2-j)][j] = in_data[i][j];
           end
        end
    end

    always_comb begin

        foreach(out_data[i,j])
            out_data[i][j] = matrix_tmp[i][j];
    end

endmodule
