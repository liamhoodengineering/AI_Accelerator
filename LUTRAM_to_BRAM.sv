`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/19/2026 04:04:48 PM
// Design Name: 
// Module Name: LUTRAM_to_BRAM
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module LUTRAM_to_BRAM#
(parameter int ROW = 16)
(
    input logic start,
    input logic clk,
    output logic[31:0] Q_bank_dout_1[ROW][4],
    output logic[31:0] Q_bank_dout_2[ROW][4],
    input logic[15:0] Q_LUTRAM[ROW][16],
    output logic done
);
 always_ff @(posedge clk)
 begin
    
        for(int i = 0; i < ROW; i++)
        begin
            for(int bank = 0; bank < 4; bank++)
            begin
                if(start)begin
                    Q_bank_dout_1[i][bank] <= {Q_LUTRAM[bank*4+1][i], Q_LUTRAM[bank*4][i]};
                    Q_bank_dout_2[i][bank] <= {Q_LUTRAM[bank*4+3][i], Q_LUTRAM[bank*4+2][i]};
                    done <= 1'b1;
                end
                else
                begin
                    // Hold the loaded tile between loads (do NOT zero it): the
                    // LUTRAM must persist for the systolic array to read after
                    // the 1-cycle load pulse. Only `done` deasserts.
                    done <= 1'b0;
                end
            end 
        end
    end
endmodule

