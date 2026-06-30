`timescale 1ns / 1ps

module BRAM_TO_LUT_TB();

    logic         clk = 1'b0;
    logic         reset;
    logic [3:0]   wea, web;
    logic [255:0] input_data = 256'hFFFF_EEEE_DDDD_CCCC_BBBB_AAAA_9999_8888_7777_6666_5555_4444_3333_2222_1111_0000;
    logic [31:0]  dout_1 [4];
    logic [31:0]  dout_2 [4];

    BRAM_to_LUTRAM dut (
        .clk        (clk),
        .reset      (reset),
        .wea_q      (wea),
        .web_q      (web),
        .input_data (input_data),
        .dout_1     (dout_1),
        .dout_2     (dout_2)
    );

    always #5 clk = ~clk;   // 100 MHz

    integer i;
    initial begin
        // Idle defaults
        reset = 1'b1;
        wea   = 4'h0;
        web   = 4'h0;

        @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        // Single-cycle parallel write to all 4 banks via both ports
        wea = 4'hF;
        web = 4'hF;
        @(posedge clk);
        wea = 4'h0;
        web = 4'h0;

        // BRAM read latency
        @(posedge clk);
        @(posedge clk);

        // One $display per bank — covers both dual-port reads
        for (i = 0; i < 4; i = i + 1) begin
            $display("bank=%0d  port_A=0x%08h  port_B=0x%08h  expected_A=0x%08h  expected_B=0x%08h  %s",
                     i,
                     dout_1[i], dout_2[i],
                     input_data[i*64      +: 32],
                     input_data[i*64 + 32 +: 32],
                     ((dout_1[i] === input_data[i*64      +: 32]) &&
                      (dout_2[i] === input_data[i*64 + 32 +: 32])) ? "PASS" : "FAIL");
        end

        $finish;
    end

endmodule
