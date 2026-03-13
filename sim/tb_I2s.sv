// tb_I2s.sv
// Test bench for I2sClockGen.sv & I2sCapture.sv

`timescale 1ns / 1ps

module tb_I2s;

    // test input
    logic        clk;
    logic        rst_n;
    logic        sd;

    // internal connection
    logic        bclk;
    logic        ws;

    // test output
    logic [15:0] capture_data;
    logic        capture_done;

    // test data
    logic [23:0] data1 = 24'b1010_1010_1010_1010_1010_1010;
    logic [23:0] data2 = 24'b0101_0101_0101_0101_0101_0101;

    // send 24 bits data
    task automatic send_data(input logic [23:0] data);
        @(negedge ws);
        for (int i = 23; i >= 0; i--) begin
            @(negedge bclk);  // naturally wait for one bclk at first
            sd <= data[i];
        end
        @(negedge bclk);
        sd <= 0;  // reset sd
    endtask  //automatic

    // devices under test
    I2sClockGen u_ClockGen (
        .clk_i  (clk),
        .rst_n_i(rst_n),

        .bclk_o(bclk),
        .ws_o  (ws)
    );
    I2sCapture u_Capture (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bclk_i(bclk),
        .ws_i(ws),
        .sd_i(sd),

        .capture_data_o(capture_data),
        .capture_done_o(capture_done)
    );

    initial begin
        clk = 0;
        rst_n = 0;
        sd = 0;
        #15

        // testing
        rst_n = 1;
        send_data(data1);
        send_data(data2);
        @(negedge ws);
        $stop;
    end

    always #10 clk = ~clk;
endmodule
