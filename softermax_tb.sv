`timescale 1ns / 1ps

// Directed test for `softermax` driving the 16-element bf16 logits vector
// supplied by the user. `max` is checked bit-exact; `sum` is checked against
// the EXACT online-softmax reference with a 5% relative tolerance to absorb
// the polynomial approximation in `fractional_bit_shift` and bf16 round-off.

module softermax_tb();

    logic         clk;
    logic         Reset;
    logic [15:0]  logits     [15:0];
    logic [15:0]  logits_out [15:0];

    int errors;

    softermax dut(
        .logits(logits),
        .clk(clk),
        .Reset(Reset),
        .logits_out(logits_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Stimulus and reference tables (index 0 = reset state)
    // ---------------------------------------------------------------
    logic [15:0] stim_logits [0:15];
    logic [15:0] exp_max     [0:15];
    logic [15:0] exp_sum     [0:15];   // closest bf16 to the real value (display only)
    real         exp_sum_r   [0:15];   // floating-point reference for tolerance check

    // bf16 -> real conversion (treats exp==0 as zero)
    function automatic real bf16_to_real(input logic [15:0] b);
        logic       sign_b;
        logic [7:0] exp_b;
        logic [6:0] mant_b;
        real        v;
        begin
            sign_b = b[15];
            exp_b  = b[14:7];
            mant_b = b[6:0];
            if (exp_b == 8'd0)
                v = 0.0;
            else begin
                v = (1.0 + (real'(mant_b) / 128.0)) * (2.0 ** (real'(exp_b) - 127.0));
                if (sign_b) v = -v;
            end
            return v;
        end
    endfunction

    task automatic check_cycle(input int k);
        real got_r;
        real exp_r;
        real rel_err;
        begin
            $display("--- cycle %0d ---", k);
            $display("  REG    counter=%0d  max=%h  sum=%h",
                     dut.counter, dut.max, dut.sum);
            $display("  COMB   delta=%h  delta_int=%0d  delta_frac=%h pow2_neg_delta=%h  frac_out=%h  pow2_neg_delta_full=%h  new_max=%b",
                     dut.delta, dut.delta_int, dut.delta_frac,
                     dut.pow2_neg_delta, dut.frac_out, dut.pow2_neg_delta_full,
                     dut.new_max);

            // ----- max: bit-exact -----
            if (dut.max === exp_max[k])
                $display("  PASS   max = %h", dut.max);
            else begin
                $display("  FAIL   max = %h  (expected %h)", dut.max, exp_max[k]);
                errors++;
            end

            // ----- sum: 5% relative tolerance vs EXACT reference -----
            got_r = bf16_to_real(dut.sum);
            exp_r = exp_sum_r[k];
            rel_err = (got_r - exp_r) / exp_r;
            if (rel_err < 0.0) rel_err = -rel_err;
            if (rel_err < 0.05)
                $display("  PASS   sum = %h (%.4f)  vs ref %h (%.4f)  rel_err=%.2f%%",
                         dut.sum, got_r, exp_sum[k], exp_r, rel_err * 100.0);
            else begin
                $display("  FAIL   sum = %h (%.4f)  vs ref %h (%.4f)  rel_err=%.2f%%",
                         dut.sum, got_r, exp_sum[k], exp_r, rel_err * 100.0);
                errors++;
            end
        end
    endtask

    initial begin
        errors = 0;

        // -------- stimulus (user-supplied 16-element bf16 vector) --------
        stim_logits[0]  = 16'hBFA8;   // -1.3125
        stim_logits[1]  = 16'h402C;   // +2.6875
        stim_logits[2]  = 16'h3EE0;   // +0.4375
        stim_logits[3]  = 16'hC060;   // -3.5
        stim_logits[4]  = 16'h3FF0;   // +1.875
        stim_logits[5]  = 16'hBF30;   // -0.6875
        stim_logits[6]  = 16'h4048;   // +3.125
        stim_logits[7]  = 16'h3D80;   // +0.0625
        stim_logits[8]  = 16'hC00C;   // -2.1875
        stim_logits[9]  = 16'h3FA8;   // +1.3125
        stim_logits[10] = 16'hBE40;   // -0.1875
        stim_logits[11] = 16'h4080;   // +4.0
        stim_logits[12] = 16'hBF80;   // -1.0
        stim_logits[13] = 16'h400C;   // +2.1875
        stim_logits[14] = 16'hC098;   // -4.75
        stim_logits[15] = 16'h3F50;   // +0.8125

        // -------- expected `max` after each cycle (k=0 is post-Reset) --------
        exp_max[0]  = 16'hBFA8;   // -1.3125 (reset)
        exp_max[1]  = 16'h402C;   // +2.6875
        exp_max[2]  = 16'h402C;
        exp_max[3]  = 16'h402C;
        exp_max[4]  = 16'h402C;
        exp_max[5]  = 16'h402C;
        exp_max[6]  = 16'h4048;   // +3.125
        exp_max[7]  = 16'h4048;
        exp_max[8]  = 16'h4048;
        exp_max[9]  = 16'h4048;
        exp_max[10] = 16'h4048;
        exp_max[11] = 16'h4080;   // +4.0
        exp_max[12] = 16'h4080;
        exp_max[13] = 16'h4080;
        exp_max[14] = 16'h4080;
        exp_max[15] = 16'h4080;

        // -------- expected `sum`: closest bf16 (display) + real (tolerance) --------
        exp_sum[0]  = 16'h3F80; exp_sum_r[0]  = 1.0000;
        exp_sum[1]  = 16'h3F88; exp_sum_r[1]  = 1.0625;
        exp_sum[2]  = 16'h3FA3; exp_sum_r[2]  = 1.2727;
        exp_sum[3]  = 16'h3FA5; exp_sum_r[3]  = 1.2864;
        exp_sum[4]  = 16'h3FED; exp_sum_r[4]  = 1.8548;
        exp_sum[5]  = 16'h3FFA; exp_sum_r[5]  = 1.9512;
        exp_sum[6]  = 16'h401C; exp_sum_r[6]  = 2.4414;
        exp_sum[7]  = 16'h4024; exp_sum_r[7]  = 2.5610;
        exp_sum[8]  = 16'h4026; exp_sum_r[8]  = 2.5862;
        exp_sum[9]  = 16'h4038; exp_sum_r[9]  = 2.8708;
        exp_sum[10] = 16'h403E; exp_sum_r[10] = 2.9715;
        exp_sum[11] = 16'h4028; exp_sum_r[11] = 2.6206;
        exp_sum[12] = 16'h402A; exp_sum_r[12] = 2.6519;
        exp_sum[13] = 16'h403C; exp_sum_r[13] = 2.9365;
        exp_sum[14] = 16'h403C; exp_sum_r[14] = 2.9388;
        exp_sum[15] = 16'h4043; exp_sum_r[15] = 3.0485;

        // -------- drive into DUT --------
        for (int i = 0; i < 16; i++) logits[i] = stim_logits[i];

        // -------- Reset --------
        Reset = 1'b1;
        @(posedge clk); #1;
        $display("=== After Reset ===");
        $display("  REG    counter=%0d  max=%h  sum=%h",
                 dut.counter, dut.max, dut.sum);
        if (dut.max === exp_max[0] && dut.sum === exp_sum[0] && dut.counter === 4'd1)
            $display("  PASS   reset state");
        else begin
            $display("  FAIL   reset state  (max=%h sum=%h counter=%0d, expected max=%h sum=%h counter=1)",
                     dut.max, dut.sum, dut.counter, exp_max[0], exp_sum[0]);
            errors++;
        end

        // -------- 15 post-Reset cycles --------
        Reset = 1'b0;
        for (int k = 1; k <= 15; k++) begin
            @(posedge clk); #1;
            check_cycle(k);
        end

        $display("");
        if (errors == 0)
            $display("==== PASS: softermax matches EXACT reference within 5%% across 16 logits ====");
        else
            $display("==== FAIL: %0d mismatch(es) vs EXACT reference ====", errors);

        $finish;
    end

endmodule
