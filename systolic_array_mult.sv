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
    input logic[15:0] array_A[ROWS-1:0][COLS-1:0],
    input logic[15:0] array_B[ROWS-1:0][COLS-1:0],
    output logic[15:0] c_matrix[ROWS-1:0][COLS-1:0]
    );
   
    localparam int SKEW_W = ROWS + COLS - 1;   // 31 for 16x16

    logic[15:0] a;
    logic done;

    logic[15:0] array_A_out[ROWS-1:0][ROWS+COLS-2:0];
    logic[15:0] array_B_out[ROWS+COLS-2:0][COLS-1:0];
  // logic[15:0] array_B_out[ROWS-1:0][ROWS+COLS-2:0];

    // Cycle pointer that walks 0..SKEW_W-1 (= 0..30), then holds. Indexes the
    // column of array_A_out / row of array_B_out that feeds the grid edge.
    logic [5:0] col_ptr;
    always_ff @(posedge clk) begin
        if (reset)                       col_ptr <= '0;
        else if (col_ptr < (SKEW_W - 1)) col_ptr <= col_ptr + 6'd1;
    end
   
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
     
    
     
//     BF16_pe_unit BF16_pe_unit_inst(
//        .A(),
//        .B(),
//        .clk(),
//        .reset(),
//        .S()
//     );
   
     counter counter_inst(
        .reset(reset), 
        .clk(clk),
        .done(done)
);
//    always_ff @(posedge clk)
//    begin
//        if(reset)begin
//            foreach(array_A[i,j])
//            begin
//                array_A[i][j] <= 16'hFFFF;
//                array_B[i][j] <= 16'hFFFF;
//            end
//           // done <= 1'b0;
//        end
//        else
//        begin
////            array_A[0] <= {0,array_A[0][0:3]};
////            array_A[1] <= {0,array_A[1][0:3]};
////            array_A[2] <= {0,array_A[2][0:3]};
            
////            array_B[4] <= array_B[3];
////            array_B[3] <= array_B[2];
////            array_B[2] <= array_B[1];
////            array_B[1] <= array_B[0];
////            array_B[0] <= '{0,0,0};
////            foreach(array_A_out[i,j])
////                array_A_out[i][j] <= 16'b0;
//        end
//    end

    logic[15:0] a_grid   [ROWS][COLS];
    logic[15:0] b_grid   [ROWS][COLS];
    logic[15:0] acc_grid [ROWS][COLS];
   
    
  

    always_ff @(posedge clk)
    begin
        if(reset) begin
            for(int i = 0; i < ROWS; i++) begin
                for(int j = 0; j < COLS; j++) begin
                    a_grid[i][j]   <= 16'b0;
                    b_grid[i][j]   <= 16'b0;
              //      acc_grid[i][j] <= 16'b0;
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
                        // A flows left -> right; left edge pulls from the skewed
                        // A buffer at column col_ptr.
                        a_grid[i][j] <= (j == 0) ? array_A_out[i][col_ptr] : a_grid[i][j-1];

                        // B flows top -> bottom; top edge pulls from the skewed
                        // B buffer at row col_ptr; interior shifts down from the
                        // PE above (i-1), not from below.
                        b_grid[i][j] <= (i == 0) ? array_B_out[col_ptr][j] : b_grid[i-1][j];
    
                        // Local MAC at each PE
                        //acc_grid[i][j] <= acc_grid[i][j] + a_grid[i][j] * b_grid[i][j];
                    end
                end
            end
        end
    end
    
    
    genvar i,j;
     
     generate
        for(i = 0; i < 16; i++)
        begin
            for( j = 0; j < 16; j++)
            begin
                  BF16_pe_unit BF16_pe_unit_inst(
                    .A(a_grid[i][j]),
                    .B(b_grid[i][j]),
                    .clk(clk),
                    .reset(reset),
                    .S(acc_grid[i][j])
                 );
            end
        end
          
     endgenerate
    
    

endmodule


module counter(
    input logic reset, 
    input logic clk,
    output logic done
);

    logic[5:0] counter;
    
    always_ff @(posedge clk)
    begin
         counter <= reset ? 6'b0 : (counter + 6'd1);
    end
    
    assign done = (counter == 6'd47) ? 1'b1 : 1'b0;

endmodule
