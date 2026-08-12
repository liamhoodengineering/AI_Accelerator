`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: sqrt_tb
// Description: Self-checking testbench for square_root.sv (integer dimension ->
//              CORDIC Q8.6 sqrt -> BF16). `dimension` is a compile-time parameter,
//              so a generate loop instantiates one DUT per test vector; after all
//              conversions assert `done` (watchdog-bounded), each BF16 result is
//              compared against $sqrt(dimension). The intermediate Q8.6 word is
//              probed to isolate a CORDIC error from a BF16-converter error.
//////////////////////////////////////////////////////////////////////////////////

module sqrt_tb();

    localparam int N = 16;
    // perfect squares | non-perfect squares | edges (0 = zero-guard, 16383 = max valid)
    localparam int DIMS [N] = '{ 1, 4, 16, 64, 256, 1024, 4096,
                                 2, 3, 50, 100, 200, 1000, 5000,
                                 0, 16383 };

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic [15:0] dim_sqrt_bus  [N];   // BF16 outputs
    logic [N-1:0] done_bus;           // packed so &done_bus works
    logic [13:0] sqrt_op_probe [N];   // intermediate Q8.6 (stage isolation)

    genvar gi;
    generate
        for (gi = 0; gi < N; gi++) begin : dut_gen
            square_root #(.dimension(DIMS[gi])) dut (
                .clk      (clk),
                .dim_sqrt (dim_sqrt_bus[gi]),
                .done     (done_bus[gi])
            );
            // gi is elaboration-constant here, so this hierarchical probe is legal
            assign sqrt_op_probe[gi] = dut.sqrt_op_output;
        end
    endgenerate

    // BF16 (1 sign + 8 exp + 7 mantissa) -> real (helper mirrors flash_v_tb.sv)
    function automatic real bf16_to_real(input logic [15:0] b);
        if (b[14:7] == 8'd0) return 0.0;
        return (b[15] ? -1.0 : 1.0)
             * (1.0 + real'(b[6:0]) / 128.0)
             * (2.0 ** (real'(b[14:7]) - 127.0));
    endfunction

    int  pass_cnt, fail_cnt;
    real got, expv, abs_err, tol;
    int  fixed_got, fixed_exp;

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        // Wait for every conversion to finish (watchdog below bounds a hang).
        wait (&done_bus);
        #1;

        $display("=== square_root BF16 self-check (N=%0d) ===", N);
        for (int i = 0; i < N; i++) begin
            got       = bf16_to_real(dim_sqrt_bus[i]);
            expv      = $sqrt(real'(DIMS[i]));
            abs_err   = (got > expv) ? (got - expv) : (expv - got);
            // Q8.6 truncation (<=1/64) + BF16 quantization (~value*2^-7), plus slack.
            tol       = (1.0 / 64.0) + expv * (2.0 ** -7) + 1.0e-6;

            fixed_got = sqrt_op_probe[i];
            fixed_exp = $floor($sqrt(real'(DIMS[i]) * (2.0 ** 12)));

            if (DIMS[i] == 0) begin
                // zero guard must emit an exact BF16 +0.0
                if (dim_sqrt_bus[i] == 16'h0000) pass_cnt++; else fail_cnt++;
                $display("%s dim=%5d  got=%h  expected 0x0000 (zero guard)  sqrt_op=%0d",
                         (dim_sqrt_bus[i] == 16'h0000) ? "PASS" : "FAIL",
                         DIMS[i], dim_sqrt_bus[i], fixed_got);
            end
            else begin
                if (abs_err <= tol) pass_cnt++; else fail_cnt++;
                $display("%s dim=%5d  got=%h (%9.5f)  exp=%9.5f  abs_err=%8.5f (tol=%7.5f)  sqrt_op=%0d%s",
                         (abs_err <= tol) ? "PASS" : "FAIL",
                         DIMS[i], dim_sqrt_bus[i], got, expv, abs_err, tol, fixed_got,
                         (fixed_got != fixed_exp) ?
                            $sformatf("  <CORDIC MISMATCH exp=%0d>", fixed_exp) : "");
            end
        end

        $display("");
        $display("=== RESULT: PASS %0d / %0d   FAIL %0d ===", pass_cnt, N, fail_cnt);
        $finish;
    end

    // Watchdog: if any instance never asserts done, report which and stop.
    initial begin
        #200000;
        $display("WATCHDOG: not all conversions completed. done_bus = %b", done_bus);
        $finish;
    end

endmodule
