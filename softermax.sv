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
    // Unused here (kept for FSM_tiling port compatibility): the logit tile is
    // already 1/sqrt(D)-scaled upstream. Present only so elaboration matches the
    // FSM_tiling instantiation; softermax's output path is not exercised by the
    // logit/scores check (CHECK_OUT=0).
    input logic [15:0] scaling_factor,
    // Full logit TILE: logits[query_row][key] for the 16 keys of this key-block.
    input logic [15:0] logits[16][15:0],
    input logic[15:0] V_matrix[16][16],
    input logic clk,
    input logic Reset,
    // Vestigial: every V_out row is now written by the internal row sequencer, so
    // there is no single destination row to select. Kept for port compatibility.
    input logic [3:0] row_idx,
    // ---- Chainable flash-attention state (carry running m/d/o across key-blocks) ----
    // One pass consumes a whole 16x16 tile: 16 query rows x 16 keys = 256 cycles.
    input  logic        softermax_start,  // 1-cycle pulse: begin a tile
    input  logic [15:0] m_in [16],        // carried running max per row (seed 0xFF80 = -inf)
    input  logic [15:0] d_in [16],        // carried running sum per row (seed 0)
    input  logic [15:0] o_in [16][16],    // carried running output per row (seed 0)
    output logic [15:0] m_out [16],       // running max per row after this tile
    output logic [15:0] d_out [16],       // running sum per row after this tile
    output logic [15:0] o_out [16][16],   // running output per row after this tile
    output logic[15:0] logits_out[15:0],  // debug: weights for the row being streamed
    output logic softmax_done,            // high once all 16 rows complete

    output logic[15:0] V_out[16][16]
    );

    // Expose the running registers so the FSM can chain blocks.
    // (max/sum/o_acc are declared below; assigned here as outputs.)
    
    parameter logic[15:0] ONE_IN_BF16 = 16'h3F80;
    parameter int ROWS = 16;
    
  
