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
    input logic[15:0] V_matrix[16][16],
    input logic clk,
    input logic Reset,
    output logic[15:0] logits_out[15:0],
    output logic done,                 // high once the 16-element pass completes

    output logic[15:0] V_out[16][16]
    );
    
    parameter logic[15:0] ONE_IN_BF16 = 16'h3F80;
    parameter int ROWS = 16;
   
    
  
//16'h3f80+
   
    logic[15:0] d_i;
    logic [15:0] max;
    logic [15:0] sum;
    logic [3:0]  counter;

    logic        new_max;
    logic [15:0] neg_logit;
    logic [15:0] o_neg_max;
    logic [15:0] delta;
    logic [15:0] delta_1;
    logic [3:0]  delta_int;
    logic [3:0]  delta_int_1;
    logic [11:0] delta_frac;
    logic [11:0] delta_frac_1;
    logic [15:0] pow2_neg_delta; 
    logic [15:0] pow2_neg_delta_1;          // 2^(-delta_int) only
    logic [15:0] pow2_neg_delta_full;
    logic [15:0] pow2_neg_delta_full_1;     // 2^(-delta_int) * 2^(-delta_frac) = 2^(-|delta|)
    logic [15:0] frac_out; 
    logic [15:0] frac_out_1;                // ~ 2^(-delta_frac)
    logic [15:0] sum_scaled, sum_plus_term, sum_new_max;
    
    logic[15:0] next_max;
    logic[15:0] next_sum;

    // ---- Output lanes: logits_out[i] = 2^(x_i - max) / sum (base 2 throughout) ----
    // Valid only AFTER the 16-cycle max/sum recursion converges; during the
    // recursion these track the moving max/sum and are garbage.
//    logic [15:0] o_neg_max;
//    logic [15:0] o_delta     [16];   // x_i - max  (<= 0)
//    logic [3:0]  o_int       [16];
//    logic [11:0] o_frac      [16];
//    logic [15:0] o_pow2_int  [16];
//    logic [15:0] o_frac_pow  [16];
//    logic [15:0] o_pow2_full [16];
//    logic [15:0] o_quot      [16];

   // logic[] counter

    assign o_neg_max = max ^ 16'h8000;   // -max, shared across lanes
    assign neg_logit = logits[counter] ^ 16'h8000;//negates logit value
    //        d_i = d_i_minus_1 * np.exp(m_i_minus_1 - m_i) + np.exp(x_i - m_i)

