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
    input logic [3:0] row_idx,         // which V_out row this pass's o-vector lands in
    output logic[15:0] logits_out[15:0],
    output logic done,                 // high once the 16-element pass completes

    output logic[15:0] V_out[16][16]
   // output logic softmax_done[15:0]
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
    // Option-2 recompute: after the recursion freezes (done=1) max and sum hold
    // their FINAL values, so each lane recomputes its numerator from the final
    // max directly — no stale cached numerators (fixes H3), and every lane
    // (including lane 0) is computed uniformly. Combinational; sample after done.
    // (o_neg_max is declared above and assigned = -max.)
    logic [15:0] o_delta     [16];   // x_i - max  (<= 0)
    logic [3:0]  o_int       [16];
    logic [11:0] o_frac      [16];
    logic [15:0] o_pow2_int  [16];
    logic [15:0] o_frac_pow  [16];
    logic [15:0] o_pow2_full [16];
    logic [15:0] o_quot      [16];

    assign o_neg_max = max ^ 16'h8000;   // -max, shared across lanes
    assign neg_logit = logits[counter] ^ 16'h8000;//negates logit value
    //        d_i = d_i_minus_1 * np.exp(m_i_minus_1 - m_i) + np.exp(x_i - m_i)

    generate
        for (genvar gi = 0; gi < 16; gi++) begin : out_lane
            // x_i - max (result <= 0; decimal_decomp uses magnitude fields only)
            BF16_Add_Unit        u_o_sub   (.A(logits[gi]),     .B(o_neg_max),      .C(o_delta[gi]));
            decimal_decomp       u_o_dec   (.matrix_a(o_delta[gi]), .new_int(o_int[gi]), .new_decimal(o_frac[gi]));
            // 2^(-int): realizes the negative exponent of 2^(x_i - max)
            assign o_pow2_int[gi] = {1'b0, 8'd127 - {4'b0, o_int[gi]}, 7'b0};
            fractional_bit_shift u_o_frac  (.delta_frac(o_frac[gi]), .frac_out(o_frac_pow[gi]));
            BF16_Mult_Unit       u_o_mul   (.A(o_pow2_int[gi]), .B(o_frac_pow[gi]), .C(o_pow2_full[gi]));
            BF16_DIV_Unit        u_o_div   (.A(o_pow2_full[gi]), .B(sum),           .C(o_quot[gi]));
            // Underflow guard: |x_i - max| >= 16 wraps decimal_decomp's 4-bit int — clamp to 0
            assign logits_out[gi] = (o_delta[gi][14:7] >= 8'd131) ? 16'h0000 : o_quot[gi];
        end
    endgenerate


    // BF16 is sign+magnitude: a plain $signed bit-pattern compare inverts the
    // ordering when BOTH values are negative (bigger magnitude = smaller value).
    // Proper compare: differing signs -> the positive one is larger; both
    // positive -> larger magnitude; both negative -> SMALLER magnitude.
    assign new_max = (logits[counter][15] != max[15])
                   ? (max[15] & ~logits[counter][15])                  // new is positive, max negative
                   : (logits[counter][15]
                        ? (logits[counter][14:0] < max[14:0])          // both negative: smaller magnitude wins
                        : (logits[counter][14:0] > max[14:0]));        // both positive: larger magnitude wins
                     
    BF16_Add_Unit  u_sub      (.A(max), .B(neg_logit), .C(delta));//delta = max - logits[counter]
    decimal_decomp u_decomp   (.matrix_a(delta), .new_int(delta_int), .new_decimal(delta_frac));//extract integer and decimal porions from delta
    
    BF16_Add_Unit  u_sub_1      (.A(logits[counter]), .B(o_neg_max), .C(delta_1));//delta = max - logits[counter]
    decimal_decomp u_decomp_1   (.matrix_a(delta_1), .new_int(delta_int_1), .new_decimal(delta_frac_1));//extract integer and decimal porions from delta
    
    assign next_max = new_max ? logits[counter] : max;

    assign pow2_neg_delta = {1'b0, 8'd127 - {4'b0, delta_int}, 7'b0};
    assign pow2_neg_delta_1 = {1'b0, 8'd127 - {4'b0, delta_int_1}, 7'b0};
    
    // (logits_out is driven by the out_lane recompute block above.)

    fractional_bit_shift u_frac (.delta_frac(delta_frac), .frac_out(frac_out));//new_max
    fractional_bit_shift u_frac_1 (.delta_frac(delta_frac_1), .frac_out(frac_out_1));//~new_max

  
    BF16_Mult_Unit u_frac_mul (.A(pow2_neg_delta), .B(frac_out),            .C(pow2_neg_delta_full));//new_max
    BF16_Mult_Unit u_frac_mul_1 (.A(pow2_neg_delta_1), .B(frac_out_1),            .C(pow2_neg_delta_full_1));//~new_max


    BF16_Mult_Unit u_mul      (.A(sum),            .B(pow2_neg_delta_full), .C(sum_scaled));
    BF16_Add_Unit  u_add_one  (.A(sum_scaled),     .B(16'h3F80),            .C(sum_new_max));
    BF16_Add_Unit  u_add_term (.A(sum),            .B(pow2_neg_delta_full), .C(sum_plus_term));
    
    assign next_sum = new_max ? sum_new_max     : sum_plus_term;
    
    // ---- Flash-attention output recursion (per streamed element counter) ----
    //********* EQUATION FOR OUTPUT: o_i = (o_i_minus_1 * d_i_minus_1 * 2^(m_i_minus_1 - m_i) / d_i) + (2^(x_i - m_i) / d_i) * V[i, :]
    //
    // Split into two SCALAR coefficients shared by all 16 lanes:
    //   coeff_left  = d_{i-1} * 2^(m_{i-1}-m_i) / d_i
    //   coeff_right = 2^(x_i - m_i) / d_i          (x_i = logits[counter], the streamed element)
    // then per lane j:  o_next[j] = coeff_left*o_acc[j] + coeff_right*V_matrix[counter][j]
    //
    // d_{i-1}/m_{i-1} are the registered sum/max; d_i/m_i are next_sum/next_max
    // (the post-update values for the element incorporated this cycle) — matching
    // the gold iteration. o_acc registers each cycle while !done; when done, the
    // finished o-vector is placed into V_out[row_idx].

    logic [15:0] o_acc [16];                    // o accumulator
    logic [15:0] v_sub_delta_1, v_sub_delta_2;  // m_{i-1}-m_i,  x_i-m_i
    logic [3:0]  v_delta_int,  v_delta_int_2;
    logic [11:0] v_delta_frac, v_delta_frac_2;
    logic [15:0] v_pow2_neg_delta,  v_pow2_neg_delta_2;
    logic [15:0] v_frac_out, v_frac_out_2;
    logic [15:0] v_pow2_full, v_pow2_full_2;    // 2^(m_{i-1}-m_i), 2^(x_i-m_i)
    logic [15:0] v_num_left, coeff_left, coeff_right;
    logic [15:0] coeff_left_c, coeff_right_c;
    logic [15:0] v_left [16], v_right [16], o_next [16];

    // --- scalar stage: left coefficient ---
    BF16_Add_Unit  v_sub_1   (.A(max),             .B(next_max ^ 16'h8000), .C(v_sub_delta_1));   //computes: m_i_minus_1 - m_i
    decimal_decomp v_decomp_1(.matrix_a(v_sub_delta_1), .new_int(v_delta_int), .new_decimal(v_delta_frac));
    assign v_pow2_neg_delta = {1'b0, 8'd127 - {4'b0, v_delta_int}, 7'b0};
    fractional_bit_shift v_fbs_1(.delta_frac(v_delta_frac), .frac_out(v_frac_out));
    BF16_Mult_Unit v_frac_mul(.A(v_pow2_neg_delta), .B(v_frac_out), .C(v_pow2_full));             //computes: 2^(m_i_minus_1 - m_i)
    BF16_Mult_Unit v_mul_1   (.A(sum), .B(v_pow2_full), .C(v_num_left));                          //computes: d_i_minus_1 * 2^(m_i_minus_1 - m_i)
    BF16_DIV_Unit  v_div_1   (.A(v_num_left), .B(next_sum), .C(coeff_left));                      //computes: .../d_i

    // --- scalar stage: right coefficient ---
    BF16_Add_Unit  v_sub_2   (.A(logits[counter]), .B(next_max ^ 16'h8000), .C(v_sub_delta_2));   //computes: x_i - m_i
    decimal_decomp v_decomp_2(.matrix_a(v_sub_delta_2), .new_int(v_delta_int_2), .new_decimal(v_delta_frac_2));
    assign v_pow2_neg_delta_2 = {1'b0, 8'd127 - {4'b0, v_delta_int_2}, 7'b0};
    fractional_bit_shift v_fbs_2(.delta_frac(v_delta_frac_2), .frac_out(v_frac_out_2));
    BF16_Mult_Unit v_frac_mul_2(.A(v_pow2_neg_delta_2), .B(v_frac_out_2), .C(v_pow2_full_2));     //computes: 2^(x_i - m_i)
    BF16_DIV_Unit  v_div_2   (.A(v_pow2_full_2), .B(next_sum), .C(coeff_right));                  //computes: 2^(x_i - m_i)/d_i

    // underflow clamps: |delta| >= 16 wraps decimal_decomp's 4-bit int — force coefficient to 0
    assign coeff_left_c  = (v_sub_delta_1[14:7] >= 8'd131) ? 16'h0000 : coeff_left;
    assign coeff_right_c = (v_sub_delta_2[14:7] >= 8'd131) ? 16'h0000 : coeff_right;

    // --- per-lane vector stage ---
    generate
        for (genvar j = 0; j < 16; j++) begin : v_lane
            BF16_Mult_Unit v_mul_L (.A(coeff_left_c),  .B(o_acc[j]),             .C(v_left[j]));  //computes: coeff_left * o_i_minus_1[j]
            BF16_Mult_Unit v_mul_R (.A(coeff_right_c), .B(V_matrix[counter][j]), .C(v_right[j])); //computes: coeff_right * V[i, j]
            BF16_Add_Unit  v_add   (.A(v_left[j]),     .B(v_right[j]),           .C(o_next[j]));  //adds the two terms
        end
    endgenerate

    // --- o accumulator register + V_out row capture ---
    // Reset seeds o = V[0,:] because the sum/max recursion seeds m=logits[0], d=1
    // (element 0 already incorporated => o_0 = V[0,:] in the gold recursion).
    always_ff @(posedge clk) begin
        if (Reset)
            for (int j = 0; j < 16; j++) o_acc[j] <= V_matrix[0][j];
               // softmax_done[j] <= 1'b0;
        else if (!done)begin
            for (int j = 0; j < 16; j++) o_acc[j] <= o_next[j];
               // softmax_done[j] <= 1'b1;
            end
        else
            V_out[row_idx] <= o_acc;      // pass complete: place the finished row
    end

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
    //2^(-f) ~ 1- 0.6585*f + 0.2314*f^2 - 0.03*f^3?
   // 1+ f*(-0.6585 + f*(0.2314 - 0.04*f))
    // ----------------------------------------------------------------
    logic [15:0] a_zero, a_one, a_two, a_three;
    assign a_zero = 16'h3F80;   // +1.0
    assign a_one  = 16'hBF31;   // -0.69140625
    assign a_two  = 16'h3E6D;   // 0.23144531
    assign a_three = 16'hBD24; // -0.04003906
    
    //-0.69314718056
    //0.240227

    logic [15:0] temp_1, temp_2, temp_3, temp_4, temp_5;
    BF16_Mult_Unit horner_eq_1 (.A(a_three),  .B(frac_bf16), .C(temp_1));
    BF16_Add_Unit  horner_eq_2 (.A(temp_1), .B(a_two),     .C(temp_2));
    BF16_Mult_Unit horner_eq_3 (.A(temp_2), .B(frac_bf16), .C(temp_3));
    BF16_Add_Unit  horner_eq_4 (.A(temp_3), .B(a_one),    .C(temp_4));
    BF16_Mult_Unit  horner_eq_5 (.A(temp_4), .B(frac_bf16),    .C(temp_5));
    BF16_Add_Unit  horner_eq_6 (.A(temp_5), .B(a_zero),    .C(frac_out));


    


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
//        m_i_minus_1 = float('-inf')  # Initial value for m_{i-1}
//        d_i_minus_1 = 0.0  # Initial value for d'_{i-1}
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