//16'h3f80+
   
    logic [15:0] max;
    logic [15:0] sum;
    logic [3:0]  counter;   // key index within the current row (0..15)
    logic [3:0]  row;       // query row being streamed  (0..15)

    logic        new_max;
    logic [15:0] neg_logit;
    logic [15:0] o_neg_max;
    logic [15:0] delta;
    logic [3:0]  delta_int;
    logic [11:0] delta_frac;
    logic [15:0] pow2_neg_delta;            // 2^(-delta_int) only
    logic [15:0] pow2_neg_delta_full;       // 2^(-delta_int) * 2^(-delta_frac) = 2^(-|delta|)
    logic [15:0] frac_out;                  // ~ 2^(-delta_frac)
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
    assign neg_logit = logits[row][counter] ^ 16'h8000;//negates logit value
    //        d_i = d_i_minus_1 * np.exp(m_i_minus_1 - m_i) + np.exp(x_i - m_i)

    generate
        for (genvar gi = 0; gi < 16; gi++) begin : out_lane
            // x_i - max (result <= 0; decimal_decomp uses magnitude fields only)
            BF16_Add_Unit        u_o_sub   (.A(logits[row][gi]), .B(o_neg_max),     .C(o_delta[gi]));
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
    assign new_max = (logits[row][counter][15] != max[15])
                   ? (max[15] & ~logits[row][counter][15])                  // new is positive, max negative
                   : (logits[row][counter][15]
                        ? (logits[row][counter][14:0] < max[14:0])          // both negative: smaller magnitude wins
                        : (logits[row][counter][14:0] > max[14:0]));        // both positive: larger magnitude wins
                     
    BF16_Add_Unit  u_sub      (.A(max), .B(neg_logit), .C(delta));//delta = max - logits[counter]
    decimal_decomp u_decomp   (.matrix_a(delta), .new_int(delta_int), .new_decimal(delta_frac));//extract integer and decimal porions from delta

    // NOTE: a second chain used to compute delta_1 = logits[counter] - max and
    // decompose it separately for the ~new_max path. It was dead weight: delta_1
    // is the exact negation of delta, and decimal_decomp reads only matrix_a[14:7]
    // and [6:0] -- never the sign bit -- so both chains produced bit-identical
    // new_int/new_decimal, hence identical frac_out and pow2_neg_delta_full. The
    // result of the duplicate chain was never consumed. Removed: it cost one
    // BF16_Add_Unit, one decimal_decomp, one fractional_bit_shift (2 mults +
    // 2 adds internally) and one BF16_Mult_Unit per softermax instance.
    // 2^(-|delta|) below serves BOTH the new_max and ~new_max paths.

    assign next_max = new_max ? logits[row][counter] : max;

    assign pow2_neg_delta = {1'b0, 8'd127 - {4'b0, delta_int}, 7'b0};

    // (logits_out is driven by the out_lane recompute block above.)

    fractional_bit_shift u_frac (.delta_frac(delta_frac), .frac_out(frac_out));

    BF16_Mult_Unit u_frac_mul (.A(pow2_neg_delta), .B(frac_out),            .C(pow2_neg_delta_full));


    // Underflow guard, same |delta| >= 16 rule as logits_out / coeff_left_c / coeff_right_c:
    // decimal_decomp's 4-bit new_int WRAPS past 16 (e.g. 20 -> 4), so 2^(-|delta|) would come
    // back as ~2^-4 instead of ~0. pow2_neg_delta_full feeds BOTH sum paths, so clamp it once:
    //   new_max path : sum_scaled    = sum * 2^(m_prev-m_new) -> 0, so sum_new_max = 1.0
    //   normal path  : sum_plus_term = sum + 2^(x_i-max)      -> sum (element contributes ~0)
    logic [15:0] pow2_neg_delta_full_c;
    assign pow2_neg_delta_full_c = (delta[14:7] >= 8'd131) ? 16'h0000 : pow2_neg_delta_full;

    BF16_Mult_Unit u_mul      (.A(sum),            .B(pow2_neg_delta_full_c), .C(sum_scaled));
    BF16_Add_Unit  u_add_one  (.A(sum_scaled),     .B(16'h3F80),              .C(sum_new_max));
    BF16_Add_Unit  u_add_term (.A(sum),            .B(pow2_neg_delta_full_c), .C(sum_plus_term));
    
    assign next_sum = new_max ? sum_new_max     : sum_plus_term;
    
    // ---- Flash-attention output recursion (per streamed element counter) ----
    //********* EQUATION FOR OUTPUT: o_i = (o_i_minus_1 * d_i_minus_1 * 2^(m_i_minus_1 - m_i) / d_i) + (2^(x_i - m_i) / d_i) * V[i, :]
    //
    // Split into two SCALAR coefficients shared by all 16 lanes:
    //   coeff_left  = d_{i-1} * 2^(m_{i-1}-m_i) / d_i
    //   coeff_right = 2^(x_i - m_i) / d_i     (x_i = logits[row][counter], streamed element)
    // then per lane j:  o_next[j] = coeff_left*o_acc[j] + coeff_right*V_matrix[counter][j]
    //
    // V_matrix is indexed by `counter` alone: it holds this key-block's V rows, which
    // are the same 16 keys for every query row.
    //
    // d_{i-1}/m_{i-1} are the registered sum/max; d_i/m_i are next_sum/next_max
    // (the post-update values for the element incorporated this cycle) — matching
    // the gold iteration. o_acc registers each cycle within a row; at counter==15
    // the finished o-vector goes to o_out[row] and V_out[row].

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
    BF16_Add_Unit  v_sub_2   (.A(logits[row][counter]), .B(next_max ^ 16'h8000), .C(v_sub_delta_2));   //computes: x_i - m_i
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

    // --- o accumulator register + per-row result capture ---
    // Seeded from the carried o_in[row] at each row boundary and streamed while the
    // row runs. On the last element of a row (counter==15) o_next already holds that
    // row's finished vector, so it is published straight to o_out[row] (and thus
    // V_out[row], which mirrors it below) — one write per row, unlike the old design
    // which re-wrote V_out every idle cycle. o_acc is simultaneously reloaded with
    // the next row's seed.
    //
    // NOTE: o_out has no reset, so o_out[r] reads X until row r first completes —
    // the whole array only becomes defined at cycle 256, when softmax_done rises.
    // That is safe because every consumer (this project's TB and FSM_tiling) samples
    // on the done edge, but it is why the array shows all-X in a waveform viewer for
    // the duration of the first tile.
    always_ff @(posedge clk) begin
        if (Reset)
            for (int j = 0; j < 16; j++) o_acc[j] <= 16'h0000;
        else if (softermax_start)
            for (int j = 0; j < 16; j++) o_acc[j] <= o_in[0][j];
        else if (!softmax_done) begin
            if (counter == 4'd15) begin
                for (int j = 0; j < 16; j++)
                    o_out[row][j] <= o_next[j];
                if (row != 4'd15)
                    for (int j = 0; j < 16; j++) o_acc[j] <= o_in[row + 4'd1][j];
            end
            else
                for (int j = 0; j < 16; j++) o_acc[j] <= o_next[j];
        end
    end

    // V_out mirrors o_out. These used to be two separate register arrays written
    // with identical data on the same cycle -- 256x16 duplicated flops for nothing,
    // and a second array that read X until every row had completed. V_out is now a
    // pure alias, so it costs no storage and inherits o_out's defined-ness exactly.
    always_comb
        for (int r = 0; r < 16; r++)
            for (int c = 0; c < 16; c++)
                V_out[r][c] = o_out[r][c];

    always_ff @(posedge clk)
    begin
        if(Reset)
        begin
            // Idle after reset (softmax_done=1) until a start pulse launches a tile.
            max          <= 16'hFF80;   // -inf
            sum          <= 16'h0000;
            counter      <= 4'd0;
            row          <= 4'd0;
            softmax_done <= 1'b1;
        end
        else if(softermax_start)
        begin
            // Seed row 0 from its carried running state and start streaming.
            row          <= 4'd0;
            counter      <= 4'd0;
            max          <= m_in[0];
            sum          <= d_in[0];
            softmax_done <= 1'b0;
        end
        else if(!softmax_done)
        begin
            if(counter == 4'd15)
            begin
                // Last key of this row: next_max/next_sum already incorporate it,
                // so publish them as the row's result rather than registering them
                // into max/sum (which are reloaded for the next row instead).
                m_out[row] <= next_max;
                d_out[row] <= next_sum;
                if(row == 4'd15)
                    softmax_done <= 1'b1;      // whole tile complete; freeze
                else
                begin
                    row     <= row + 4'd1;
                    counter <= 4'd0;
                    max     <= m_in[row + 4'd1];
                    sum     <= d_in[row + 4'd1];
                end
            end
            else
            begin
                // incorporate logits[row][counter] into the running sum/max
                sum     <= next_sum;
                max     <= next_max;
                counter <= counter + 4'd1;
            end
        end
        // softmax_done: hold max, sum, counter, row (no further accumulation)
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

