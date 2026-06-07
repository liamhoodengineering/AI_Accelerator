`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: BF16_Add_Unit
// Description: Combinational BF16 adder.
//              Mirror of BF16_Mult_Unit in style: single always_comb, zero
//              short-circuit, no Inf/NaN/subnormal handling.
//////////////////////////////////////////////////////////////////////////////////

module BF16_Add_Unit(
    input  logic [15:0] A,
    input  logic [15:0] B,
    output logic [15:0] C
);
    logic        sA, sB, sBig, sSmall;
    logic [7:0]  eA, eB, eBig, eSmall, eOut;
    logic [7:0]  mA, mB, mBig, mSmall;          // 8-bit significand with hidden 1
    logic [7:0]  exp_diff;
    logic [8:0]  mSmall_aligned, sum9;
    logic [2:0]  lz;                            // leading-zero count for cancellation
    logic [6:0]  mantOut;
    logic        a_is_zero, b_is_zero, signs_eq;
    logic        a_gt_b;

    always_comb begin
        // Unpack
        sA = A[15]; eA = A[14:7]; mA = {1'b1, A[6:0]};
        sB = B[15]; eB = B[14:7]; mB = {1'b1, B[6:0]};
        a_is_zero = (A[14:0] == 15'b0);
        b_is_zero = (B[14:0] == 15'b0);

        // Magnitude compare (ignore sign)
        a_gt_b = ({eA, A[6:0]} >= {eB, B[6:0]});
        sBig    = a_gt_b ? sA : sB;
        sSmall  = a_gt_b ? sB : sA;
        eBig    = a_gt_b ? eA : eB;
        eSmall  = a_gt_b ? eB : eA;
        mBig    = a_gt_b ? mA : mB;
        mSmall  = a_gt_b ? mB : mA;

        // Align smaller mantissa to bigger exponent
        exp_diff       = eBig - eSmall;
        mSmall_aligned = (exp_diff > 8) ? 9'b0
                                        : ({1'b0, mSmall} >> exp_diff);

        // Add / subtract (9-bit to capture carry-out)
        signs_eq = (sBig == sSmall);
        sum9     = signs_eq ? ({1'b0, mBig} + mSmall_aligned)
                            : ({1'b0, mBig} - mSmall_aligned);

        // Leading-zero detect on the 8-bit window (for cancellation renorm)
        casez (sum9[7:0])
            8'b1???????: lz = 3'd0;
            8'b01??????: lz = 3'd1;
            8'b001?????: lz = 3'd2;
            8'b0001????: lz = 3'd3;
            8'b00001???: lz = 3'd4;
            8'b000001??: lz = 3'd5;
            8'b0000001?: lz = 3'd6;
            8'b00000001: lz = 3'd7;
            default:     lz = 3'd0;
        endcase

        if (signs_eq && sum9[8]) begin
            // Same-sign carry-out: shift right by 1, exp + 1
            eOut    = eBig + 8'd1;
            mantOut = sum9[7:1];
        end
        else if (!signs_eq) begin
            // Opposite-sign cancellation: left-shift to renormalize
            eOut    = eBig - {5'b0, lz};
            mantOut = ((sum9[7:0] << lz));// >> 1);
        end
        else begin
            // Same-sign no carry: hidden bit already at position [7]
            eOut    = eBig;
            mantOut = sum9[6:0];
        end

        // Final selection
        if (a_is_zero)                      C = B;
        else if (b_is_zero)                 C = A;
        else if (!signs_eq && sum9 == 9'b0) C = 16'h0000;
        else                                C = {sBig, eOut, mantOut};
    end

endmodule
