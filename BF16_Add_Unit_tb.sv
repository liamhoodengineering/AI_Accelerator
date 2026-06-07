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

        if (errors == 0)
            $display("==== PASS: BF16_Add_Unit all cases matched ====");
        else
            $display("==== FAIL: %0d BF16_Add_Unit mismatches ====", errors);

        $finish;
    end

endmodule
