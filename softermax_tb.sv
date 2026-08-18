`timescale 1ns / 1ps

// File-driven test for `softermax`.
//
// Reads 15 rows of 16 BF16 logits from input.txt and the matching Python
// softmax results (base-e, softmax_3pass) from output.txt. For each row the
// DUT runs its 16-cycle online max/sum recursion; the TB then computes the
// final probabilities in real arithmetic as 2^(x_i - dut.max) / dut.sum
// (the DUT's `logits_out` integer division is non-functional) and compares
// them element-wise against the reference, accumulating margin-of-error
// statistics.
//
// NOTE on expected error: the Python reference uses base-e exp; the DUT is a
// base-2 "softermax". Tail probabilities differ systematically between the
// two bases — the report quantifies exactly that margin.

module softermax_tb();

    localparam string IN_FILE   = "C:/Users/egypt/AI_Accelerator/python_verification/input.txt";
    localparam string OUT_FILE  = "C:/Users/egypt/AI_Accelerator/python_verification/output.txt";
    localparam int    N_ROWS    = 15;
    localparam real   TOLERANCE = 0.05;   // 5% relative-error threshold for counting

    logic         clk;
    logic         Reset;
    logic [15:0]  logits     [15:0];
    logic [15:0]  logits_out [15:0];

    softermax dut(
        .logits(logits),
        .clk(clk),
        .Reset(Reset),
        .logits_out(logits_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Golden data
    // ---------------------------------------------------------------
    logic [15:0] in_vecs  [N_ROWS][16];
    logic [15:0] ref_vecs [N_ROWS][16];

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

    // "0x4183" -> 16'h4183
    function automatic logic [15:0] parse_hex(input string s);
        string t;
        begin
            t = s;
            if (t.len() > 2 && t.substr(0, 1) == "0x")
                t = t.substr(2, t.len() - 1);
            return t.atohex();
        end
    endfunction

    task automatic read_hex_file(input string path,
                                 ref logic [15:0] dst [N_ROWS][16]);
        int    fd, row, col, n;
        string tok;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "cannot open %s", path);
            row = 0; col = 0;
            while (!$feof(fd) && row < N_ROWS) begin
                n = $fscanf(fd, "%s", tok);
                if (n == 1) begin
                    dst[row][col] = parse_hex(tok);
                    col++;
                    if (col == 16) begin col = 0; row++; end
                end
            end
            $fclose(fd);
            if (row != N_ROWS)
                $fatal(1, "%s: expected %0d rows of 16 values, got %0d complete rows",
                       path, N_ROWS, row);
            $display("loaded %0d rows from %s", N_ROWS, path);
        end
    endtask

    // ---------------------------------------------------------------
    // Error accumulators
    // ---------------------------------------------------------------
    real g_abs_sum, g_abs_max, g_rel_sum, g_rel_max;
    int  g_abs_max_row, g_abs_max_el, g_rel_max_row, g_rel_max_el;
    int  g_cmp_count, g_rel_count, g_over_tol;
    int  max_errors;

    // Hardware logits_out vs exact base-2 softmax accumulators
    real h_abs_sum, h_abs_max, h_rel_sum, h_rel_max;
    int  h_abs_max_row, h_abs_max_el, h_rel_max_row, h_rel_max_el;
    int  h_cmp_count, h_rel_count, h_over_tol;

    initial begin
        g_abs_sum = 0.0;  g_abs_max = 0.0;
        g_rel_sum = 0.0;  g_rel_max = 0.0;
        g_cmp_count = 0;  g_rel_count = 0;  g_over_tol = 0;
        max_errors = 0;
        h_abs_sum = 0.0;  h_abs_max = 0.0;
        h_rel_sum = 0.0;  h_rel_max = 0.0;
        h_cmp_count = 0;  h_rel_count = 0;  h_over_tol = 0;

        read_hex_file(IN_FILE,  in_vecs);
        read_hex_file(OUT_FILE, ref_vecs);

        for (int row = 0; row < N_ROWS; row++) begin : per_row
            real dut_max_r, dut_sum_r, true_max_r;
            real dut_out_r, ref_r, abs_err, rel_err;
            real row_abs_max, row_rel_max, prob_total;
            real exact2_num [16];      // 2^(x_i - true_max)
            real exact2_out [16];      // exact base-2 softmax reference
            real exact2_den;
            real hw_out_r, hw_abs, hw_rel, hw_prob_total, hw_row_rel_max;

            // Drive this row's logits
            for (int i = 0; i < 16; i++) logits[i] = in_vecs[row][i];

            // Reset one cycle, then 15 processing cycles (indices 1..15)
            Reset = 1'b1;
            @(posedge clk); #1;
            Reset = 1'b0;
            repeat (15) @(posedge clk);
            #1;

            dut_max_r = bf16_to_real(dut.max);
            dut_sum_r = bf16_to_real(dut.sum);

            // Sanity: dut.max must be the true row max (bit-exact check via value)
            true_max_r = bf16_to_real(in_vecs[row][0]);
            for (int i = 1; i < 16; i++)
                if (bf16_to_real(in_vecs[row][i]) > true_max_r)
                    true_max_r = bf16_to_real(in_vecs[row][i]);
            if (dut_max_r != true_max_r) begin
                $display("row %2d: FAIL max — dut.max=%h (%.4f), true max %.4f",
                         row, dut.max, dut_max_r, true_max_r);
                max_errors++;
            end

            // Element-wise compare: TB-side softmax vs reference file
            row_abs_max = 0.0;
            row_rel_max = 0.0;
            prob_total  = 0.0;
            for (int i = 0; i < 16; i++) begin
                dut_out_r = (2.0 ** (bf16_to_real(in_vecs[row][i]) - dut_max_r)) / dut_sum_r;
                ref_r     = bf16_to_real(ref_vecs[row][i]);
                prob_total += dut_out_r;

                abs_err = (dut_out_r > ref_r) ? (dut_out_r - ref_r) : (ref_r - dut_out_r);
                g_abs_sum += abs_err;
                g_cmp_count++;
                if (abs_err > g_abs_max) begin
                    g_abs_max = abs_err; g_abs_max_row = row; g_abs_max_el = i;
                end
                if (abs_err > row_abs_max) row_abs_max = abs_err;

                if (ref_r > 1e-9) begin
                    rel_err = abs_err / ref_r;
                    g_rel_sum += rel_err;
                    g_rel_count++;
                    if (rel_err > g_rel_max) begin
                        g_rel_max = rel_err; g_rel_max_row = row; g_rel_max_el = i;
                    end
                    if (rel_err > row_rel_max) row_rel_max = rel_err;
                    if (rel_err > TOLERANCE) g_over_tol++;
                end
            end

            $display("row %2d: max=%h (%.4f)  sum=%h (%.4f)  prob_total=%.4f  row_abs_max=%.6f  row_rel_max=%.2f%%",
                     row, dut.max, dut_max_r, dut.sum, dut_sum_r,
                     prob_total, row_abs_max, row_rel_max * 100.0);

            // ------- Hardware logits_out vs exact base-2 softmax -------
            exact2_den = 0.0;
            for (int i = 0; i < 16; i++) begin
                exact2_num[i] = 2.0 ** (bf16_to_real(in_vecs[row][i]) - true_max_r);
                exact2_den += exact2_num[i];
            end
            for (int i = 0; i < 16; i++)
                exact2_out[i] = exact2_num[i] / exact2_den;

            hw_prob_total  = 0.0;
            hw_row_rel_max = 0.0;
            for (int i = 0; i < 16; i++) begin
                hw_out_r = bf16_to_real(dut.logits_out[i]);
                hw_prob_total += hw_out_r;

                hw_abs = (hw_out_r > exact2_out[i]) ? (hw_out_r - exact2_out[i])
                                                    : (exact2_out[i] - hw_out_r);
                h_abs_sum += hw_abs;
                h_cmp_count++;
                if (hw_abs > h_abs_max) begin
                    h_abs_max = hw_abs; h_abs_max_row = row; h_abs_max_el = i;
                end

                if (exact2_out[i] > 1e-9) begin
                    hw_rel = hw_abs / exact2_out[i];
                    h_rel_sum += hw_rel;
                    h_rel_count++;
                    if (hw_rel > h_rel_max) begin
                        h_rel_max = hw_rel; h_rel_max_row = row; h_rel_max_el = i;
                    end
                    if (hw_rel > hw_row_rel_max) hw_row_rel_max = hw_rel;
                    if (hw_rel > TOLERANCE) h_over_tol++;
                end
            end
            $display("        HW logits_out: hw_prob_total=%.4f  hw_row_rel_max=%.2f%%",
                     hw_prob_total, hw_row_rel_max * 100.0);
        end

        // ---------------------------------------------------------------
        // Margin-of-error report
        // ---------------------------------------------------------------
        $display("");
        $display("=== Margin of Error (DUT base-2 online softmax vs Python base-e reference) ===");
        $display("rows processed        : %0d", N_ROWS);
        $display("elements compared     : %0d (relative-error stats on %0d nonzero refs)",
                 g_cmp_count, g_rel_count);
        $display("mean absolute error   : %.6f", g_abs_sum / g_cmp_count);
        $display("max  absolute error   : %.6f   (row %0d, elem %0d)",
                 g_abs_max, g_abs_max_row, g_abs_max_el);
        $display("mean relative error   : %.2f%%", (g_rel_sum / g_rel_count) * 100.0);
        $display("max  relative error   : %.2f%%   (row %0d, elem %0d)",
                 g_rel_max * 100.0, g_rel_max_row, g_rel_max_el);
        $display("elements > %.0f%% rel err : %0d / %0d",
                 TOLERANCE * 100.0, g_over_tol, g_rel_count);
        if (max_errors != 0)
            $display("WARNING: %0d row(s) had wrong dut.max — online max recursion broken", max_errors);

        $display("");
        $display("=== Hardware logits_out vs exact base-2 softmax ===");
        $display("elements compared     : %0d (relative-error stats on %0d nonzero refs)",
                 h_cmp_count, h_rel_count);
        $display("mean absolute error   : %.6f", h_abs_sum / h_cmp_count);
        $display("max  absolute error   : %.6f   (row %0d, elem %0d)",
                 h_abs_max, h_abs_max_row, h_abs_max_el);
        $display("mean relative error   : %.9f%%", (h_rel_sum / h_rel_count) * 100.0);
        $display("max  relative error   : %.9f%%   (row %0d, elem %0d)",
                 h_rel_max * 100.0, h_rel_max_row, h_rel_max_el);
        $display("elements > %.0f%% rel err : %0d / %0d",
                 TOLERANCE * 100.0, h_over_tol, h_rel_count);
        $display("");

        $finish;
    end

    // Watchdog
    initial begin
        #50_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
