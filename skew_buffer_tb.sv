`timescale 1ns / 1ps

module skew_buffer_tb(
    );

    localparam int ROWS   = 16;
    localparam int COLS   = 16;
    localparam int DATA_W = 16;

    logic                clk;
    logic                reset;
    logic [DATA_W-1:0]   in_data  [ROWS][COLS];
    logic [DATA_W-1:0]   out_data [ROWS][COLS];
    int                  errors;

    skew_buffer #(
        .ROWS(ROWS),
        .DATA_W(DATA_W)
    ) dut (
        .clk(clk),
        .reset(reset),
        .in_data(in_data),
        .out_data(out_data));

    always #5 clk = ~clk;

    // Expected outputs sampled just after each posedge clk.
    // Row index = cycle (0..7), column index = lane (0..2).
    logic [DATA_W-1:0] expected_out [8][ROWS] = '{
        '{16'd10, 16'd0,  16'd0},
        '{16'd11, 16'd20, 16'd0},
        '{16'd12, 16'd21, 16'd30},
        '{16'd13, 16'd22, 16'd31},
        '{16'd14, 16'd23, 16'd32},
        '{16'd15, 16'd24, 16'd33},
        '{16'd16, 16'd25, 16'd34},
        '{16'd17, 16'd26, 16'd35}
    };

    initial begin
        clk     = 1'b0;
        reset   = 1'b1;
        in_data = {'{16'd10, 16'd20, 16'd30},
                  '{16'd11, 16'd21, 16'd31},
                  '{16'd12, 16'd22, 16'd32},
                  '{16'd13, 16'd23, 16'd33},
                  '{16'd14, 16'd24, 16'd34},
                  '{16'd15, 16'd25, 16'd35},
                  '{16'd25, 16'd35, 16'd45}};
        errors  = 0;

        @(negedge clk); reset = 1'b0;

        for (int cyc = 0; cyc < 8; cyc++) begin
            // Drive new inputs on the negedge so they are stable for the next posedge.
            in_data[0] = 16'(10 + cyc);
            in_data[1] = 16'(20 + cyc);
            in_data[2] = 16'(30 + cyc);

            @(posedge clk);
            #1;  // let combinational out_data settle

            for (int lane = 0; lane < ROWS; lane++) begin
                if (out_data[lane] !== expected_out[cyc][lane]) begin
                    $display("FAIL cycle=%0d lane=%0d got=%0d exp=%0d",
                             cyc, lane, out_data[lane], expected_out[cyc][lane]);
                    errors++;
                end
                else begin
                    $display("PASS cycle=%0d lane=%0d got=%0d",
                             cyc, lane, out_data[lane]);
                end
            end
        end

        // Drain check: stop feeding data and confirm the chain flushes to zero.
        in_data = '{16'd0, 16'd0, 16'd0};
        repeat (ROWS) @(posedge clk);
        #1;
        for (int lane = 0; lane < ROWS; lane++) begin
            if (out_data[lane] !== 16'd0) begin
                $display("FAIL drain lane=%0d got=%0d exp=0", lane, out_data[lane]);
                errors++;
            end
        end

        if (errors == 0)
            $display("==== PASS: skew_buffer ROWS=%0d matches expected delay pattern ====", ROWS);
        else
            $display("==== FAIL: %0d skew_buffer mismatches ====", errors);

        $finish;
    end

endmodule
