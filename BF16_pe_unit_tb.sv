`timescale 1ns / 1ps

module BF16_pe_unit_tb(
    );

    logic [15:0] A, B, accumulate, S;
    int          errors;

    BF16_pe_unit dut(
        .A(A),
        .B(B),
        .accumulate(accumulate),
        .S(S));

    task automatic check(input logic [15:0] a,
                         input logic [15:0] b,
                         input logic [15:0] acc,
                         input logic [15:0] exp_val,
                         input string       label);
        begin
            A          = a;
            B          = b;
            accumulate = acc;
            #1;
            if (S === exp_val) begin
                $display("PASS  %-30s A=%h B=%h ACC=%h  S=%h  expected=%h",
                         label, a, b, acc, S, exp_val);
            end
            else begin
                $display("FAIL  %-30s A=%h B=%h ACC=%h  S=%h  expected=%h",
                         label, a, b, acc, S, exp_val);
                errors++;
            end
        end
    endtask

    initial begin
        errors = 0;

        // Case 1: A>0, B>0, multiplier carry-out (1.5 * 1.5 = 2.25)
        check(16'h3FC0, 16'h3FC0, 16'h0000, 16'h4110, "C1a 1.5*1.5 + 0");
        check(16'h3FC0, 16'h3FC0, 16'h3FC0, 16'h4070, "C1b 1.5*1.5 + 1.5");
        check(16'h3FC0, 16'h3FC0, 16'hBF80, 16'h3FA0, "C1c 1.5*1.5 + (-1)");

        // Case 2: A>0, B>0, no multiplier carry (1 * 2 = 2)
        check(16'h3F80, 16'h4000, 16'h0000, 16'h4000, "C2a 1*2 + 0");
        check(16'h3F80, 16'h4000, 16'h3F80, 16'h4040, "C2b 1*2 + 1");
        check(16'h3F80, 16'h4000, 16'hBF80, 16'h3F80, "C2c 1*2 + (-1)");

        // Case 3: opposite signs, equal magnitudes (2 * -2 = -4)
        check(16'h4000, 16'hC000, 16'h0000, 16'hC080, "C3a 2*-2 + 0");
        check(16'h4000, 16'hC000, 16'h4080, 16'h0000, "C3b 2*-2 + 4 (cancel)");
        check(16'h4000, 16'hC000, 16'hC080, 16'hC100, "C3c 2*-2 + (-4)");

        // Case 4: opposite signs, |A| > |B| (4 * -1 = -4)
        check(16'h4080, 16'hBF80, 16'h0000, 16'hC080, "C4a 4*-1 + 0");
        check(16'h4080, 16'hBF80, 16'h3F80, 16'hC040, "C4b 4*-1 + 1");
        check(16'h4080, 16'hBF80, 16'hBF80, 16'hC0A0, "C4c 4*-1 + (-1)");

        // Case 5: opposite signs, |A| < |B| (1 * -4 = -4)
        check(16'h3F80, 16'hC080, 16'h0000, 16'hC080, "C5a 1*-4 + 0");
        check(16'h3F80, 16'hC080, 16'h4080, 16'h0000, "C5b 1*-4 + 4 (cancel)");
        check(16'h3F80, 16'hC080, 16'hBF80, 16'hC0A0, "C5c 1*-4 + (-1)");

        // Case 6: one input is zero (A=0, B nonzero)
        check(16'h0000, 16'h40A0, 16'h0000, 16'h0000, "C6a 0*5 + 0");
        check(16'h0000, 16'h40A0, 16'h3F80, 16'h3F80, "C6b 0*5 + 1");
        check(16'h0000, 16'h40A0, 16'hBF80, 16'hBF80, "C6c 0*5 + (-1)");

        // Case 7: both inputs zero
        check(16'h0000, 16'h0000, 16'h0000, 16'h0000, "C7a 0*0 + 0");
        check(16'h0000, 16'h0000, 16'h4040, 16'h4040, "C7b 0*0 + 3");
        check(16'h0000, 16'h0000, 16'hC040, 16'hC040, "C7c 0*0 + (-3)");

        if (errors == 0)
            $display("==== PASS: BF16_pe_unit all 21 cases matched ====");
        else
            $display("==== FAIL: %0d BF16_pe_unit mismatches ====", errors);

        $finish;
    end

endmodule
