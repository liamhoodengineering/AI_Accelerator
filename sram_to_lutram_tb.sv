`timescale 1ns / 1ps

module sram_to_lutram_tb;

    logic        clk;
    logic        Reset;

    // Test-phase signals
    logic [3:0]  load_row;
    logic        load_en;

    // Preload-phase signals (port A of every bank writes its own per-bank data)
    logic        preload_en;
    logic [5:0]  preload_addr;
    logic [31:0] preload_q [4];
    logic [31:0] preload_k [4];

    top dut(
        .clk(clk),
        .Reset(Reset),
        .load_row(load_row),
        .load_en(load_en),
        .preload_en(preload_en),
        .preload_addr(preload_addr),
        .preload_q(preload_q),
        .preload_k(preload_k));

    always #5 clk = ~clk;

    // ---- BF16 reference patterns (same formula as q_bank_*.mem / k_bank_*.mem) -
    function automatic logic [15:0] q_bf16(input int r, input int c);
        return logic'(((r << 8) | (c << 4)) & 16'hFFFF);
    endfunction
    function automatic logic [15:0] k_bf16(input int r, input int c);
        return logic'(((r << 12) | (c << 8)) & 16'hFFFF);
    endfunction

    // ---- SRAM contents (4 banks x 64 32-bit words for Q and K) ---------------
    logic [31:0] q_mem [4][64];
    logic [31:0] k_mem [4][64];

    // ---- Golden LUT contents -------------------------------------------------
    logic [15:0] q_expected [16][16];
    logic [15:0] k_expected [16][16];

    int errors;

    initial begin
        // ---- Init ----
        clk          = 1'b0;
        Reset        = 1'b1;
        load_row     = 4'b0;
        load_en      = 1'b0;
        preload_en   = 1'b0;
        preload_addr = 6'b0;
        errors       = 0;

        for (int b = 0; b < 4; b++) begin
            preload_q[b] = 32'b0;
            preload_k[b] = 32'b0;
            for (int i = 0; i < 64; i++) begin
                q_mem[b][i] = 32'b0;
                k_mem[b][i] = 32'b0;
            end
        end

        // ---- Build per-bank SRAM contents ----
        // Low-order interleaving:
        //   bank b offset 2r   -> {bf16(r, 2b+1), bf16(r, 2b)}   (port A view)
        //   bank b offset 2r+1 -> {bf16(r, 2b+9), bf16(r, 2b+8)} (port B view)
        for (int b = 0; b < 4; b++) begin
            for (int r = 0; r < 16; r++) begin
                q_mem[b][2*r]   = {q_bf16(r, 2*b+1), q_bf16(r, 2*b)};
                q_mem[b][2*r+1] = {q_bf16(r, 2*b+9), q_bf16(r, 2*b+8)};
                k_mem[b][2*r]   = {k_bf16(r, 2*b+1), k_bf16(r, 2*b)};
                k_mem[b][2*r+1] = {k_bf16(r, 2*b+9), k_bf16(r, 2*b+8)};
            end
        end

        // ---- Build expected LUTRAM contents ----
        // Q: q_tile_lut[i][j] = q_bf16(i, j) directly.
        // K: loaded TRANSPOSED -- source row r lands in LUT column r,
        //    so k_tile_lut[i][j] holds the BF16 from K matrix row j, column i.
        for (int i = 0; i < 16; i++) begin
            for (int j = 0; j < 16; j++) begin
                q_expected[i][j] = q_bf16(i, j);
                k_expected[i][j] = k_bf16(j, i);
            end
        end

        // ---- Release reset ----
        repeat (2) @(posedge clk);
        @(negedge clk); Reset = 1'b0;
        @(posedge clk);

        // ---- Preload phase: walk 64 addresses, write per-bank data ----------
        preload_en = 1'b1;
        for (int a = 0; a < 64; a++) begin
            preload_addr = a[5:0];
            for (int b = 0; b < 4; b++) begin
                preload_q[b] = q_mem[b][a];
                preload_k[b] = k_mem[b][a];
            end
            @(posedge clk);
        end
        preload_en = 1'b0;
        for (int b = 0; b < 4; b++) begin
            preload_q[b] = 32'b0;
            preload_k[b] = 32'b0;
        end

        // Settle: let the write completion drain and the next read setup.
        @(posedge clk);
        @(posedge clk);

        // ---- Test phase: walk load_row across 16 cycles --------------------
        load_en = 1'b1;
        for (int r = 0; r < 16; r++) begin
            load_row = r[3:0];
            @(posedge clk);
        end
        load_en = 1'b0;

        // Wait for the final pipelined LUT write to settle:
        //   BRAM read latency 1 + load_row_d1/load_en_d1 pipeline 1 = 2 cycles
        @(posedge clk);
        @(posedge clk);
        #1;

        // ---- Compare ----
        for (int i = 0; i < 16; i++) begin
            for (int j = 0; j < 16; j++) begin
                if (dut.q_tile_lut[i][j] !== q_expected[i][j]) begin
                    $display("FAIL Q i=%0d j=%0d got=%h exp=%h",
                             i, j, dut.q_tile_lut[i][j], q_expected[i][j]);
                    errors++;
                end
                if (dut.k_tile_lut[i][j] !== k_expected[i][j]) begin
                    $display("FAIL K i=%0d j=%0d got=%h exp=%h",
                             i, j, dut.k_tile_lut[i][j], k_expected[i][j]);
                    errors++;
                end
            end
        end

        if (errors == 0)
            $display("==== PASS: sram_to_lutram Q+K load matches expected ====");
        else
            $display("==== FAIL: %0d mismatches ====", errors);

        $finish;
    end

endmodule
