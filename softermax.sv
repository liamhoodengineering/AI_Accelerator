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


module softermax #(
    parameter logic[23:0] dimension = 24'h080000,
    parameter logic[15:0] ONE_IN_BF16 = 16'h3F80,
    parameter int ROWS = 16
    )(
    input logic[15:0] scaling_factor,
    input logic [15:0] logits[16][15:0],
    input logic[15:0] V_matrix[16][16],
    input logic clk,
    input logic Reset,
    input logic [3:0] row_idx,         // which V_out row this pass's o-vector lands in
    output logic[15:0] logits_out[15:0],
    output logic done,                 // high once the 16-element pass completes
    
    input logic[15:0] m_in[16],
    input logic[15:0] d_in[16],
    input logic[15:0] o_in[16],

    output logic[15:0] V_out[16][16],
    output logic[15:0] m_out[16],
    output logic[15:0] d_out[16],
    output logic[15:0] o_out[16]
   // output logic softmax_done[15:0]
    );
    
//    logic[15:0] dim_sqrt;
    localparam[15:0] ROW = 16'd16;
    localparam[15:0] COL = 16'd16;
    
    
    
//    logic[15:0] logits_scaled[15:0];
    
//    always_comb begin
//    for(int i = 0; i < 16; i++) 
//         logits_scaled[i] = logits[i] - 16'h0300;
//     end
    
  
//16'h3f80+
   
   // logic[15:0] d_i;
    logic [15:0] max[ROW];
    logic [15:0] sum[ROW];
    logic [3:0]  counter;

    logic        new_max[ROW];
    logic [15:0] neg_logit[ROW];
    logic [15:0] o_neg_max[ROW];
    logic [15:0] delta[ROW];
    logic [15:0] delta_1[ROW];
    logic [3:0]  delta_int[ROW];
    logic [3:0]  delta_int_1[ROW];
    logic [11:0] delta_frac[ROW];
    logic [11:0] delta_frac_1[ROW];
    logic [15:0] pow2_neg_delta[ROW]; 
    logic [15:0] pow2_neg_delta_1[ROW];          // 2^(-delta_int) only
    logic [15:0] pow2_neg_delta_full[ROW];
    logic [15:0] pow2_neg_delta_full_1[ROW];     // 2^(-delta_int) * 2^(-delta_frac) = 2^(-|delta|)
    logic [15:0] frac_out[ROW]; 
    logic [15:0] frac_out_1[ROW];                // ~ 2^(-delta_frac)
    logic [15:0] sum_scaled, sum_plus_term, sum_new_max [ROW];
    
    logic[15:0] next_max[ROW];
    logic[15:0] next_sum[ROW];

    // ---- Output lanes: logits_out[i] = 2^(x_i - max) / sum (base 2 throughout) ----
    // Option-2 recompute: after the recursion freezes (done=1) max and sum hold
    // their FINAL values, so each lane recomputes its numerator from the final
    // max directly — no stale cached numerators (fixes H3), and every lane
    // (including lane 0) is computed uniformly. Combinational; sample after done.
    // (o_neg_max is declared above and assigned = -max.)
    logic [15:0] o_delta     [ROW][COL];   // x_i - max  (<= 0)
    logic [3:0]  o_int       [ROW][COL];
    logic [11:0] o_frac      [ROW][COL];
    logic [15:0] o_pow2_int  [ROW][COL];
    logic [15:0] o_frac_pow  [ROW][COL];
    logic [15:0] o_pow2_full [ROW][COL];
    logic [15:0] o_quot      [ROW][COL];

    always_comb begin: negate_max
        for(int r = 0; r < ROW; r++)
        begin
                o_neg_max[r] = max[r] ^ 16'h8000;   // -max, shared across lanes
                neg_logit[r] = logits[r][counter] ^ 16'h8000;//negates logit value
        end
    end

    
    generate
        for(genvar row = 0; row < ROW; row++) begin
            for (genvar gi = 0; gi < 16; gi++) begin : out_lane
                BF16_Add_Unit        u_o_sub   (.A(logits[row][gi]),     .B(o_neg_max[row]),      .C(o_delta[row][gi]));//computes xi - mi
                decimal_decomp       u_o_dec   (.matrix_a(o_delta[row][gi]), .new_int(o_int[row][gi]), .new_decimal(o_frac[row][gi]));//breaks xi-mi into decimal and integer portions
                assign o_pow2_int[row][gi] = {1'b0, 8'd127 - {4'b0, o_int[row][gi]}, 7'b0};
                fractional_bit_shift u_o_frac  (.delta_frac(o_frac[row][gi]), .frac_out(o_frac_pow[row][gi]));
                BF16_Mult_Unit       u_o_mul   (.A(o_pow2_int[row][gi]), .B(o_frac_pow[row][gi]), .C(o_pow2_full[row][gi]));//computes 2 ^ (xi-mi)
                BF16_DIV_Unit        u_o_div   (.A(o_pow2_full[row][gi]), .B(sum[row]),           .C(o_quot[row][gi]));//computes (2 ^ (xi-mi))/(sum of current row)
                assign logits_out[row][gi] = (o_delta[row][gi][14:7] >= 8'd131) ? 16'h0000 : o_quot[row][gi];
            end
        end
    endgenerate

   
    // BF16 is sign+magnitude: a plain $signed bit-pattern compare inverts the
    // ordering when BOTH values are negative (bigger magnitude = smaller value).
    // Proper compare: differing signs -> the positive one is larger; both
    // positive -> larger magnitude; both negative -> SMALLER magnitude.
    always_comb
    begin
        for(int r = 0; r < ROW; r++)
        begin
        new_max[r] = (logits[r][counter][15] != max[r][15])//checks if difference in sign
                       ? (max[r][15] & ~logits[r][counter][15])                  // new is positive, max negative
                       : (logits[r][counter][15]//if xi[15] is negative
                            ? (logits[r][counter][14:0] < max[r][14:0])          // both negative: smaller magnitude wins
                            : (logits[r][counter][14:0] > max[r][14:0]));        // both positive: larger magnitude wins
        end
    end   //determines if new_max is present at logits[r][counter]
                 
    generate
        for(genvar r = 0; r < ROW; r++)
        begin
            BF16_Add_Unit  u_sub      (.A(m_in[r]), .B(neg_logit[r]), .C(delta[r]));//delta = max - logits[counter]
            decimal_decomp u_decomp   (.matrix_a(delta[r]), .new_int(delta_int[r]), .new_decimal(delta_frac[r]));//extract integer and decimal porions from delta
            
            BF16_Add_Unit  u_sub_1      (.A(logits[r][counter]), .B(o_neg_max[r]), .C(delta_1[r]));//delta = max - logits[counter]
            decimal_decomp u_decomp_1   (.matrix_a(delta_1[r]), .new_int(delta_int_1[r]), .new_decimal(delta_frac_1[r]));//extract integer and decimal porions from delta_1
        end
    endgenerate
    
    always_comb begin
        for(int r = 0; r < ROW; r++)
        begin
            next_max[r] = new_max[r] ? logits[r][counter] : m_in[r];
            pow2_neg_delta[r] = {1'b0, 8'd127 - {4'b0, delta_int[r]}, 7'b0};
            pow2_neg_delta_1[r] = {1'b0, 8'd127 - {4'b0, delta_int_1[r]}, 7'b0};
        end
    end
    
    generate
        for(genvar r = 0; r < ROW; r++)
        begin
            fractional_bit_shift u_frac (.delta_frac(delta_frac[r]), .frac_out(frac_out[r]));//new_max
            fractional_bit_shift u_frac_1 (.delta_frac(delta_frac_1[r]), .frac_out(frac_out_1[r]));//~new_max
          
            BF16_Mult_Unit u_frac_mul (.A(pow2_neg_delta[r]), .B(frac_out[r]),            .C(pow2_neg_delta_full[r]));//new_max
            BF16_Mult_Unit u_frac_mul_1 (.A(pow2_neg_delta_1[r]), .B(frac_out_1[r]),            .C(pow2_neg_delta_full_1[r]));//~new_max
        end
    endgenerate//computes next_max


    // Underflow guard, same |delta| >= 16 rule as logits_out / coeff_left_c / coeff_right_c:
    // decimal_decomp's 4-bit new_int WRAPS past 16 (e.g. 20 -> 4), so 2^(-|delta|) would come
    // back as ~2^-4 instead of ~0. pow2_neg_delta_full feeds BOTH sum paths, so clamp it once:
    //   new_max path : sum_scaled    = sum * 2^(m_prev-m_new) -> 0, so sum_new_max = 1.0
    //   normal path  : sum_plus_term = sum + 2^(x_i-max)      -> sum (element contributes ~0)
    logic [15:0] pow2_neg_delta_full_c[ROW];
    
    always_comb for(int r = 0; r < ROW; r++) pow2_neg_delta_full_c[r] = (delta[r][14:7] >= 8'd131) ? 16'h0000 : pow2_neg_delta_full[r];
    
    generate
        for(genvar r = 0; r < ROW; r++)begin
            BF16_Mult_Unit u_mul      (.A(max[r]),            .B(pow2_neg_delta_full_c[r]), .C(sum_scaled[r]));
            BF16_Add_Unit  u_add_one  (.A(sum_scaled[r]),     .B(16'h3F80),              .C(sum_new_max[r]));
            BF16_Add_Unit  u_add_term (.A(sum[r]),            .B(pow2_neg_delta_full_c[r]), .C(sum_plus_term[r]));
        end
    endgenerate
    
    always_comb for(int r = 0; r < ROW; r++) next_sum[r] = new_max[r] ? sum_new_max[r]     : sum_plus_term[r];//updates sum for the next iteration for each row
    
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

//    logic [15:0] o_acc [16];                    // o accumulator
    logic [15:0] o_acc [ROW][COL];                    // o accumulator

    logic [15:0] v_sub_delta_1, v_sub_delta_2 [ROW];  // m_{i-1}-m_i,  x_i-m_i
    logic [3:0]  v_delta_int,  v_delta_int_2 [ROW];
    logic [11:0] v_delta_frac, v_delta_frac_2 [ROW];
    logic [15:0] v_pow2_neg_delta,  v_pow2_neg_delta_2 [ROW];
    logic [15:0] v_frac_out, v_frac_out_2 [ROW];
    logic [15:0] v_pow2_full, v_pow2_full_2 [ROW];    // 2^(m_{i-1}-m_i), 2^(x_i-m_i)
    logic [15:0] v_num_left, coeff_left, coeff_right [ROW];
    logic [15:0] coeff_left_c, coeff_right_c [ROW];
    logic [15:0] v_left [ROW][16], v_right [ROW][16], o_next [ROW][16];

    // --- scalar stage: left coefficient ---
    generate
        for(genvar r = 0; r < ROW; r++)
        begin
            BF16_Add_Unit  v_sub_1   (.A(max[r]),             .B(next_max[r] ^ 16'h8000), .C(v_sub_delta_1[r]));   //computes: m_i_minus_1 - m_i
            decimal_decomp v_decomp_1(.matrix_a(v_sub_delta_1[r]), .new_int(v_delta_int[r]), .new_decimal(v_delta_frac[r])); 
        end
    endgenerate
    
    always_comb for(int r = 0; r < ROW; r++) v_pow2_neg_delta[r] = {1'b0, 8'd127 - {4'b0, v_delta_int[r]}, 7'b0};
    
    generate
        for(genvar r = 0; r < ROW; r++)
        begin
            fractional_bit_shift v_fbs_1(.delta_frac(v_delta_frac[r]), .frac_out(v_frac_out[r]));
            BF16_Mult_Unit v_frac_mul(.A(v_pow2_neg_delta[r]), .B(v_frac_out[r]), .C(v_pow2_full[r]));             //computes: 2^(m_i_minus_1 - m_i)
            BF16_Mult_Unit v_mul_1   (.A(sum[r]), .B(v_pow2_full[r]), .C(v_num_left[r]));                          //computes: d_i_minus_1 * 2^(m_i_minus_1 - m_i)
            BF16_DIV_Unit  v_div_1   (.A(v_num_left[r]), .B(next_sum[r]), .C(coeff_left[r]));                      //computes: .../d_i
        end
    endgenerate

    // --- scalar stage: right coefficient ---
    generate
        for(genvar r = 0; r < ROW; r++)
        begin
            BF16_Add_Unit  v_sub_2   (.A(logits[r][counter]), .B(next_max[r] ^ 16'h8000), .C(v_sub_delta_2[r]));   //computes: x_i - m_i
            decimal_decomp v_decomp_2(.matrix_a(v_sub_delta_2[r]), .new_int(v_delta_int_2[r]), .new_decimal(v_delta_frac_2[r]));
        end
    endgenerate
    
    always_comb for(int r = 0; r < ROW; r++) v_pow2_neg_delta_2 = {1'b0, 8'd127 - {4'b0, v_delta_int_2[r]}, 7'b0};
    
    generate
        for(genvar r = 0; r < ROW; r++)
        begin
            fractional_bit_shift v_fbs_2(.delta_frac(v_delta_frac_2[r]), .frac_out(v_frac_out_2[r]));
            BF16_Mult_Unit v_frac_mul_2(.A(v_pow2_neg_delta_2[r]), .B(v_frac_out_2[r]), .C(v_pow2_full_2[r]));     //computes: 2^(x_i - m_i)
            BF16_DIV_Unit  v_div_2   (.A(v_pow2_full_2[r]), .B(next_sum[r]), .C(coeff_right[r]));                  //computes: 2^(x_i - m_i)/d_i
        end
    endgenerate

    // underflow clamps: |delta| >= 16 wraps decimal_decomp's 4-bit int — force coefficient to 0
    always_comb
    begin
        for(int r = 0; r < ROW; r++)
        begin
            coeff_left_c[r]  = (v_sub_delta_1[r][14:7] >= 8'd131) ? 16'h0000 : coeff_left[r];
            coeff_right_c[r] = (v_sub_delta_2[r][14:7] >= 8'd131) ? 16'h0000 : coeff_right[r];
        end
    end

    // --- per-lane vector stage ---
    generate
        for (genvar j = 0; j < 16; j++) begin : v_lane
            BF16_Mult_Unit v_mul_L (.A(coeff_left_c[r]),  .B(o_acc[j]),             .C(v_left[j]));  //computes: coeff_left * o_i_minus_1[j]
            BF16_Mult_Unit v_mul_R (.A(coeff_right_c[r]), .B(V_matrix[counter][j]), .C(v_right[j])); //computes: coeff_right * V[i, j]
            BF16_Add_Unit  v_add   (.A(v_left[j]),     .B(v_right[j]),           .C(o_next[j]));  //adds the two terms
        end
    endgenerate

    // --- o accumulator register + V_out row capture ---
    // Reset seeds o = V[0,:] because the sum/max recursion seeds m=logits[0], d=1
    // (element 0 already incorporated => o_0 = V[0,:] in the gold recursion).
    always_ff @(posedge clk) begin
        if (Reset)
//            for (int j = 0; j < 16; j++) o_acc[j] <= V_matrix[0][j];
            foreach(V_matrix[r,c])
                o_acc[r][c] <= V_matrix[r][c];
               // softmax_done[j] <= 1'b0;
        else if (!done)
              foreach(o_acc[r,c])
                o_acc[r][c] <= o_next[r][c];
//            for (int j = 0; j < 16; j++) o_acc[j] <= o_next[j];
//               // softmax_done[j] <= 1'b1;
//            end
        else
            foreach(V_out[r,c])
                V_out[r][c] <= o_acc[r][c];      // pass complete: place the finished row
    end

    always_ff @(posedge clk)
    begin
        if(Reset)
        begin
            for(int r = 0; r < ROW; r++)
            begin
                max[r]     <= m_in[r];
                sum[r] <= d_in[r];
            end
            counter <= 4'd1;
            done    <= 1'b0;
        end
        else if(!done)
        begin
            // incorporate logits[counter] into the running sum/max
            for(int r = 0; r < ROW; r++)
            begin
                sum[r] <= (counter == 4'd0) ? d_in[r] : (new_max[r] ? sum_new_max[r]     : sum_plus_term[r]);
                max[r] <= (counter == 4'd0) ? m_in[r] : (new_max[r] ? logits[r][counter] : max[r]);
            end
            if(counter == 4'd15)begin
                done <= 1'b1;              // last element processed; freeze state
                for(int r = 0; r < ROW; r++)
                begin
                    m_out[r] = max[r];
                    d_out[r] = sum[r];
                end
            end
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
    assign a_one  = 16'hBF34;   
    assign a_two  = 16'h3E85;   
    assign a_three = 16'hBD6F; 
    
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

