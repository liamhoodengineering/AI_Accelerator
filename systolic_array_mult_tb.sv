`timescale 1ns / 1ps

module systolic_array_mult_tb(
    );

    logic clk;
    logic reset;
    logic[15:0]   c_matrix[15:0][15:0];
    logic[15:0]    expected[15:0][15:0];
    int   errors;

    systolic_array_mult dut(
        .clk(clk),
        .reset(reset),
        .c_matrix(c_matrix));

    always #5 clk = ~clk;

    initial begin
        clk    = 1'b0;
        reset  = 1'b0;
        errors = 0;

       expected = '{
    '{ 84,  90,  96, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{201, 216, 231, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{318, 342, 366, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},

    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
};

        @(negedge clk); reset = 1'b1;
        @(negedge clk); reset = 1'b0;
        
       // $display(c_matrix);

        repeat (12) @(posedge clk);

        for (int i = 0; i < 16; i++) begin
            for (int j = 0; j < 16; j++) begin
                if (c_matrix[i][j] !== expected[i][j]) begin
                    $display("MISMATCH c_matrix[%0d][%0d]: got %0d, expected %0d",
                             i, j, c_matrix[i][j], expected[i][j]);
                    errors++;
                end
            end
        end

        if (errors == 0)
            $display("PASS: c_matrix matches A*B reference");
        else
            $display("FAIL: %0d mismatches", errors);

        $finish;
    end

//    initial begin
//        $display("t  cnt done acc[0][0] acc[1][1] acc[2][2] c[0][0]");
//        forever @(posedge clk) begin
//            $display("%0t %0d %b %0d %0d %0d %0d",
//                     $time,
//                     dut.counter_inst.counter,
//                     dut.done,
//                     dut.acc_grid[0][0],
//                     dut.acc_grid[1][1],
//                     dut.acc_grid[2][2],
//                     c_matrix[0][0]);
//        end
//    end

endmodule
