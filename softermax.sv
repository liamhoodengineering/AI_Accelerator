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
    
    
    
   
    
    
    
    
//16'h3f80+
    
    logic [15:0] max;
    logic [15:0] sum;
    logic [3:0]  counter;

    logic        new_max;
    logic [15:0] neg_logit, delta;
    logic [3:0]  delta_int;
    logic [11:0] delta_frac;                 // unused — reserved for future 2^-frac LUT
    logic [15:0] pow2_neg_delta;
    logic [15:0] sum_scaled, sum_plus_term, sum_new_max, sum_new_max_1;
    
    logic[15:0] frac_out;
    
    
    fractional_bit_shift fractional_bit_shift_inst(
        .delta_frac(delta_frac),
        .frac_out(frac_out)
    );
    
    
    
    

    always_comb
    begin
        for(int i = 0; i < 16; i++)
            logits_out[i] = logits[i] / sum;
    end

    assign neg_logit = logits[counter] ^ 16'h8000;
    assign new_max   = $signed({~logits[counter][15], logits[counter][14:0]})
                     > $signed({~max[15],             max[14:0]});
                     
    

    BF16_Add_Unit  u_sub      (.A(max), .B(neg_logit), .C(delta));
    decimal_decomp u_decomp   (.matrix_a(delta), .new_int(delta_int), .new_decimal(delta_frac));

    assign pow2_neg_delta = {1'b0, 8'd127 - {4'b0, delta_int}, 7'b0};

    BF16_Mult_Unit u_mul      (.A(sum),        .B(pow2_neg_delta), .C(sum_scaled));
    BF16_Add_Unit  u_add_one  (.A(sum_scaled), .B(16'h3F80),       .C(sum_new_max));
    BF16_Mult_Unit frac_mul_1      (.A(frac_out),        .B(sum_new_max), .C(sum_new_max_1));
    BF16_Add_Unit  u_add_term (.A(sum),        .B(pow2_neg_delta), .C(sum_plus_term));
    BF16_Mult_Unit frac_mul_2      (.A(frac_out),        .B(sum_plus_term), .C(sum_plus_term_1));

    always_ff @(posedge clk)
    begin
        if(Reset)
        begin
            max     <= logits[0];
            sum     <= 16'h3F80;
            counter <= 4'd1;
        end
        else
        begin
            counter <= counter + 4'd1;
            sum     <= new_max ? sum_new_max_1     : sum_plus_term_1;
            max     <= new_max ? logits[counter] : max;
        end
    end
endmodule

module fractional_bit_shift(
    input logic[11:0] delta_frac, 
    output logic[15:0] frac_out
    );

    logic[15:0] a_zero, a_one, a_two;
    assign a_zero = 16'h3F80;
    assign a_one = 16'h3F28;
    assign a_two = 16'h3EB0;
    logic[15:0] temp_1, temp_2, temp_3, temp_4;
    BF16_Mult_Unit  horner_eq_1      (.A(a_two), .B({{4{1'b0}},delta_frac}), .C(temp_1));
    BF16_Add_Unit  horner_eq_2      (.A(temp_1), .B(a_one), .C(temp_2));
    BF16_Mult_Unit  horner_eq_3      (.A(temp_2), .B({{4{1'b0}},delta_frac}), .C(temp_3));
    BF16_Add_Unit  horner_eq_4      (.A(temp_3), .B(a_zero), .C(frac_out));

endmodule

module decimal_decomp(
    input  logic [15:0] matrix_a,
    output logic [3:0]  new_int,
    output logic [11:0] new_decimal
);
    // bf16: [15]=sign, [14:7]=exp, [6:0]=mantissa; value = 1.mantissa * 2^(exp-127).
    // base places the implicit '1' at bit 19; right-shift by (134 - exp) lands
    // bit 12 of the result on 2^0, giving Q4.12 in the low 16 bits.
    // For exp > 134 (value >= 256) the left-shift arm produces a wrapped result.
    logic [7:0]  exp     = matrix_a[14:7];
    logic [19:0] base    = {1'b1, matrix_a[6:0], 12'b0};
    logic [19:0] shifted = (exp <= 8'd134) ? (base >> (8'd134 - exp))
                                           : (base << (exp  - 8'd134));

    assign {new_int, new_decimal} = shifted[15:0];
endmodule


