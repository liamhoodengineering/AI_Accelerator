`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/08/2026 09:29:10 PM
// Design Name: 
// Module Name: softermax
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


module softermax(
    input logic [15:0] logits[15:0],
    input logic clk,
    input logic Reset,
    output logic[15:0] logits_out[15:0]
    );
    
    logic[15:0] max;
    logic[15:0] sum;
    logic[3:0] counter;
    logic[15:0] curr_logit;
    logic[15:0] curr_sum, curr_sum_1, curr_sum_2, product_2;
    
    assign curr_logit = ~(logits[counter]) + 16'd1;
    
    always_comb
    begin
        for(int i = 0; i < 16; i++)
            logits_out[i] = logits[i] / sum;
    end
     
    
    //assign 
    
    BF16_Add_Unit  BF16_Add_Unit_inst  (.A(max), .B(curr_logit), .C(curr_sum));//max - logits[counter]
    BF16_Add_Unit  BF16_Add_Unit_inst_1  (.A(sum), .B(((16'h4000) >> (curr_sum))), .C(curr_sum_1));//sum + (max - logits[counter])
//    BF16_Add_Unit  BF16_Add_Unit_inst_2  (.A(sum), .B(((16'h4000) >> (~curr_sum+16'd1))), .C(curr_sum_2));//max - logits[counter]
  
    BF16_Mult_Unit BF16_Mult_Unit_inst (.A(sum),      .B(((16'h4000) >> (~curr_sum+16'd1))),          .C(product_2));
        
    always_ff @(posedge clk)
    begin
        if(Reset)
        begin
            max <= logits[0];
            sum <= 16'h3f80;
            counter <= 4'd1;
        end
        else
        begin
            counter <= counter + 4'd1;
            
            sum <= (logits[counter] > max) ? (product_2+16'h3f80) : curr_sum_1;
            
            
        end
    end
endmodule 

module decimal_decomp(
    input logic[15:0] matrix_a,
    output logic[8:0] new_int,
    output logic[6:0] new_decimal
);
    logic[15:0] new_num;
    logic sign = matrix_a[15];
    logic[7:0] exponent;
    assign exponent = matrix_a[14:7];
    logic[6:0] mantissa;
    assign mantissa = matrix_a[6:0];
    logic[7:0] shift;
    assign shift = exponent - 8'd127;
    
    logic[16:0] mantissa_extended;
    assign mantissa_extended = {{8{1'b0}},1'b1,mantissa};
    
    always_comb
    begin
        if(exponent >= 8'd127)
        begin
            new_num = mantissa_extended << shift;
        end
        else if(exponent < 8'd127)
        begin
            new_num = mantissa_extended >> shift;
        end
    end
    
    assign new_int = new_num[15:7];
    assign new_decimal = new_num[6:0];


endmodule


//16'h4000;