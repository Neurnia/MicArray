// tb_RecordPacker.sv
// Self-checking test bench for RecordPacker.sv

`timescale 1ns / 1ps

module tb_RecordPacker;

    localparam int MicCnt = 3;
    localparam int SampleWidth = 16;
    localparam int WordWidth = 16;

    logic                                      clk;
    logic                                      rst_n;
    logic                                      record_done;
    logic [   MicCnt - 1:0][SampleWidth - 1:0] record_data;

    logic                                      pack_done;
    logic [WordWidth - 1:0]                    pack_data;

    logic                                      record_ready;
    logic                                      record_valid;
    logic                                      record_error;

    logic                                      pack_ready;
    logic                                      pack_valid;

    RecordPacker #(
        .MIC_CNT     (MicCnt),
        .SAMPLE_WIDTH(SampleWidth),
        .WORD_WIDTH  (WordWidth)
    ) u_dut (
        .clk_i         (clk),
        .rst_n_i       (rst_n),
        .record_done_i (record_done),
        .record_data_i (record_data),
        .pack_done_o   (pack_done),
        .pack_data_o   (pack_data),
        .record_ready_o(record_ready),
        .record_valid_i(record_valid),
        .record_error_i(record_error),
        .pack_ready_i  (pack_ready),
        .pack_valid_o  (pack_valid)
    );

    // upstream
    task automatic send_record(input logic expected_error, input logic [SampleWidth - 1:0] ch0,
                               input logic [SampleWidth - 1:0] ch1,
                               input logic [SampleWidth - 1:0] ch2);
        begin
            @(negedge clk);
            record_data[0] <= ch0;
            record_data[1] <= ch1;
            record_data[2] <= ch2;
            record_error   <= expected_error;
            record_valid   <= 1'b1;

            @(posedge clk);
            #1;
            if (record_ready !== 1'b1) begin
                $fatal(1, "Expected record_ready during record handshake.");
            end

            @(negedge clk);
            record_valid <= 1'b0;
            record_error <= 1'b0;
        end
    endtask

    task automatic pulse_record_done;
        @(negedge clk);
        record_done <= 1'b1;
        @(negedge clk);
        record_done <= 1'b0;
    endtask

    // check
    task automatic expect_word(input logic [WordWidth - 1:0] expected_word, input int stall_cycles,
                               input logic expected_done);
        begin
            while (pack_valid !== 1'b1) begin
                @(posedge clk);
                #1;
            end

            repeat (stall_cycles) begin
                @(posedge clk);
                #1;
                if (pack_valid !== 1'b1) begin
                    $fatal(1, "pack_valid dropped during downstream backpressure.");
                end
                if (pack_data !== expected_word) begin
                    $fatal(1,
                           "pack_data changed during downstream backpressure. expected=%h got=%h",
                           expected_word, pack_data);
                end
                if (pack_done !== 1'b0) begin
                    $fatal(1, "pack_done should stay low before the final word handshake.");
                end
            end

            @(negedge clk);
            if (pack_valid !== 1'b1) begin
                $fatal(1, "Expected pack_valid before downstream handshake.");
            end
            if (pack_data !== expected_word) begin
                $fatal(1, "pack_data mismatch before handshake. expected=%h got=%h", expected_word,
                       pack_data);
            end
            pack_ready <= 1'b1;
            @(posedge clk);
            #1;
            if (pack_done !== expected_done) begin
                $fatal(1, "pack_done mismatch. expected=%0d got=%0d", expected_done, pack_done);
            end
            @(negedge clk);
            pack_ready <= 1'b0;
        end
    endtask

    initial begin
        clk          = 1'b0;
        rst_n        = 1'b0;
        record_done  = 1'b0;
        record_data  = '0;
        record_valid = 1'b0;
        record_error = 1'b0;
        pack_ready   = 1'b0;

        #25;
        rst_n = 1'b1;

        @(posedge clk);
        #1;
        if (record_ready !== 1'b1) begin
            $fatal(1, "RecordPacker should be ready for a frame after reset.");
        end

        // frame 1: no error, not the end of window
        send_record(1'b0, 16'h1111, 16'h2222, 16'h3333);
        expect_word(16'h0000, 1, 1'b0);
        expect_word(16'h1111, 0, 1'b0);
        expect_word(16'h2222, 2, 1'b0);
        expect_word(16'h3333, 0, 1'b0);

        @(posedge clk);
        #1;
        if (record_ready !== 1'b1) begin
            $fatal(1, "RecordPacker should return to ready after one frame is packed.");
        end

        // frame 2: error flagged, mark end of window while packing this frame
        // Protocol note:
        // - The first word is the error flag word.
        // - When the error word is non-zero, downstream must ignore the following payload words.
        // - This test still checks that the payload ordering stays stable under backpressure.
        send_record(1'b1, 16'hAAAA, 16'hBBBB, 16'hCCCC);
        pulse_record_done();
        expect_word(16'h8000, 0, 1'b0);
        expect_word(16'hAAAA, 0, 1'b0);
        expect_word(16'hBBBB, 1, 1'b0);
        expect_word(16'hCCCC, 0, 1'b1);

        @(posedge clk);
        #1;
        if (pack_done !== 1'b0) begin
            $fatal(1, "pack_done should drop after the completion pulse.");
        end
        if (record_ready !== 1'b1) begin
            $fatal(1, "RecordPacker should be ready again after the final frame.");
        end

        $display("tb_RecordPacker passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
