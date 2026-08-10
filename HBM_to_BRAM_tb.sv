`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: HBM_to_BRAM_tb
// Description: Verifies that HBM_to_BRAM.sv loads 16x16 tiles of a row-major
//              matrix (8192x4096, 16-bit words) out of HBM correctly.
//
//              Gold-standard pattern (mirrors flash_v_tb.sv): python_verification/
//              verify_hbm_to_bram.py emits the vectors + expected results as
//              $readmemh files; this TB drives the DUT with them and self-checks.
//
//              Check tiers (see plan):
//                A. Address cross-check  : dut.S_AXI_ARADDR/AWADDR[i] == row-major gold
//                B. Read-data reconstruct: read_data_out[i] == gold beat; little-endian
//                                          word decomposition == gold tile words
//                D. Neighbor isolation   : write target + tc+1 + tr+1 with distinct
//                                          data, read target, expect only target data
//                C. BRAM reconstruct     : DEFERRED (tile write-index sequencing is
//                                          user-owned) — reported informational only.
//
//              Tile order matches verify_hbm_to_bram.py:
//                0:(0,0) 1:(100,50) 2:(511,255)  standalone
//                3:(200,100) target  4:(200,101) tc+1  5:(201,100) tr+1
//////////////////////////////////////////////////////////////////////////////////

module HBM_to_BRAM_tb;

    localparam int NT = 6;   // must match verify_hbm_to_bram.py

    localparam string BLOCK_FILE = "C:/Users/egypt/AI_Accelerator/python_verification/hbm_block.txt";
    localparam string ADDR_FILE  = "C:/Users/egypt/AI_Accelerator/python_verification/hbm_addr.txt";
    localparam string BEATS_FILE = "C:/Users/egypt/AI_Accelerator/python_verification/hbm_beats.txt";
    localparam string TILES_FILE = "C:/Users/egypt/AI_Accelerator/python_verification/hbm_tiles.txt";

    // --- Gold memories (one value per line, $readmemh) ---
    logic [16:0]  block_mem [0:NT-1];        // block address T per tile
    logic [33:0]  addr_mem  [0:NT*16-1];     // byte_addr(i)      : [t*16+i]
    logic [255:0] beats_mem [0:NT*16-1];     // 256-bit LE beat   : [t*16+i]
    logic [15:0]  tiles_mem [0:NT*256-1];    // gold word         : [(t*16+i)*16+c]

    // --- Clock / reset ---
    logic clk         = 1'b0;
    logic hbm_ref_clk = 1'b0;
    logic apb_pclk    = 1'b0;
    logic reset       = 1'b1;
    always #2.5 clk         = ~clk;          // 200 MHz AXI
    always #5   hbm_ref_clk = ~hbm_ref_clk;  // 100 MHz HBM PLL ref
    always #5   apb_pclk    = ~apb_pclk;     // 100 MHz APB

    // --- DUT stimulus (array interface) ---
    logic [16:0]  read_block_address;
    logic [16:0]  write_block_address;
    logic [255:0] write_data    [16];
    logic         RW_en         [16];
    logic         start;
    logic [255:0] read_data_out [16];
    logic [1:0]   read_resp_out [16];
    logic         apb_complete_0;

    // --- State encodings (must match DUT) ---
    localparam [2:0] IDLE_ST = 3'b000;

    // --- Diagnostic trace of channel-0 R-channel handshake (gated) ---
    logic trace_en = 1'b0;
    always @(posedge clk) if (trace_en)
        $display("[%0t] st0=%0d ARv=%b ARr=%b ARaddr=%09h | Rv=%b Rr=%b Rl=%b RDATA0.lo=%04h | rdo0.lo=%04h",
                 $time, dut.state[0],
                 dut.S_AXI_ARVALID[0], dut.S_AXI_ARREADY[0], dut.S_AXI_ARADDR[0],
                 dut.S_AXI_RVALID[0], dut.S_AXI_RREADY[0], dut.S_AXI_RLAST[0],
                 dut.S_AXI_RDATA[0][15:0], read_data_out[0][15:0]);

    HBM_to_BRAM dut (
        .read_block_address  (read_block_address),
        .write_block_address (write_block_address),
        .write_data          (write_data),
        .RW_en               (RW_en),
        .start               (start),
        .clk                 (clk),
        .reset               (reset),
        .HBM_REF_CLK_0       (hbm_ref_clk),
        .APB_0_PCLK          (apb_pclk),
        .read_data_out       (read_data_out),
        .read_resp_out       (read_resp_out),
        .apb_complete_0      (apb_complete_0)
    );

    // --- Scoreboard ---
    int addr_pass, addr_fail;
    int data_pass, data_fail;
    int bram_pass, bram_fail;   // Tier C (deferred / informational)

    // ---- helpers ----------------------------------------------------------
    function automatic bit all_idle();
        all_idle = 1'b1;
        for (int i = 0; i < 16; i++)
            if (dut.state[i] !== IDLE_ST) all_idle = 1'b0;
    endfunction

    task automatic wait_all_idle(input int max_cyc = 100000);
        int n = 0;
        do begin
            @(posedge clk);
            n++;
            if (n > max_cyc) begin
                $error("wait_all_idle: timeout, states not returning to IDLE");
                $finish;
            end
        end while (!all_idle());
    endtask

    task automatic pulse_start();
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;   // 1-cycle pulse (all 16 channels leave IDLE together)
        @(posedge clk);
    endtask

    // Tier A: compare the DUT's generated AXI addresses to the row-major gold.
    task automatic check_read_addr(input int t);
        for (int i = 0; i < 16; i++) begin
            if (dut.S_AXI_ARADDR[i] === addr_mem[t*16 + i]) addr_pass++;
            else begin
                addr_fail++;
                $error("ADDR(R) t=%0d ch=%0d  got=0x%09h  gold=0x%09h",
                       t, i, dut.S_AXI_ARADDR[i], addr_mem[t*16 + i]);
            end
        end
    endtask

    task automatic check_write_addr(input int t);
        for (int i = 0; i < 16; i++) begin
            if (dut.S_AXI_AWADDR[i] === addr_mem[t*16 + i]) addr_pass++;
            else begin
                addr_fail++;
                $error("ADDR(W) t=%0d ch=%0d  got=0x%09h  gold=0x%09h",
                       t, i, dut.S_AXI_AWADDR[i], addr_mem[t*16 + i]);
            end
        end
    endtask

    // Drive one tile's 16 beats into HBM via the DUT write path.
    task automatic write_tile(input int t);
        write_block_address = block_mem[t][16:0];
        for (int i = 0; i < 16; i++) begin
            write_data[i] = beats_mem[t*16 + i];
            RW_en[i]      = 1'b1;   // write path
        end
        #1 check_write_addr(t);     // AWADDR is combinational from write_block_address
        pulse_start();
        wait_all_idle();
        $display("[%0t] write_tile %0d (T=%05h) done", $time, t, block_mem[t]);
    endtask

    // Read one tile back through the DUT read path; latch read_data_out.
    task automatic read_tile(input int t);
        read_block_address = block_mem[t][16:0];
        for (int i = 0; i < 16; i++) RW_en[i] = 1'b0;   // read path
        #1 check_read_addr(t);      // ARADDR is combinational from read_block_address
        pulse_start();
        wait_all_idle();
        repeat (2) @(posedge clk);  // let read_data_out settle
        $display("[%0t] read_tile  %0d (T=%05h) done", $time, t, block_mem[t]);
    endtask

    // Tier B: read_data_out[i] must equal gold beat, and its little-endian word
    // decomposition must equal the gold tile words.  `expect_t` is the tile whose
    // gold we expect to see (for neighbor isolation it stays = target tile).
    task automatic check_read_data(input int expect_t);
        logic [15:0] got, gold;
        int          local_pass, local_fail;
        local_pass = 0; local_fail = 0;
        for (int i = 0; i < 16; i++) begin
            // exact 256-bit beat check
            if (read_data_out[i] !== beats_mem[expect_t*16 + i]) begin
                $error("BEAT t=%0d row=%0d  got=0x%064h  gold=0x%064h",
                       expect_t, i, read_data_out[i], beats_mem[expect_t*16 + i]);
            end
            // per-column little-endian word check
            for (int c = 0; c < 16; c++) begin
                got  = read_data_out[i][16*c +: 16];
                gold = tiles_mem[(expect_t*16 + i)*16 + c];
                if (got === gold) begin
                    data_pass++; local_pass++;
                end else begin
                    data_fail++; local_fail++;
                    $error("WORD t=%0d row=%0d col=%0d  got=%04h  gold=%04h",
                           expect_t, i, c, got, gold);
                end
            end
        end
        $display("  Tier B tile %0d: %0d/256 words match", expect_t, local_pass);
    endtask

    // Tier C (DEFERRED / informational): reconstruct LUTRAM from the Q_bank
    // registered read ports and compare to gold.  BRAM write-address sequencing
    // (FSM_tile_counter/BRAM_parsing 'row') is user-owned, so this is expected to
    // be incomplete for now; reported separately, does NOT gate the verdict.
    //   LUTRAM[i][4b+0]=port_A[i][b][15:0], [4b+1]=port_A[i][b][31:16],
    //   LUTRAM[i][4b+2]=port_B[i][b][15:0], [4b+3]=port_B[i][b][31:16]
    task automatic check_bram_deferred(input int t);
        logic [15:0] got, gold;
        for (int i = 0; i < 16; i++)
            for (int b = 0; b < 4; b++)
                for (int h = 0; h < 4; h++) begin
                    case (h)
                        0: got = dut.port_A_out[i][b][15:0];
                        1: got = dut.port_A_out[i][b][31:16];
                        2: got = dut.port_B_out[i][b][15:0];
                        3: got = dut.port_B_out[i][b][31:16];
                    endcase
                    gold = tiles_mem[(t*16 + i)*16 + (4*b + h)];
                    if (got === gold) bram_pass++;
                    else              bram_fail++;
                end
    endtask

    // ---- main -------------------------------------------------------------
    initial begin
        // defaults
        start               = 1'b0;
        read_block_address  = '0;
        write_block_address = '0;
        for (int i = 0; i < 16; i++) begin
            write_data[i] = '0;
            RW_en[i]      = 1'b0;
        end
        addr_pass=0; addr_fail=0; data_pass=0; data_fail=0; bram_pass=0; bram_fail=0;

        // Small VCD (channel-0 R-channel only) for waveform inspection in Vivado
        $dumpfile("hbm_rch.vcd");
        $dumpvars(0, dut.state[0],
                  dut.S_AXI_ARVALID[0], dut.S_AXI_ARREADY[0], dut.S_AXI_ARADDR[0],
                  dut.S_AXI_RVALID[0], dut.S_AXI_RREADY[0], dut.S_AXI_RLAST[0],
                  dut.S_AXI_RDATA[0], read_data_out[0]);

        // load gold
        $readmemh(BLOCK_FILE, block_mem);
        $readmemh(ADDR_FILE,  addr_mem);
        $readmemh(BEATS_FILE, beats_mem);
        $readmemh(TILES_FILE, tiles_mem);
        $display("loaded gold: NT=%0d  block[0]=%05h  addr[0]=%09h  beat[0]=%064h",
                 NT, block_mem[0], addr_mem[0], beats_mem[0]);

        // reset + wait for HBM calibration
        repeat (8) @(posedge clk);
        reset <= 1'b0;
        $display("[%0t] reset released, waiting for apb_complete_0", $time);
        wait (apb_complete_0 === 1'b1);
        $display("[%0t] apb_complete_0 asserted — HBM ready", $time);
        repeat (2) @(posedge clk);

        // ---- Scenario 1: standalone round-trip + address check (tiles 0,1,2) ----
        trace_en = 1'b1;   // trace tiles 0 (works) and 1 (fails) for diagnosis
        for (int t = 0; t < 3; t++) begin
            write_tile(t);
            read_tile(t);
            check_read_data(t);
            // check_bram_deferred(t);  // Tier C disabled: BRAM-write block is user-owned WIP (does not elaborate)
            if (t == 1) trace_en = 1'b0;
        end

        // ---- Scenario 2: neighbor isolation (target=3, neighbors=4,5) ----
        write_tile(3);   // target       (200,100) id=4
        write_tile(4);   // tc+1 neighbor (200,101) id=5
        write_tile(5);   // tr+1 neighbor (201,100) id=6
        read_tile(3);
        $display("  neighbor isolation: reading target tile 3, expecting only its data");
        check_read_data(3);
        // check_bram_deferred(3);  // Tier C disabled (see above)

        // ---- summary ----
        $display("");
        $display("=== HBM_to_BRAM tile-load verification ===");
        $display("Tier A  addresses : PASS %0d  FAIL %0d", addr_pass, addr_fail);
        $display("Tier B  tile data : PASS %0d  FAIL %0d (of %0d words checked)",
                 data_pass, data_fail, data_pass + data_fail);
        $display("Tier D  neighbor isolation folded into Tier B on tile 3");
        $display("Tier C  BRAM: DISABLED — BRAM-write block is user-owned WIP (does not elaborate)");
        if (addr_fail == 0 && data_fail == 0)
            $display("RESULT: PASS  (Tiers A+B+D green; Tier C deferred)");
        else
            $display("RESULT: FAIL  (addr_fail=%0d data_fail=%0d)", addr_fail, data_fail);

        $finish;
    end

    // Watchdog — covers HBM calibration (~10-40 us) + 6 tiles x 2 transactions
    initial begin
        #2_000_000;   // 2 ms
        $error("TIMEOUT: testbench did not finish within 2 ms");
        $finish;
    end

endmodule
