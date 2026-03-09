// tb_I2sCapture.sv.
// Test bench for I2sCapture.sv.
// Simulate two complete data sending process.

// time unit / time precision
// time unit: numbers shown in the code.
// time precision: how precise simulator works.
`timescale 1ns / 1ps
// or write like:
// timeunit 1ns;
// timeprecision 1ps;

module tb_I2sCapture;

    // test input
    logic        clk;
    logic        rst_n;
    logic        bclk;
    logic        ws;
    logic        sd;
    // test output
    logic [15:0] sample_data;
    logic        sample_valid;

    // test data
    logic [23:0] data1 = 24'b1010_1010_1010_1010_1010_1010;
    logic [23:0] data2 = 24'b0101_0101_0101_0101_0101_0101;

    // data sending task (one ws period)
    // "automatic" stands for automatic allocate & deallocate
    task automatic send_data(
        input logic [23:0] data
    );
        begin
            // left channel
            for (int j = 31; j>=0; j--) begin
                @(negedge bclk);
                if (j == 31) begin
                    ws <= ~ws;
                end else if (j < 31 && j >= 7) begin
                    sd <= data[j - 7];
                end else begin
                    sd <= 0;
                end
            end
            // right channel
            for (int j = 31; j>=0; j--) begin
                @(negedge bclk);
                if (j == 31) begin
                    ws <= ~ws;
                end else begin
                    sd <= 0;
                end
            end
        end
    endtask //automatic

    // device under test
    I2sCapture u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bclk_i(bclk),
        .ws_i(ws),
        .sd_i(sd),

        .sample_data_o (sample_data),
        .sample_valid_o(sample_valid)
    );

    initial begin
        // initialize
        clk = 0;
        bclk = 0;
        rst_n = 0;
        ws = 1;
        sd =0;
        #10 // wait for 10 units

        // start a period
        rst_n = 1;
        #10

        // send the data (24 bits)
        // test if dut can cut the data at the right time
        send_data(data1);
        send_data(data2);
        // stop the simulation
        @(negedge bclk);
        $stop;
    end;

    // #HALF_PERIOD, showing the signal flips every half period
    // #10ns or #10us is also acceptable
    always #10 clk = ~clk; // 50MHz
    always #31.24us bclk = ~bclk; // around 16kHz

endmodule
