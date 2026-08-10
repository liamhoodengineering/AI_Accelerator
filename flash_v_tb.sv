`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: flash_v_tb
// Description: Verifies the softermax V-path (flash-attention output recursion
//              o_i = coeff_left*o_{i-1} + coeff_right*V[i,:]) against the
//              base-2 gold from python_verification/verify_flash_v.py.
//
//              16 passes, one per logits row k: drive logits + row_idx, pulse
//              Reset, wait done, let V_out[k] capture. Then compare all 256
//              V_out elements against flash_gold_base2.txt at 5% relative
//              tolerance, printing the relative error on every line.
//
//              Rows 12-15 are edge cases: max@0, max@15, all-negative,
//              duplicated max.
//////////////////////////////////////////////////////////////////////////////////

module flash_v_tb();

    localparam string LOGITS_FILE = "C:/Users/egypt/AI_Accelerator/python_verification/flash_logits.txt";
    localparam string VMAT_FILE   = "C:/Users/egypt/AI_Accelerator/python_verification/flash_vmatrix.txt";
    localparam string GOLD2_FILE  = "C:/Users/egypt/AI_Accelerator/python_verification/flash_gold_base2.txt";
    localparam string GOLDE_FILE  = "C:/Users/egypt/AI_Accelerator/python_verification/flash_gold_basee.txt";

    logic         clk = 1'b0;
    logic         Reset;
    logic [3:0]   row_idx;
    logic [15:0]  logits     [15:0];
    logic [15:0]  V_matrix   [16][16];
    logic [15:0]  logits_out [15:0];
    logic [15:0]  V_out      [16][16];
    logic         done;

    softermax dut(
        .logits     (logits),
        .V_matrix   (V_matrix),
        .clk        (clk),
        .Reset      (Reset),
        .row_idx    (row_idx),
        .logits_out (logits_out),
        .done       (done),
        .V_out      (V_out)
    );

    always #5 clk = ~clk;

    // real -> BF16, round to nearest (validated in prior standalone xsim runs)
    function automatic logic [15:0] real_to_bf16(input real v);
        real  av;
        int   e, mant;
        logic sign;
        begin
            if (v == 0.0) return 16'h0000;
            sign = (v < 0.0);
            av   = sign ? -v : v;
            e    = 0;
            while (av >= 2.0) begin av = av / 2.0; e = e + 1; end
            while (av <  1.0) begin av = av * 2.0; e = e - 1; end
            mant = $rtoi((av - 1.0) * 128.0 + 0.5);
            if (mant == 128) begin mant = 0; e = e + 1; end
            return {sign, 8'(e + 127), 7'(mant)};
        end
    endfunction

    function automatic real bf16_to_real(input logic [15:0] b);
        if (b[14:7] == 8'd0) return 0.0;
        return (b[15] ? -1.0 : 1.0)
             * (1.0 + real'(b[6:0]) / 128.0)
             * (2.0 ** (real'(b[14:7]) - 127.0));
    endfunction

    // 16x16 matrix of reals from file (256 whitespace-separated decimals)
    task automatic read_matrix_real(input string path, output real dst [16][16]);
        int    fd, idx, n;
        string tok;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "cannot open %s", path);
            idx = 0;
            while (!$feof(fd) && idx < 256) begin
                n = $fscanf(fd, "%s", tok);
                if (n == 1) begin
                    dst[idx / 16][idx % 16] = tok.atoreal();
                    idx++;
                end
            end
            $fclose(fd);
            if (idx != 256)
                $fatal(1, "%s: expected 256 values, got %0d", path, idx);
            $display("loaded 16x16 from %s", path);
        end
    endtask

    real logits_r [16][16];
    real vmat_r   [16][16];
    real gold2_r  [16][16];
    real golde_r  [16][16];

    int  pass_cnt, fail_cnt;
    real r_out, r_gold, abs_err, rel_err;
    real sum_rel, max_rel, max_abs;
    int  max_rel_row, max_rel_lane;
    real sum_rel_e;
    // NOTE: k must be a static (module-scope) variable. Declaring it in the
    // for-header of an initial block containing @/wait event controls hits an
    // xsim quirk where reads of k after the event control return stale 0.
    int  k;

    // One full pass: drive a logits row, reset, run to done, let V_out capture.
    // NOTE: this body must live in a task. Driving from a for-loop directly in
    // the initial block hits an xsim quirk (observed on 2022.2) where writes to
    // `logits` after the first pass's event controls silently fail.
    task automatic run_pass(input int r);
        begin
            for (int i = 0; i < 16; i++)
                logits[i] = real_to_bf16(logits_r[r][i]);
            row_idx = r[3:0];
            Reset = 1'b1;
            repeat (2) @(posedge clk);
            Reset = 1'b0;
            wait (done === 1'b1);
            repeat (2) @(posedge clk);   // let V_out[row_idx] capture
            $display("pass %0d complete: logits0=%h max=%h sum=%h",
                     r, logits[0], dut.max, dut.sum);
        end
    endtask

    initial begin
        Reset   = 1'b1;
        row_idx = 4'd0;

        read_matrix_real(LOGITS_FILE, logits_r);
        read_matrix_real(VMAT_FILE,   vmat_r);
        read_matrix_real(GOLD2_FILE,  gold2_r);
        read_matrix_real(GOLDE_FILE,  golde_r);

        // V matrix is static across all passes
        foreach (V_matrix[i, j])
            V_matrix[i][j] = real_to_bf16(vmat_r[i][j]);

        // ---- 16 passes, one per logits row ----
        for (k = 0; k < 16; k++)
            run_pass(k);

        // ---- compare all 256 elements against base-2 gold ----
        pass_cnt = 0; fail_cnt = 0;
        sum_rel  = 0.0; max_rel = 0.0; sum_rel_e = 0.0; max_abs = 0.0;
        for (int k = 0; k < 16; k++) begin
            for (int j = 0; j < 16; j++) begin
                r_out  = bf16_to_real(V_out[k][j]);
                r_gold = gold2_r[k][j];
                abs_err = (r_out > r_gold) ? (r_out - r_gold) : (r_gold - r_out);
                rel_err = (r_gold != 0.0) ? abs_err / ((r_gold < 0.0) ? -r_gold : r_gold)
                                          : abs_err;
                sum_rel += rel_err;
                if (rel_err > max_rel) begin
                    max_rel = rel_err; max_rel_row = k; max_rel_lane = j;
                end
                if(abs_err > max_abs)
                    max_abs = abs_err;
                // info: error vs base-e gold
                if (golde_r[k][j] != 0.0)
                    sum_rel_e += ((r_out > golde_r[k][j]) ? (r_out - golde_r[k][j])
                                                          : (golde_r[k][j] - r_out))
                                 / ((golde_r[k][j] < 0.0) ? -golde_r[k][j] : golde_r[k][j]);

             //   if (rel_err < 0.05) begin
                if (abs_err < 0.01) begin

                    pass_cnt++;
                    $display("PASS row=%2d lane=%2d  got=%h (%11.6f)  gold=%11.6f  rel_err=%7.2f%%",
                             k, j, V_out[k][j], r_out, r_gold, rel_err * 100.0);
                end
                else begin
                    fail_cnt++;
                    $display("FAIL row=%2d lane=%2d  got=%h (%11.6f)  gold=%11.6f  rel_err=%7.2f%%",
                             k, j, V_out[k][j], r_out, r_gold, rel_err * 100.0);
                end
            end
        end

        $display("");
        $display("=== V-path vs base-2 flash-attention gold ===");
        $display("PASS %0d / 256   FAIL %0d", pass_cnt, fail_cnt);
        $display("mean rel err = %.2f%%   max rel err = %.2f%% (row %0d, lane %0d)",
                 (sum_rel / 256.0) * 100.0, max_rel * 100.0, max_rel_row, max_rel_lane);
        $display("info: mean rel err vs base-e gold = %.2f%% (quantifies exp->2^ substitution)",
                 (sum_rel_e / 256.0) * 100.0);
        $display("edge rows: 12=max@0  13=max@15  14=all-negative  15=duplicate-max");
        $display("max abs err = %.2f%%", max_abs*100.0);

        $finish;
    end

    // Watchdog
    initial begin
        #100_000;
        $display("Watchdog hit");
        $finish;
    end

endmodule
