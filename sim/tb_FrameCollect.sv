// tb_FrameCollect.sv
// Test bench for FrameCollect.sv
// 4 microphones

`timescale 1ns / 1ps

module tb_FrameCollect;

    localparam int MicCnt = 4;
    localparam int SampleWidth = 16;

    // test input
    logic                                   clk;
    logic                                   rst_n;
    logic                                   frame_change;
    logic [MicCnt - 1:0][SampleWidth - 1:0] sample_data_array;
    logic [MicCnt - 1:0]                    sample_valid_array;

    // output
    logic [MicCnt - 1:0][SampleWidth - 1:0] frame_data;
    logic                                   frame_error;

    // shake hand
    logic                                   frame_ready;
    logic                                   frame_valid;

    // generate the clock
    logic                                   bclk;
    logic                                   ws;
    I2sClockGen u_I2sClockGen (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ws_o(ws),
        .bclk_o(bclk)
    );

    //device under test
    FrameCollect #(
        .MIC_CNT(MicCnt),
        .SAMPLE_WIDTH(SampleWidth)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .frame_change_i(frame_change),
        .sample_data_i(sample_data_array),
        .sample_valid_i(sample_valid_array),

        .frame_data_o (frame_data),
        .frame_error_o(frame_error),

        .frame_ready_i(frame_ready),
        .frame_valid_o(frame_valid)
    );

    // find the time to send data
    task automatic data_send_time();
        @(negedge frame_change);
        for (int i = 0; i < 16; i++) begin
            @(negedge bclk);
        end
    endtask  //automatic

    // hand shake & check
    task automatic hand_shake();
        if (!frame_valid) begin
            @(posedge frame_valid);
        end
        @(posedge clk);
        frame_ready = 1'b1;
        @(posedge clk);
        frame_ready = 1'b0;

        // check
        @(posedge clk);
        if (frame_valid !== 1'b0) begin
            $fatal(1, "hand shake failed.");
        end
    endtask  //automatic

    // sample valid pulse
    task automatic sample_valid_pulse(input int ch);
        @(posedge clk);
        sample_valid_array[ch] <= 1'b1;
        @(posedge clk);
        sample_valid_array[ch] <= 1'b0;
    endtask  //automatic

    // frame check
    task automatic frame_check(input logic [15:0] ch0, input logic [15:0] ch1,
                               input logic [15:0] ch2, input logic [15:0] ch3);
        begin
            // wait for signal
            if (!frame_valid) begin
                @(posedge frame_valid);
            end
            if (frame_data[0] !== ch0 ||
            frame_data[1] !== ch1 ||
            frame_data[2] !== ch2 ||
            frame_data[3] !== ch3) begin
                $fatal(1, "frame_data mismatch.");
            end
        end
    endtask  //automatic

    initial begin
        clk = 0;
        rst_n = 0;
        sample_data_array = '0;
        sample_valid_array = '0;
        frame_ready = 0;
        frame_change = 0;
        #20

        // start test
        rst_n = 1;
        data_send_time();
        sample_data_array[0] = 16'h1111;
        sample_valid_pulse(0);
        @(negedge clk);  // simulate delay
        sample_data_array[1] = 16'h2222;
        sample_valid_pulse(1);
        sample_data_array[2] = 16'h3333;
        sample_valid_pulse(2);
        @(negedge clk);  // simulate delay
        sample_data_array[3] = 16'h4444;
        sample_valid_pulse(3);
        // self-check
        frame_check(16'h1111, 16'h2222, 16'h3333, 16'h4444);
        hand_shake();

        // another frame
        data_send_time();
        sample_data_array[0] = 16'hAAAA;
        sample_valid_pulse(0);
        sample_data_array[1] = 16'hBBBB;
        sample_valid_pulse(1);
        @(negedge clk);  // simulate delay
        sample_data_array[2] = 16'hCCCC;
        sample_valid_pulse(2);
        sample_data_array[3] = 16'hDDDD;
        sample_valid_pulse(3);
        // self check
        frame_check(16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD);
        hand_shake();

        // simulate incomplete frame
        data_send_time();
        sample_data_array[0] = 16'h1111;
        sample_valid_pulse(0);
        sample_data_array[1] = 16'h2222;
        sample_valid_pulse(1);
        sample_data_array[2] = 16'h3333;
        sample_valid_pulse(2);

        @(negedge frame_change);
        @(posedge clk);
        if (frame_error !== 1'b1) begin
            $fatal(1, "error detection failed.");
        end
        @(negedge bclk);
        $stop;
    end

    // clock
    always #10 clk = ~clk;

    // frame change
    always @(negedge ws) begin
        frame_change = 1'b1;
        @(posedge clk) frame_change = 1'b0;
    end

endmodule
