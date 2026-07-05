`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/05/2026 04:42:53 PM
// Design Name: 
// Module Name: softermax_attempt_2_tb
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


module softermax_attempt_2_tb();

 localparam string IN_FILE   = "C:/Users/egypt/AI_Accelerator/python_verification/input.txt";
    localparam string OUT_FILE  = "C:/Users/egypt/AI_Accelerator/python_verification/output.txt";
    localparam int    N_ROWS    = 1;
    
        logic         clk;
    logic         Reset;
    logic [15:0]  logits     [15:0];
    logic [15:0]  logits_out [15:0];

    softermax dut(
        .logits(logits),
        .clk(clk),
        .Reset(Reset),
        .logits_out(logits_out)
    );
    
    always #5 clk = ~clk;
    
    task automatic read_file(input string path,
   // begin
        ref logic[15:0] dst[16]);
        int fd, row, col, n;
        string tok;
    begin
        fd = $fopen(path, "r");
        if(fd == 0) $fatal(1, "cannot open %s", path);
        
         row = 0;
         col = 0;
         
        while (!$feof(fd) && row < N_ROWS) begin
            n = $fscanf(fd, "%s", tok);
            if (n == 1) begin
                    dst[row][col] = tok.atoreal();
                    col++;
                    if (col == 16) begin col = 0; row++; end
                end
            
        end 
        $fclose(fd);
    end
  endtask  
  
  logic[15:0] in_vecs[16];
  logic[15:0] ref_vecs[16];
  
  
  
  initial begin
      clk = 1'b0;
      Reset = 1'b1;
      repeat(2) @(posedge clk);
      Reset = 1'b0;
      read_file(IN_FILE,  in_vecs);
      foreach(logits[i])
        logits[i] = in_vecs[i];
      repeat(30) @(posedge clk);
      
      read_file(OUT_FILE,  ref_vecs);
      foreach(logits_out[i])
        if((logits_out[i] >= ref_vecs[i]*0.95) && (logits_out[i] <= ref_vecs[i]*1.05))
            $display("PASS -- computed: %.5f, got: %.5f", ref_vecs[i], logits_out[i]);
        else
            $display("FAIL -- computed: %.5f, got: %.5f", ref_vecs[i], logits_out[i]);

  end
  
  
  initial begin
      #50000 
      $display("Watchdog hit");
      $finish;
  end
      
  
  

endmodule
