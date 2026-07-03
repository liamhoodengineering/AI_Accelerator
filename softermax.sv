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
    logic [11:0] delta_frac;
    logic [15:0] pow2_neg_delta;          // 2^(-delta_int) only
    logic [15:0] pow2_neg_delta_full;     // 2^(-delta_int) * 2^(-delta_frac) = 2^(-|delta|)
    logic [15:0] frac_out;                // ~ 2^(-delta_frac)
    logic [15:0] sum_scaled, sum_plus_term, sum_new_max;

    always_comb
    begin
        for(int i = 0; i < 16; i++)
            logits_out[i] = logits[i] / sum;
    end

    assign neg_logit = logits[counter] ^ 16'h8000;//negates logit value
   
    assign new_max   = $signed({logits[counter][15], logits[counter][14:0]})
                     > $signed({max[15],             max[14:0]});//decides if current iteration of logits is larger than max
    BF16_Add_Unit  u_sub      (.A(max), .B(neg_logit), .C(delta));//delta = max - logits[counter]
    decimal_decomp u_decomp   (.matrix_a(delta), .new_int(delta_int), .new_decimal(delta_frac));//extract integer and decimal porions from delta

    assign pow2_neg_delta = {1'b0, 8'd127 - {4'b0, delta_int}, 7'b0};

    fractional_bit_shift u_frac (.delta_frac(delta_frac), .frac_out(frac_out));

    // Fold the 2^(-frac) correction into pow2_neg_delta BEFORE the +1.0 / +sum,
    // so the math is  1 + sum*2^(-delta)  and  sum + 2^(-delta), not
    // (1 + sum*2^(-int)) * 2^(-frac).
    BF16_Mult_Unit u_frac_mul (.A(pow2_neg_delta), .B(frac_out),            .C(pow2_neg_delta_full));

    BF16_Mult_Unit u_mul      (.A(sum),            .B(pow2_neg_delta_full), .C(sum_scaled));
    BF16_Add_Unit  u_add_one  (.A(sum_scaled),     .B(16'h3F80),            .C(sum_new_max));
    BF16_Add_Unit  u_add_term (.A(sum),            .B(pow2_neg_delta_full), .C(sum_plus_term));

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
            sum     <= new_max ? sum_new_max     : sum_plus_term;
            max     <= new_max ? logits[counter] : max;
        end
    end
endmodule

module fractional_bit_shift(//applys horner algorithm for approximating 2^frac
    input  logic [11:0] delta_frac,        // 12-bit value from decimal_decomp unit
    output logic [15:0] frac_out           // bf16 ~ 2^(-delta_frac)
    );

    // ----------------------------------------------------------------
    // Q0.12 -> bf16 conversion (priority-encode leading 1, normalize)
    // ----------------------------------------------------------------
    logic [3:0]  lead;        // position of MSB-most '1' in delta_frac (0..11)
    logic [11:0] shifted;     // delta_frac shifted so the leading 1 sits at bit 11
    logic [7:0]  exp_field;
    logic [6:0]  mant_field;
    logic [15:0] frac_bf16;

    always_comb begin
        lead = 4'd0;
        for (int i = 0; i < 12; i++) begin
            if (delta_frac[i]) lead = i[3:0];   // last write wins -> highest set bit
        end
    end

    assign shifted    = delta_frac << (4'd11 - lead);
    assign mant_field = shifted[10:4];
    // value = 2^(lead - 12) * (1.mantissa)  ->  biased exp = 127 + (lead - 12) = lead + 115
    assign exp_field  = 8'd115 + {4'b0000, lead};
    assign frac_bf16  = (delta_frac == 12'd0) ? 16'h0000 : {1'b0, exp_field, mant_field};

    // ----------------------------------------------------------------
    // Horner evaluation of a minimax fit to 2^(-f) on f in [0,1]:
    //   2^(-f) ~ 1 - 0.6585*f + 0.1565*f^2
    //   (q(0)=1.0, q(1)~0.498, q(0.5)~0.710)
    // ----------------------------------------------------------------
    logic [15:0] a_zero, a_one, a_two;
    assign a_zero = 16'h3F80;   // +1.0
    assign a_one  = 16'hBF29;   // -0.6585
    assign a_two  = 16'h3E20;   // +0.1565

    logic [15:0] temp_1, temp_2, temp_3;
    BF16_Mult_Unit horner_eq_1 (.A(a_two),  .B(frac_bf16), .C(temp_1));
    BF16_Add_Unit  horner_eq_2 (.A(temp_1), .B(a_one),     .C(temp_2));
    BF16_Mult_Unit horner_eq_3 (.A(temp_2), .B(frac_bf16), .C(temp_3));
    BF16_Add_Unit  horner_eq_4 (.A(temp_3), .B(a_zero),    .C(frac_out));

endmodule

module decimal_decomp(
    input  logic [15:0] matrix_a,
    output logic [3:0]  new_int,
    output logic [11:0] new_decimal
);
    logic [7:0]  exp;
    logic [19:0] base;
    logic [19:0] shifted;

    assign exp  = matrix_a[14:7];
    assign base = {1'b1, matrix_a[6:0], 12'b0};//implicit leading 1

    assign shifted = (exp <= 8'd134)//could be wrong
                   ? (base >> (8'd134 - exp))
                   : (base << (exp - 8'd134));

    assign new_int     = shifted[15:12];
    assign new_decimal = shifted[11:0];

endmodule


