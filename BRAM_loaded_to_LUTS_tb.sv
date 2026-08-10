`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: BRAM_loaded_to_LUTS_tb
// Description: Tests BRAM_TO_LUTRAM (BRAM ports -> LUTRAM packing).
//              Preloads the two BRAM read ports (dout_1/dout_2) with distinct
//              BF16-formatted values, clocks the DUT, and checks that each row's
//              16 LUTRAM slots receive them in bank-major, port-A-then-B,
//              little-endian order:
//                bank b: dout_1[i][b] -> slots 4b(low)/4b+1(high)
//                        dout_2[i][b] -> slots 4b+2(low)/4b+3(high)
//////////////////////////////////////////////////////////////////////////////////

module BRAM_loaded_to_LUTS_tb();

    logic [31:0] data_in_1 [16][4];
    logic [31:0] data_in_2 [16][4];
    logic [15:0] LUTS      [16][16];
    logic        clk = 1'b0;
    logic        result;
    int          errors = 0;

    // Distinct, BF16-formatted value per (row, slot): positive normal,
    // exponent = row+1 (unique per row), mantissa = slot (unique per slot).
    function automatic logic [15:0] slot_val(input int i, input int s);
        return {1'b0, 8'(i + 1), 7'(s)};
    endfunction

    BRAM_TO_LUTRAM dut(
        .clk    (clk),
        .dout_1 (data_in_1),
        .dout_2 (data_in_2),
        .LUTRAM (LUTS)
    );

    always #5 clk = ~clk;

    task automatic check(input  logic [15:0] LUT_out_1,
                         input  logic [15:0] LUT_out_2,
                         input  logic [31:0] BRAM_out_1,
                         output logic        result);
        result = (LUT_out_1 == BRAM_out_1[15:0]) && (LUT_out_2 == BRAM_out_1[31:16]);
    endtask

    initial begin
        // ---- preload: pack slot values little-endian into the two ports ----
        for (int i = 0; i < 16; i++)
            for (int b = 0; b < 4; b++) begin
                data_in_1[i][b] = {slot_val(i, 4*b + 1), slot_val(i, 4*b + 0)}; // {high, low}
                data_in_2[i][b] = {slot_val(i, 4*b + 3), slot_val(i, 4*b + 2)};
            end

        // ---- clock the DUT so LUTRAM registers (1 edge captures; sample after) ----
        @(posedge clk);
        @(posedge clk);
        #1;

        // ---- check every 32-bit word -> its two LUTRAM slots ----
        for (int i = 0; i < 16; i++)
            for (int b = 0; b < 4; b++) begin
                check(LUTS[i][4*b+0], LUTS[i][4*b+1], data_in_1[i][b], result);
                if (!result) begin
                    errors++;
                    $display("MISMATCH row=%0d bank=%0d portA  slots %0d/%0d got=%h/%h exp=%h/%h",
                             i, b, 4*b, 4*b+1, LUTS[i][4*b], LUTS[i][4*b+1],
                             data_in_1[i][b][15:0], data_in_1[i][b][31:16]);
                end
                check(LUTS[i][4*b+2], LUTS[i][4*b+3], data_in_2[i][b], result);
                if (!result) begin
                    errors++;
                    $display("MISMATCH row=%0d bank=%0d portB  slots %0d/%0d got=%h/%h exp=%h/%h",
                             i, b, 4*b+2, 4*b+3, LUTS[i][4*b+2], LUTS[i][4*b+3],
                             data_in_2[i][b][15:0], data_in_2[i][b][31:16]);
                end
            end

        if (errors == 0)
            $display("==== PASS: all 128 words / 256 LUTRAM slots correct ====");
        else
            $display("==== FAIL: %0d word mismatches ====", errors);

        $finish;
    end

endmodule
