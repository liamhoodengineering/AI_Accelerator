`timescale 1ns / 1ps

module BRAM_to_LUTRAM(
    input  logic         clk,
    input  logic         reset,
    input  logic [3:0]   wea_q,
    input  logic [3:0]   web_q,
    input  logic [255:0] input_data,
    output logic [31:0]  dout_1 [4],   // port A from each bank
    output logic [31:0]  dout_2 [4]    // port B from each bank
);

    genvar bank;
    generate
        for (bank = 0; bank < 4; bank++) begin : q_banks
            Q_bank Q_bank_inst (
                .clka  (clk),
                .rsta  (reset),
                .wea   (wea_q),
                .addra (6'h0),
                .dina  (input_data[bank*64      +: 32]),
                .douta (dout_1[bank]),
                .clkb  (clk),
                .rstb  (reset),
                .web   (web_q),
                .addrb (6'h1),
                .dinb  (input_data[bank*64 + 32 +: 32]),
                .doutb (dout_2[bank])
            );
        end
    endgenerate

endmodule
