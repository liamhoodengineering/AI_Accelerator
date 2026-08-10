`timescale 1ns / 1ps

module BF16_DIV_Unit_tb();

    logic [15:0] A;
    logic [15:0] B;
    logic [15:0] C;

    BF16_DIV_Unit dut (.A(A), .B(B), .C(C));

    // Task: apply one vector and report pass/fail
    task automatic check(input [15:0] a_in, b_in, expected, input string label);
        A = a_in;
        B = b_in;
        #1;
        $display("%-24s  A=0x%04h  B=0x%04h  C=0x%04h  expected=0x%04h  %s",
                 label, a_in, b_in, C, expected,
                 (C === expected) ? "PASS" : "FAIL");
    endtask

    initial begin
        // Vector 1 — identity
        check(16'h3F80, 16'h3F80, 16'h3F80, "1.0 / 1.0 = 1.0");

        // Vector 2 — trivial integer
        check(16'h4000, 16'h3F80, 16'h4000, "2.0 / 1.0 = 2.0");

        // Vector 3 — exponent subtraction
        check(16'h4080, 16'h4000, 16'h4000, "4.0 / 2.0 = 2.0");

        // Vector 4 — result < 1
        check(16'h3F80, 16'h4000, 16'h3F00, "1.0 / 2.0 = 0.5");

        // Vector 5 — fractional result (expected to FAIL — mantissa div is integer)
        check(16'h4040, 16'h4000, 16'h3FC0, "3.0 / 2.0 = 1.5");

        // Vector 6 — same value
        check(16'h40A0, 16'h40A0, 16'h3F80, "5.0 / 5.0 = 1.0");

        // Vector 7 — negative dividend
        check(16'hC000, 16'h3F80, 16'hC000, "-2.0 / 1.0 = -2.0");

        // Vector 8 — negative divisor
        check(16'h4000, 16'hBF80, 16'hC000, "2.0 / -1.0 = -2.0");

        // Vector 9 — both negative
        check(16'hC0C0, 16'hC000, 16'h4040, "-6.0 / -2.0 = 3.0");

        // Vector 10 — zero dividend
        check(16'h0000, 16'h3F80, 16'h0000, "0.0 / 1.0 = 0.0");

        // Vector 11 — divide by zero (documents DUT quirk: returns signed zero)
        check(16'h3F80, 16'h0000, 16'h0000, "1.0 / 0.0 (DUT: returns 0)");

        // -------------------- Additional 15 harder vectors --------------------
        // BF16 encoding key: {sign[15], exp[14:7], mantissa[6:0]}, bias 127,
        // implicit leading 1 on the mantissa.

        // Vector 12 — 7.5 / 3.0 = 2.5
        check(16'h40F0, 16'h4040, 16'h4020, "7.5 / 3.0 = 2.5");

        // Vector 13 — 12.5 / 2.5 = 5.0
        check(16'h4148, 16'h4020, 16'h40A0, "12.5 / 2.5 = 5.0");

        // Vector 14 — 100.0 / 10.0 = 10.0
        check(16'h42C8, 16'h4120, 16'h4120, "100.0 / 10.0 = 10.0");

        // Vector 15 — 0.1875 / 0.75 = 0.25 (subunit / subunit)
        check(16'h3E40, 16'h3F40, 16'h3E80, "0.1875 / 0.75 = 0.25");

        // Vector 16 — 0.125 / 0.0625 = 2.0 (small magnitudes)
        check(16'h3E00, 16'h3D80, 16'h4000, "0.125 / 0.0625 = 2.0");

        // Vector 17 — 1000.0 / 8.0 = 125.0 (large / small integer)
        check(16'h447A, 16'h4100, 16'h42FA, "1000.0 / 8.0 = 125.0");

        // Vector 18 — 13.5 / 3.0 = 4.5
        check(16'h4158, 16'h4040, 16'h4090, "13.5 / 3.0 = 4.5");

        // Vector 19 — 11.0 / 4.0 = 2.75
        check(16'h4130, 16'h4080, 16'h4030, "11.0 / 4.0 = 2.75");

        // Vector 20 — -7.5 / 2.5 = -3.0 (negative dividend, exact)
        check(16'hC0F0, 16'h4020, 16'hC040, "-7.5 / 2.5 = -3.0");

        // Vector 21 — -0.75 / 0.25 = -3.0 (subunit negative dividend)
        check(16'hBF40, 16'h3E80, 16'hC040, "-0.75 / 0.25 = -3.0");

        // Vector 22 — 256.0 / 16.0 = 16.0 (large powers of two)
        check(16'h4380, 16'h4180, 16'h4180, "256.0 / 16.0 = 16.0");

        // Vector 23 — -32.0 / -4.0 = 8.0 (both negative, exact)
        check(16'hC200, 16'hC080, 16'h4100, "-32.0 / -4.0 = 8.0");

        // Vector 24 — 1.5 / 0.75 = 2.0 (fraction divided by fraction)
        check(16'h3FC0, 16'h3F40, 16'h4000, "1.5 / 0.75 = 2.0");

        // Vector 25 — 21.0 / 7.0 = 3.0 (multi-bit mantissa, exact result)
        check(16'h41A8, 16'h40E0, 16'h4040, "21.0 / 7.0 = 3.0");

        // Vector 26 — 5.0 / 3.0 ≈ 1.6640625 (inexact — nearest BF16 is 0x3FD5)
        check(16'h40A0, 16'h4040, 16'h3FD5, "5.0 / 3.0 ~= 1.664...");

        $finish;
    end

endmodule