//    generate
//        for (genvar gi = 0; gi < 16; gi++) begin : out_lane
//            // x_i - max (result <= 0; decimal_decomp uses magnitude fields only)
//            BF16_Add_Unit        u_o_sub   (.A(logits[gi]),     .B(o_neg_max),      .C(o_delta[gi]));
//            decimal_decomp       u_o_dec   (.matrix_a(o_delta[gi]), .new_int(o_int[gi]), .new_decimal(o_frac[gi]));
//            // 2^(-int): realizes the negative exponent of 2^(x_i - max)
//            assign o_pow2_int[gi] = {1'b0, 8'd127 - {4'b0, o_int[gi]}, 7'b0};
//            fractional_bit_shift u_o_frac  (.delta_frac(o_frac[gi]), .frac_out(o_frac_pow[gi]));
//            BF16_Mult_Unit       u_o_mul   (.A(o_pow2_int[gi]), .B(o_frac_pow[gi]), .C(o_pow2_full[gi]));
//            BF16_DIV_Unit        u_o_div   (.A(o_pow2_full[gi]), .B(sum),           .C(o_quot[gi]));
//            // Underflow guard: |x_i - max| >= 16 wraps decimal_decomp's 4-bit int — clamp to 0
//            assign logits_out[gi] = (o_delta[gi][14:7] >= 8'd131) ? 16'h0000 : o_quot[gi];
//        end
//    endgenerate
    
    logic[15:0] normalized_logits[16];
    
    always_ff @(posedge clk)begin
        if(Reset)begin
            for(int i = 0; i < 16; i++)
                normalized_logits[i] <= 16'd0;
        end
        else if(!done)
             normalized_logits[counter] <= pow2_neg_delta_full;
      end
    
   // normalized_logits <= reset ? 

    
   
    assign new_max   = $signed({logits[counter][15], logits[counter][14:0]})
                     > $signed({max[15],             max[14:0]});//decides if current iteration of logits is larger than max
                     
    BF16_Add_Unit  u_sub      (.A(max), .B(neg_logit), .C(delta));//delta = max - logits[counter]
    decimal_decomp u_decomp   (.matrix_a(delta), .new_int(delta_int), .new_decimal(delta_frac));//extract integer and decimal porions from delta
    
    BF16_Add_Unit  u_sub_1      (.A(logits[counter]), .B(o_neg_max), .C(delta_1));//delta = max - logits[counter]
    decimal_decomp u_decomp_1   (.matrix_a(delta_1), .new_int(delta_int_1), .new_decimal(delta_frac_1));//extract integer and decimal porions from delta
    
    assign next_max = new_max ? logits[counter] : max;

    assign pow2_neg_delta = {1'b0, 8'd127 - {4'b0, delta_int}, 7'b0};
    assign pow2_neg_delta_1 = {1'b0, 8'd127 - {4'b0, delta_int_1}, 7'b0};
    
    generate
        for(genvar a = 0; a < 16; a++) begin : div_lane
            BF16_DIV_Unit div1(.A(normalized_logits[a]), .B(sum), .C(logits_out[a]));
        end
    endgenerate

    fractional_bit_shift u_frac (.delta_frac(delta_frac), .frac_out(frac_out));//new_max
    fractional_bit_shift u_frac_1 (.delta_frac(delta_frac_1), .frac_out(frac_out_1));//~new_max

  
    BF16_Mult_Unit u_frac_mul (.A(pow2_neg_delta), .B(frac_out),            .C(pow2_neg_delta_full));//new_max
    BF16_Mult_Unit u_frac_mul_1 (.A(pow2_neg_delta_1), .B(frac_out_1),            .C(pow2_neg_delta_full_1));//~new_max


    BF16_Mult_Unit u_mul      (.A(sum),            .B(pow2_neg_delta_full), .C(sum_scaled));
    BF16_Add_Unit  u_add_one  (.A(sum_scaled),     .B(16'h3F80),            .C(sum_new_max));
    BF16_Add_Unit  u_add_term (.A(sum),            .B(pow2_neg_delta_full), .C(sum_plus_term));
    
    assign next_sum = new_max ? sum_new_max     : sum_plus_term;
    
    //    o_i = (o_i_minus_1 * d_i_minus_1 * np.exp(m_i_minus_1 - m_i) / d_i) + (np.exp(x_i - m_i) / d_i) * V[i, :]

//`ifdef ENABLE_V_PATH
//    // Quarantined: unfinished V-matrix path. Known elaboration blockers:
//    //  - `2^(...)` is XOR, not exponentiation
//    //  - generate loop drives V_Out_temp_6 from 16 instances (multiple drivers)
//    //  - v_add_term connects an unpacked array to a 16-bit port
//    //  - V_Out_temp_1 has no driver
//    logic[15:0] V_next[ROWS];
//    logic[15:0] V_Out_temp_1;
//    logic[15:0] V_Out_temp_2;
//    logic[15:0] V_Out_temp_3;//1st term

//    logic[15:0] V_Out_temp_4;
//    logic[15:0] V_Out_temp_5;
//    logic[15:0] V_Out_temp_6;


//    logic[15:0] new_V_Out_temp[ROWS];
//    //        d_i = d_i_minus_1 * np.exp(m_i_minus_1 - m_i) + np.exp(x_i - m_i) -- SUM



//     BF16_Mult_Unit v_mul_1      (.A(V_Out_temp_1),            .B(sum), .C(V_Out_temp_2));
//     BF16_Mult_Unit v_div_1      (.A(V_Out_temp_2),            .B(next_sum), .C(V_Out_temp_3));
//     BF16_Mult_Unit v_mul_2      (.A(V_Out_temp_3),            .B((2^(next_max-max))), .C(V_Out_temp_4));//1st term in addition
//       //    o_i = (o_i_minus_1 * d_i_minus_1 * np.exp(m_i_minus_1 - m_i) / d_i) + (np.exp(x_i - m_i) / d_i) * V[i, :]


//     BF16_Mult_Unit v_div_2      (.A(pow2_neg_delta_full),            .B(next_sum), .C(V_Out_temp_5));

//     generate
//         for(genvar i = 0; i < 16; i++)
//            BF16_Mult_Unit v_mul_3      (.A(V_Out_temp_5),            .B((2^(next_max-max))), .C(V_Out_temp_6));//1st term in addition
//    endgenerate

//     BF16_Add_Unit  v_add_term (.A(V_Out_temp_6), .B(V_Out_temp_4), .C(new_V_Out_temp));


////    always_comb begin
////        foreach(V_matrix[i])
////        begin
////            V_next[i] = (V_Out_temp_1*sum*(2^(next_max-max)/next_sum) + (pow2_neg_delta_full/next_sum)*V_matrix[i]);
////        end

////    end
//`endif // ENABLE_V_PATH

    always_ff @(posedge clk)
    begin
        if(Reset)
        begin
            max     <= logits[0];
            sum     <= 16'h3F80;
            counter <= 4'd1;
            done    <= 1'b0;
        end
        else if(!done)
        begin
            // incorporate logits[counter] into the running sum/max
            sum <= new_max ? sum_new_max     : sum_plus_term;
            max <= new_max ? logits[counter] : max;
            if(counter == 4'd15)
                done <= 1'b1;              // last element processed; freeze state
            else
                counter <= counter + 4'd1;
        end
        // done: hold max, sum, counter (no further accumulation)
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


//import numpy as np

//def flash_attention(Q, K, V, k):
//    """   
//    Parameters:
//    Q: Query matrix
//    K: Key matrix (transposed in the computation)
//    V: Value matrix
//    k: Row index for query
    
//    Returns:
//    Output vector O[k,:] after processing - equivalent to softmax(Q[k,:] @ K) @ V
//    """
//    N = K.shape[1]  # Get the dimension from K matrix
    
//    # Initialize variables
    //    m_i_minus_1 = float('-inf')  # Initial value for m_{i-1}
    //    d_i_minus_1 = 0.0  # Initial value for d'_{i-1}
//    o_i_minus_1 = np.zeros_like(V[0, :])  # Initial value for o'_{i-1}
    
//    for i in range(N):
//        # Calculate x_i using the k-th row of Q and i-th column of K^T
//        x_i = np.dot(Q[k, :], K[:, i])
        
//        # Update max value
//        m_i = max(m_i_minus_1, x_i)
        
//        # Calculate d'_i
//        d_i = d_i_minus_1 * np.exp(m_i_minus_1 - m_i) + np.exp(x_i - m_i)
        
//        # Calculate o'_i
//        o_i = (o_i_minus_1 * d_i_minus_1 * np.exp(m_i_minus_1 - m_i) / d_i) + (np.exp(x_i - m_i) / d_i) * V[i, :]
        
//        # Update previous values for next iteration
//        m_i_minus_1 = m_i
//        d_i_minus_1 = d_i
//        o_i_minus_1 = o_i
    
//    # The result is o'_N
//    return o_i_minus_1

