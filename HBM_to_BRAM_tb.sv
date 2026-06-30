`timescale 1ns / 1ps

module HBM_to_BRAM_tb;

    // --- Clock / reset ---
    logic clk           = 1'b0;
    logic hbm_ref_clk   = 1'b0;
    logic apb_pclk      = 1'b0;
    logic reset         = 1'b1;
    always #2.5 clk         = ~clk;          // 200 MHz AXI clock
    always #5   hbm_ref_clk = ~hbm_ref_clk;  // 100 MHz HBM PLL ref
    always #5   apb_pclk    = ~apb_pclk;     // 100 MHz APB clock

    // --- DUT stimulus ---
    logic [33:0]  read_address;
    logic [33:0]  write_address;
    logic [255:0] write_data;
    logic         RW_en;
    logic         start;
    logic [255:0] read_data_out;
    logic [1:0]   read_resp_out;
    logic         apb_complete_0;

    // --- State encodings (must match DUT) ---
    localparam [2:0] WRITE_RESP_ST = 3'b100;
    localparam [2:0] READ_DATA_ST  = 3'b110;
    localparam [2:0] IDLE_ST       = 3'b000;

    // --- DUT instantiation ---
    HBM_to_BRAM dut (
        .read_address   (read_address),
        .write_address  (write_address),
        .write_data     (write_data),
        .RW_en          (RW_en),
        .start          (start),
        .clk            (clk),
        .reset          (reset),
        .HBM_REF_CLK_0  (hbm_ref_clk),
        .APB_0_PCLK     (apb_pclk),
        .read_data_out  (read_data_out),
        .read_resp_out  (read_resp_out),
        .apb_complete_0 (apb_complete_0)
    );

    // --- Constants ---
    localparam logic [33:0]  WRITE_ADDR = 34'h0_0000_0040;
    localparam logic [255:0] PATTERN    =
        256'hDEAD_BEEF_CAFE_F00D_1234_5678_9ABC_DEF0_0FED_CBA9_8765_4321_F00D_CAFE_BEEF_DEAD;

    // --- Test sequence ---
    initial begin
        // Defaults
        RW_en         = 1'b0;
        start         = 1'b0;
        write_address = '0;
        read_address  = '0;
        write_data    = '0;

        // Phase 0 — Reset, then wait for HBM calibration to complete
        repeat (4) @(posedge clk);
        reset <= 1'b0;
        $display("[%0t] reset released, waiting for apb_complete_0", $time);
        wait (apb_complete_0 === 1'b1);
        $display("[%0t] apb_complete_0 asserted — HBM ready", $time);
        @(posedge clk);

        // Phase 1 — Write
        $display("[%0t] WRITE start: addr=0x%h data=0x%h", $time, WRITE_ADDR, PATTERN);
        write_address <= WRITE_ADDR;
        write_data    <= PATTERN;
        RW_en         <= 1'b1;
        start         <= 1'b1;
        @(posedge clk);
        start         <= 1'b0;   // 1-cycle pulse
        // Wait for FSM to enter WRITE_RESP then return to IDLE
        wait (dut.state == WRITE_RESP_ST);
        wait (dut.state == IDLE_ST);
        $display("[%0t] WRITE complete", $time);

        // Phase 2 — Idle gap
        RW_en <= 1'b0;
        repeat (2) @(posedge clk);

        // Phase 3 — Read
        $display("[%0t] READ start:  addr=0x%h", $time, WRITE_ADDR);
        read_address <= WRITE_ADDR;
        RW_en        <= 1'b0;   // read path
        start        <= 1'b1;
        @(posedge clk);
        start        <= 1'b0;   // 1-cycle pulse
        wait (dut.state == READ_DATA_ST);
        wait (dut.state == IDLE_ST);
        @(posedge clk);
        $display("[%0t] READ complete: data=0x%h resp=%b",
                 $time, read_data_out, read_resp_out);

        // Phase 4 — Check
        if (read_data_out !== PATTERN) begin
            $error("DATA MISMATCH: expected 0x%h, got 0x%h",
                   PATTERN, read_data_out);
        end else begin
            $display("PASS: read data matches written pattern");
        end

        if (read_resp_out !== 2'b00) begin
            $error("RRESP not OKAY: got %b", read_resp_out);
        end

        $finish;
    end

    // --- Watchdog ---
    initial begin
        #1_000_000;   // 1 ms — covers HBM calibration (~10–40 µs) + transactions
        $error("TIMEOUT: testbench did not finish within 1 ms");
        $finish;
    end

endmodule
