`timescale 1ns / 1ps

module BF16_Add_Unit_tb(
    );

    logic [15:0] A;
    logic [15:0] B;
    logic [15:0] C;
    int          errors;

    BF16_Add_Unit dut(
        .A(A),
        .B(B),
        .C(C));

    task automatic check(input logic [15:0] a,
                         input logic [15:0] b,
                         input logic [15:0] exp_val,
                         input string       label);
        begin
            A = a;
            B = b;
            #1;
            if (C === exp_val) begin
                $display("PASS  %-32s A=%h B=%h  C=%h  expected=%h",
                         label, a, b, C, exp_val);
            end
            else begin
                $display("FAIL  %-32s A=%h B=%h  C=%h  expected=%h",
                         label, a, b, C, exp_val);
                errors++;
            end
        end
    endtask

    initial begin
        A      = 16'h0000;
        B      = 16'h0000;
        errors = 0;

        // Zero cases (short-circuit path)
        check(16'h0000, 16'h0000, 16'h0000, "+0 + +0");
        check(16'h0000, 16'h8000, 16'h8000, "+0 + -0 (returns B)");
        check(16'h0000, 16'h40A0, 16'h40A0, "+0 + +5");
        check(16'h4040, 16'h0000, 16'h4040, "+3 + +0");

        // Same-sign, no carry-out
        check(16'h3F80, 16'h3F80, 16'h4000, "1 + 1 = 2");

        // Same-sign with carry-out (renormalize: exp+1, shift mant right)
        check(16'h3FC0, 16'h3FC0, 16'h4040, "1.5 + 1.5 = 3");

        // Opposite sign, exact cancellation -> +0
        check(16'h4040, 16'hC040, 16'h0000, "3 + (-3) = 0");

        // Opposite sign, requires left-shift renormalization
        check(16'h4080, 16'hC040, 16'h3F80, "4 + (-3) = 1");

        // Large + tiny, both same sign
        check(16'h4080, 16'h3F80, 16'h40A0, "4 + 1 = 5");

        // Same-sign with negatives
        check(16'hC000, 16'hC040, 16'hC0A0, "-2 + -3 = -5");

        // Swap order: B is bigger
        check(16'h3F80, 16'h4040, 16'h4080, "1 + 3 = 4 (B bigger)");

        // -------------------- Additional 15 cases --------------------

        // Same-sign, equal-exponent adds with carry-out
        check(16'h4020, 16'h4020, 16'h40A0, "2.5 + 2.5 = 5");
        check(16'h3F00, 16'h3F00, 16'h3F80, "0.5 + 0.5 = 1");
        check(16'h3E80, 16'h3E80, 16'h3F00, "0.25 + 0.25 = 0.5");
        check(16'h4040, 16'h4040, 16'h40C0, "3 + 3 = 6");

        // Same-sign, differing exponents (align + shift)
        check(16'h3F80, 16'h3F00, 16'h3FC0, "1 + 0.5 = 1.5");
        check(16'h4120, 16'h40C0, 16'h4180, "10 + 6 = 16");
        check(16'h4060, 16'h4090, 16'h4100, "3.5 + 4.5 = 8");
        check(16'h3FE0, 16'h3FC0, 16'h4050, "1.75 + 1.5 = 3.25");

        // Same-sign, large magnitudes
        check(16'h4100, 16'h4100, 16'h4180, "8 + 8 = 16");
        check(16'h42C8, 16'h42C8, 16'h4348, "100 + 100 = 200");

        // Opposite signs — subtraction path
        check(16'h4000, 16'hBF80, 16'h3F80, "2 + (-1) = 1");
        check(16'hC0A0, 16'h4040, 16'hC000, "-5 + 3 = -2");
        check(16'h3F80, 16'hBF00, 16'h3F00, "1 + (-0.5) = 0.5");

        // Opposite signs, exact cancellation (A < B)
        check(16'hBF80, 16'h3F80, 16'h0000, "-1 + 1 = 0");

        // Opposite signs, unequal magnitudes, negative result (large mantissa)
        check(16'hC2C8, 16'h4248, 16'hC248, "-100 + 50 = -50");

        if (errors == 0)
            $display("==== PASS: BF16_Add_Unit all cases matched ====");
        else
            $display("==== FAIL: %0d BF16_Add_Unit mismatches ====", errors);

        $finish;
    end

endmodule
