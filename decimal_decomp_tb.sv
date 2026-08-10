`timescale 1ns / 1ps

// Testbench for decimal_decomp (softermax.sv).
//
// DUT contract: given a BF16 value, split its MAGNITUDE into
//   new_int     [3:0]  — integer part, i.e. floor(|x|) mod 16
//   new_decimal [11:0] — fractional part in Q0.12, truncated
// The sign bit is ignored (the caller feeds |delta| semantics).
//
// Known limitation (verified here as modeled behavior, flagged in the log):
// new_int is 4 bits, so |x| >= 16 wraps modulo 16 instead of saturating.

module decimal_decomp_tb();

    logic [15:0] matrix_a;
    logic [3:0]  new_int;
    logic [11:0] new_decimal;

    int errors;

    decimal_decomp dut (
        .matrix_a    (matrix_a),
        .new_int     (new_int),
        .new_decimal (new_decimal)
    );

    // bf16 -> real magnitude (sign ignored; exp==0 treated as zero)
    function automatic real bf16_mag_to_real(input logic [15:0] b);
        logic [7:0] exp_b;
        logic [6:0] mant_b;
        begin
            exp_b  = b[14:7];
            mant_b = b[6:0];
            if (exp_b == 8'd0)
                return 0.0;
            return (1.0 + (real'(mant_b) / 128.0)) * (2.0 ** (real'(exp_b) - 127.0));
        end
    endfunction

    // Golden model: t = floor(|x| * 4096); int = bits[15:12] of t, frac = bits[11:0].
    // Exact for bf16 (8 significant bits) and mirrors the DUT's shift/truncate.
    function automatic logic [15:0] golden(input logic [15:0] b);
        real         v;
        longint      t;
        logic [3:0]  gi;
        logic [11:0] gf;
        begin
            v  = bf16_mag_to_real(b);
            t  = longint'($floor(v * 4096.0));
            gi = t[15:12];
            gf = t[11:0];
            return {gi, gf};
        end
    endfunction

    task automatic check(input logic [15:0] a, input string label);
        logic [3:0]  exp_int;
        logic [11:0] exp_frac;
        begin
            matrix_a = a;
            #1;
            {exp_int, exp_frac} = golden(a);
            if (new_int === exp_int && new_decimal === exp_frac)
                $display("PASS  %-28s a=%h (%.6f)  int=%0d  frac=0x%03h",
                         label, a, bf16_mag_to_real(a), new_int, new_decimal);
            else begin
                $display("FAIL  %-28s a=%h (%.6f)  int=%0d frac=0x%03h  expected int=%0d frac=0x%03h",
                         label, a, bf16_mag_to_real(a),
                         new_int, new_decimal, exp_int, exp_frac);
                errors++;
            end
        end
    endtask

    logic [15:0] rand_val;
    logic [7:0]  rand_exp;

    initial begin
        errors = 0;

        // ---- Directed vectors ----
        check(16'h0000, "zero");
        check(16'h3F80, "1.0   -> int 1, frac 0");
        check(16'h3FC0, "1.5   -> int 1, frac 0x800");
        check(16'h4000, "2.0   -> int 2, frac 0");
        check(16'h4040, "3.0   -> int 3, frac 0");
        check(16'h4110, "9.0   -> int 9, frac 0");
        check(16'h3F00, "0.5   -> int 0, frac 0x800");
        check(16'h3E80, "0.25  -> int 0, frac 0x400");
        check(16'h3D80, "0.0625-> int 0, frac 0x100");
        check(16'h4170, "15.0  -> int 15, frac 0");
        check(16'h4172, "15.125-> int 15, frac 0x200");
        check(16'h417F, "15.9375 (max < 16)");
        check(16'h3C00, "2^-7  -> int 0, frac 0x020");
        check(16'h3980, "2^-12 -> int 0, frac 0x001");
        check(16'h3900, "2^-13 -> truncates to 0");

        // Sign-agnostic: negative inputs decompose their magnitude
        check(16'hBFC0, "-1.5  (sign ignored)");
        check(16'hC110, "-9.0  (sign ignored)");

        // 4-bit wrap above 16 — modeled (mod 16), flagged as known limitation
        $display("--- known-limitation region: |x| >= 16 wraps mod 16 ---");
        check(16'h4180, "16.0  -> wraps to int 0");
        check(16'h4188, "17.0  -> wraps to int 1");
        check(16'h41F8, "31.0  -> wraps to int 15");

        // ---- Random sweep: 100 values with exponents in [115, 133] ----
        $display("--- random sweep (100 vectors, exp 115..133) ---");
        for (int n = 0; n < 100; n++) begin
            rand_exp = 8'd115 + ($urandom() % 19);
            rand_val = {1'b0, rand_exp, $urandom() & 7'h7F};
            check(rand_val, "random");
        end

        $display("");
        if (errors == 0)
            $display("==== PASS: decimal_decomp all cases matched ====");
        else
            $display("==== FAIL: %0d decimal_decomp mismatches ====", errors);

        $finish;
    end

endmodule
