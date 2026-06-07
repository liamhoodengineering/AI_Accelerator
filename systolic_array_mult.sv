`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/06/2026 03:21:38 PM
// Design Name: 
// Module Name: systolic_array_mult
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//typedef logic[15:0] fixed_array_t [30:0][15:0]; 

//function fixed_array_t padding_A_matrix (
//    input logic[15:0] matrix_A [15:0][15:0]
//    ); //16 rows, 16 cols, 16 bits --> 16 rows, 31 cols, 16 bits
    
//    logic[15:0] matrix_out[15:0][30:0];//15 rows, 31 columns
    
//   int i,j;
    
 
//        foreach(matrix_out[i,j])
//                matrix_out[i][j] = 16'b0;
                
//       foreach(matrix_A[i,j])
//       begin
//            matrix_out[i][j+(15-i)] = matrix_A[i][j];
//       end
   
    
    
//    return matrix_out; 
//endfunction

module systolic_array_mult#(
    parameter int ROWS = 16,
    parameter int COLS = 16
    )(
    input logic reset,
    input logic clk,
    output logic[15:0] c_matrix[ROWS-1:0][COLS-1:0]
    );
    logic[15:0] array_A[ROWS-1:0][COLS-1:0];
    logic[15:0] array_B[ROWS-1:0][COLS-1:0];
    logic[15:0] a;
    logic done;
    
    logic[15:0] array_A_out[ROWS-1:0][ROWS+COLS-2:0];
    logic[15:0] array_B_out[ROWS+COLS-2:0][COLS-1:0];
  // logic[15:0] array_B_out[ROWS-1:0][ROWS+COLS-2:0];
   
     skew_buffer_horizontal skew_hor_inst(
         .clk(clk),
         .reset(reset),
         .in_data(array_A),
         .out_data(array_A_out)
     );
     
     skew_buffer_vertical skew_vert_inst(
         .clk(clk),
         .reset(reset),
         .in_data(array_B),
         .out_data(array_B_out)
     );
   
     counter counter_inst(
        .reset(reset), 
        .clk(clk),
        .done(done)
);
    always_ff @(posedge clk)
    begin
        if(reset)begin
            foreach(array_A[i,j])
            begin
                array_A[i][j] <= 16'hFFFF;
                array_B[i][j] <= 16'hFFFF;
            end
           // done <= 1'b0;
        end
        else
        begin
//            array_A[0] <= {0,array_A[0][0:3]};
//            array_A[1] <= {0,array_A[1][0:3]};
//            array_A[2] <= {0,array_A[2][0:3]};
            
//            array_B[4] <= array_B[3];
//            array_B[3] <= array_B[2];
//            array_B[2] <= array_B[1];
//            array_B[1] <= array_B[0];
//            array_B[0] <= '{0,0,0};
//            foreach(array_A_out[i,j])
//                array_A_out[i][j] <= 16'b0;
        end
    end

    logic[15:0] a_grid  [ROWS-1][COLS-1];
    logic[15:0] b_grid [ROWS-1][COLS-1];
    logic[15:0] acc_grid[ROWS-1][COLS-1];
   
    
  

    always_ff @(posedge clk)
    begin
        if(reset) begin
            for(int i = 0; i < ROWS; i++) begin
                for(int j = 0; j < COLS; j++) begin
                    a_grid[i][j]   <= 16'b0;
                    b_grid[i][j]   <= 16'b0;
                    acc_grid[i][j] <= 16'b0;
                end
            end
        end
        else
        begin
            if(done)
                c_matrix <= acc_grid;
            else
            begin
                for(int i = 0; i < ROWS; i++) begin
                    for(int j = 0; j < COLS; j++) begin
                        // A flows left -> right; left edge pulls from array_A column 4
                        a_grid[i][j] <= (j == 0) ? array_A[i][4] : a_grid[i][j-1];
    
                        // B flows top -> bottom; top edge pulls from array_B row 4
                        b_grid[i][j] <= (i == 0) ? array_B[4][j] : b_grid[i-1][j];
    
                        // Local MAC at each PE
                        acc_grid[i][j] <= acc_grid[i][j] + a_grid[i][j] * b_grid[i][j];
                    end
                end
            end
        end
    end
    
    

endmodule


module counter(
    input logic reset, 
    input logic clk,
    output logic done
);

    logic[3:0] counter;
    
    always_ff @(posedge clk)
    begin
         counter <= reset ? 4'b0 : (counter + 4'd1);
    end
    
    assign done = (counter == 4'd8) ? 1'b1 : 1'b0;

endmodule
