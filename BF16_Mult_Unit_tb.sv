`timescale 1ns / 1ps

module BF16_Mult_Unit_tb(
    );

    logic [15:0] A;
    logic [15:0] B;
    logic [15:0] C;
    int          errors;
    
   

    BF16_Mult_Unit dut(
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
                $display("PASS  %-30s A=%h B=%h  C=%h  expected=%h",
                         label, a, b, C, exp_val);
            end
            else begin
                $display("FAIL  %-30s A=%h B=%h  C=%h  expected=%h",
                         label, a, b, C, exp_val);
                errors++;
            end
        end
    endtask

    initial begin
        A      = 16'h0000;
        B      = 16'h0000;
        errors = 0;

        // Zero cases
        check(16'h0000, 16'h0000, 16'h0000, "+0 x +0");
        check(16'h0000, 16'h8000, 16'h8000, "+0 x -0");
        check(16'h8000, 16'h8000, 16'h0000, "-0 x -0");
        check(16'h0000, 16'h4040, 16'h0000, "+0 x +3");
        check(16'h4040, 16'h0000, 16'h0000, "+3 x +0");
        check(16'h0000, 16'hC040, 16'h8000, "+0 x -3");

        // Sign combinations on nonzero values
        check(16'h4000, 16'h4040, 16'h40C0, "+2 x +3 = +6");
        check(16'hC000, 16'hC040, 16'h40C0, "-2 x -3 = +6");
        check(16'h4000, 16'hC040, 16'hC0C0, "+2 x -3 = -6");
        check(16'hC000, 16'h4040, 16'hC0C0, "-2 x +3 = -6");

        // Coverage extras
        check(16'h3F80, 16'h40A0, 16'h40A0, "identity 1 x 5 = 5");
        check(16'h4000, 16'h40A0, 16'h4120, "pow2 2 x 5 = 10");
        check(16'h3FC0, 16'h3FC0, 16'h4110, "renorm 1.5 x 1.5 = 2.25");

        if (errors == 0)
            $display("==== PASS: all BF16_Mult_Unit cases matched ====");
        else
            $display("==== FAIL: %0d BF16_Mult_Unit mismatches ====", errors);

        $finish;
    end

endmodule
