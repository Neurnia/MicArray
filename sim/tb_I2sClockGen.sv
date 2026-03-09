// tb_I2sClockGen.sv
// Test bench for I2sClockGen.sv

`timescale 1ns / 1ps

module tb_I2sClockGen;

    // test input
    logic clk;
    logic rst_n;
    // test output
    logic bclk;
    logic ws;

    // device under test
    I2sClockGen u_dut (
        .clk_i  (clk),
        .rst_n_i(rst_n),

        .bclk_o(bclk),
        .ws_o  (ws)
    );

    // initial values
    initial begin
        clk   = 0;
        rst_n = 0;
        #15

        // testing
        rst_n = 1;
        #8ms  // several ws
        $stop;
    end

    always #10 clk = ~clk;

endmodule
