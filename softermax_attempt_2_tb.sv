`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: softermax_attempt_2_tb
// Description: File-driven softermax test. input.txt / output.txt hold decimal
//              real values (one row of 16); tokens are converted to BF16 with
//              round-to-nearest.
//
// NOTE on data precision: the current .txt values are FP16-exact, not
// BF16-exact (generator used float16). real_to_bf16 quantizes each value to
// the nearest BF16 (<= 1 ULP ~ 0.4% error), absorbed by the 5% compare band.
// Regenerating the files from true bfloat16 tensors is a future Python fix.
//////////////////////////////////////////////////////////////////////////////////

module softermax_attempt_2_tb();

    localparam string IN_FILE  = "C:/Users/egypt/AI_Accelerator/python_verification/input.txt";
    localparam string OUT_FILE = "C:/Users/egypt/AI_Accelerator/python_verification/output.txt";
    localparam int    N_ROWS   = 1;

    logic         clk = 1'b0;
    logic         Reset;
    logic [15:0]  logits     [15:0];
    logic [15:0]  logits_out [15:0];

    softermax dut(
        .logits(logits),
        .clk(clk),
        .Reset(Reset),
        .logits_out(logits_out)
    );

    always #5 clk = ~clk;

    // real -> BF16, round to nearest (validated standalone in xsim:
    // exhaustive round-trip over exp [100,140], overflow + zero edge cases)
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
            mant = $rtoi((av - 1.0) * 128.0 + 0.5);          // round nearest
            if (mant == 128) begin mant = 0; e = e + 1; end  // mantissa overflow
            return {sign, 8'(e + 127), 7'(mant)};
        end
    endfunction

    // BF16 -> real (exp==0 treated as zero)
    function automatic real bf16_to_real(input logic [15:0] b);
        if (b[14:7] == 8'd0) return 0.0;
        return (b[15] ? -1.0 : 1.0)
             * (1.0 + real'(b[6:0]) / 128.0)
             * (2.0 ** (real'(b[14:7]) - 127.0));
    endfunction

    task automatic read_file(input string path,
                             output logic [15:0] dst [16]);
        int    fd, col, n;
        string tok;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "cannot open %s", path);
            col = 0;
            while (!$feof(fd) && col < 16) begin
                n = $fscanf(fd, "%s", tok);
                if (n == 1) begin
                    dst[col] = real_to_bf16(tok.atoreal());
                    col++;
                end
            end
            $fclose(fd);
            if (col != 16)
                $fatal(1, "%s: expected 16 values, got %0d", path, col);
        end
    endtask

    logic [15:0] in_vecs  [16];
    logic [15:0] ref_vecs [16];

    real r_out, r_ref;

    initial begin
        Reset = 1'b1;
        
       
        read_file(IN_FILE, in_vecs);
        $display("sanity: in_vecs[0] = %h (%.6f)  -- expect bf28 (-0.656250)",
                 in_vecs[0], bf16_to_real(in_vecs[0]));
        foreach (logits[i])
            logits[15-i] = in_vecs[i];
        repeat (2) @(posedge clk);
         Reset = 1'b0;
        repeat (30) @(posedge clk);

        read_file(OUT_FILE, ref_vecs);
        // logits were driven reversed (logits[15-i] = in_vecs[i]), so DUT output
        // lane i corresponds to reference element 15-i.
        foreach (logits_out[i]) begin
            r_out = bf16_to_real(logits_out[i]);
            r_ref = bf16_to_real(ref_vecs[15-i]);
            if (r_out >= r_ref * 0.95 && r_out <= r_ref * 1.05)
                $display("PASS -- out[%0d] vs ref[%0d]  expected: %.6f, got: %.6f",
                         i, 15-i, r_ref, r_out);
            else
                $display("FAIL -- out[%0d] vs ref[%0d]  expected: %.6f, got: %.6f",
                         i, 15-i, r_ref, r_out);
        end
#50
        $finish;
    end

    initial begin
        #50000
        $display("Watchdog hit");
        $finish;
    end

endmodule
