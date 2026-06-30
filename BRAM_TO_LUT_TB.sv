`timescale 1ns / 1ps

module BRAM_TO_LUT_TB();

    logic        clk = 1'b0;
    logic        reset;
    logic [5:0]  addr_1, addr_2;
    
    logic [31:0] dout_1, dout_2;
    logic [3:0]  wea, web;
    
    logic[255:0] input_data = 256'h4444_4444_3333_3333_2222_2222_1111_1111;//word from bram

    BRAM_to_LUTRAM dut (
        .clk    (clk),
        .reset  (reset),
       // .addr_1 (addr_1),
      //  .din_1  (din_1),
        .dout_1 (dout_1),
        .wea_q  (wea),
      //  .addr_2 (addr_2),
       // .din_2  (din_2),
        .dout_2 (dout_2),
        .input_data(input_data),
        .web_q  (web)
    );

    always #5 clk = ~clk;   // 100 MHz

    
    // Five test values
//    logic [31:0] DATA [0:4] = '{
//        32'h1111_1111,
//        32'h2222_2222,
//        32'h3333_3333,
//        32'h4444_4444,
//        32'hDEAD_BEEF
//    };

    integer i;
    initial begin
        // Idle defaults
        reset  = 1'b1;
        wea    = 4'h0;
        web    = 4'h0;
        addr_1 = '0;
        addr_2 = '0;
       

        @(posedge clk);
        reset = 1'b0;
        @(posedge clk);
        
        //phase 1 - write HBM to BRAM
        wea = 4'hf;
        @(posedge clk);
        wea = 4'h0;

        // Phase 1 — five writes via port A
//        wea = 4'hF;
//        for (i = 0; i < 5; i = i + 1) begin
//            addr_1 = i[5:0];
//            din_1  = DATA[i];
//            @(posedge clk);
//        end
//        wea = 4'h0;

        // Phase 2 — five readbacks via both ports
        
       
        for (i = 0; i < 5; i = i + 1) begin
//            addr_1 = i[5:0];
//            addr_2 = i[5:0];
            @(posedge clk);   // address captured
            @(posedge clk);   // data available
            $display("read addr=%0d  port_A=0x%10h  port_B=0x%10h  expected port_A=0x%10h  expected port_B=0x%10h  %s",
                     i, dout_1[i], dout_2[i], input_data[16*i+15:16*i], input_data[16*i+31:16*i+16],
                     ((dout_1[i] === input_data[16*i+15:16*i]) && (dout_2[i] === input_data[16*i+31:16*i+16])) ? "PASS" : "FAIL");
        end

        $finish;
    end

endmodule
