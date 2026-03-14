// tb_RecordControl.sv
// Self-checking test bench for RecordControl.sv

`timescale 1ns / 1ps

module tb_RecordControl;

    localparam int WindowLength = 2;
    localparam int MicCnt = 2;
    localparam int SampleWidth = 16;

    logic                                   clk;
    logic                                   rst_n;
    logic                                   frame_change;
    logic                                   record_start;
    logic [MicCnt - 1:0][SampleWidth - 1:0] frame_data;

    logic                                   record_done;
    logic                                   record_error;
    logic [MicCnt - 1:0][SampleWidth - 1:0] record_data;

    logic                                   frame_ready;
    logic                                   frame_valid;
    logic                                   frame_error;

    logic                                   record_ready;
    logic                                   record_valid;

    RecordControl #(
        .WINDOW_LENGTH(WindowLength),
        .MIC_CNT      (MicCnt),
        .SAMPLE_WIDTH (SampleWidth)
    ) u_dut (
        .clk_i         (clk),
        .rst_n_i       (rst_n),
        .frame_change_i(frame_change),
        .record_start_i(record_start),
        .frame_data_i  (frame_data),
        .record_done_o (record_done),
        .record_error_o(record_error),
        .record_data_o (record_data),
        .frame_ready_o (frame_ready),
        .frame_valid_i (frame_valid),
        .frame_error_i (frame_error),
        .record_ready_i(record_ready),
        .record_valid_o(record_valid)
    );

    // record start pulse
    task automatic pulse_record_start;
        @(negedge clk);
        record_start <= 1'b1;
        @(negedge clk);
        record_start <= 1'b0;
    endtask

    // frame change pulse
    task automatic pulse_frame_change;
        @(negedge clk);
        frame_change <= 1'b1;
        @(negedge clk);
        frame_change <= 1'b0;
    endtask

    // normal frame with 2 channels
    task automatic drive_good_frame(input logic [SampleWidth - 1:0] ch0,
                                    input logic [SampleWidth - 1:0] ch1);
        @(negedge clk);
        frame_data[0] <= ch0;
        frame_data[1] <= ch1;
        frame_valid   <= 1'b1;

        @(posedge clk);
        #1;
        if (frame_ready !== 1'b1) begin
            $fatal(1, "Expected frame_ready during a good frame handshake.");
        end

        @(negedge clk);
        frame_valid <= 1'b0;
    endtask

    // check commit and give write ready signals
    task automatic commit_record(input logic expected_error, input logic expected_done,
                                 input logic [SampleWidth - 1:0] ch0,
                                 input logic [SampleWidth - 1:0] ch1);
        @(posedge clk);
        #1;
        if (record_valid !== 1'b1) begin
            $fatal(1, "Expected record_valid in COMMITTING state.");
        end
        if (record_error !== expected_error) begin
            $fatal(1, "record_error mismatch. expected=%0d got=%0d", expected_error, record_error);
        end
        if (!expected_error) begin
            if (record_data[0] !== ch0 || record_data[1] !== ch1) begin
                $fatal(1, "record_data mismatch. got %h %h", record_data[0], record_data[1]);
            end
        end

        // write simulation
        @(negedge clk);
        record_ready <= 1'b1;
        @(posedge clk);
        #1;
        if (record_done !== expected_done) begin
            $fatal(1, "record_done mismatch. expected=%0d got=%0d", expected_done, record_done);
        end
        @(negedge clk);
        record_ready <= 1'b0;
    endtask

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b0;
        frame_change = 1'b0;
        record_start = 1'b0;
        frame_data   = '0;
        frame_valid  = 1'b0;
        frame_error  = 1'b0;
        record_ready = 1'b0;

        #25;
        rst_n = 1'b1;

        // Start recording and enter the first collecting slot.
        pulse_record_start();
        pulse_frame_change();

        // 1.good frame, then commit it.
        drive_good_frame(16'h1111, 16'h2222);
        pulse_frame_change();
        commit_record(1'b0, 1'b0, 16'h1111, 16'h2222);

        // 2.no good frame arrives, report an error and finish the window.
        pulse_frame_change();
        @(negedge clk);
        frame_error <= 1'b1;
        @(negedge clk);
        frame_error <= 1'b0;
        commit_record(1'b1, 1'b1, '0, '0);

        @(posedge clk);
        #1;
        if (record_valid !== 1'b0) begin
            $fatal(1, "record_valid should drop after the final commit.");
        end

        $display("tb_RecordControl passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
