module BF16_DIV_Unit(
    input logic[15:0] A,
    input logic[15:0] B,
    output logic[15:0] C 
    );
    
    logic c_sign;
    logic[7:0] c_exp;
    logic[15:0] c_mant;
    logic[6:0] c_mant_tmp;
    
    logic[16:0] a_temp;
    logic[16:0] b_temp;
    
    assign a_temp = {1'b1,A[6:0],8'b0};
    assign b_temp = {8'b0,1'b1,B[6:0]};
    
    always_comb
    begin
        c_sign     = A[15] ^ B[15];
        
       
        
            
        c_mant     = a_temp / b_temp;
        
        
        c_mant_tmp = (c_mant[8] == 1'b1) ? c_mant[7:1] : c_mant[6:0];
        c_exp      = A[14:7] - B[14:7] - 8'd129 - ((8'b00000001) & {8{~c_mant[8]}});//failed 5/3 now fixed

        if (A[14:0] == 15'b0 || B[14:0] == 15'b0) begin
            C = {c_sign, 15'b0};   // signed zero
        end
        else begin
            C = {c_sign, c_exp, c_mant_tmp};
        end
    end
    
endmodule