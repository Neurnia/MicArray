// tb_UartSender.sv
// Self-checking test bench for UartSender.sv

`timescale 1ns / 1ps

module tb_UartSender;

    localparam int ClkHz = 100;
    localparam int BaudHz = 10;
    localparam int DataWidth = 16;
    localparam int MicCnt = 2;
    localparam int WindowLength = 2;
    localparam int FrameWords = MicCnt + 1;
    localparam int PayloadWords = WindowLength * FrameWords;
    localparam int BaudCycles = ClkHz / BaudHz;

    logic clk;
    logic rst_n;
    logic uart_busy;
    logic uart_window_done;

    logic payload_valid;
    logic payload_ready;
    logic [DataWidth-1:0] payload_data;

    logic uart_tx;
    logic window_done_seen;

    logic [DataWidth-1:0] payload_q[$];
    logic [7:0] expected_bytes[$];

    UartSender #(
        .CLK_HZ(ClkHz),
        .BAUD_HZ(BaudHz),
        .DATA_WIDTH(DataWidth),
        .MIC_CNT(MicCnt),
        .WINDOW_LENGTH(WindowLength)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .uart_busy_o(uart_busy),
        .uart_window_done_o(uart_window_done),
        .payload_valid_i(payload_valid),
        .payload_ready_o(payload_ready),
        .payload_data_i(payload_data),
        .uart_tx_o(uart_tx)
    );

    always_comb begin
        payload_valid = (payload_q.size() != 0);
        payload_data = payload_valid ? payload_q[0] : '0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_q = {};
            window_done_seen <= 1'b0;
        end else if (payload_valid && payload_ready) begin
            void'(payload_q.pop_front());
            if (uart_window_done) begin
                window_done_seen <= 1'b1;
            end
        end else if (uart_window_done) begin
            window_done_seen <= 1'b1;
        end
    end

    task automatic enqueue_word(input logic [DataWidth-1:0] word);
        begin
            @(negedge clk);
            payload_q.push_back(word);
        end
    endtask

    task automatic expect_idle_tx(input int cycles);
        int i;
        begin
            for (i = 0; i < cycles; i++) begin
                @(posedge clk);
                #1;
                if (uart_tx !== 1'b1) begin
                    $fatal(1, "uart_tx should stay high when idle. cycle=%0d", i);
                end
                if (uart_busy !== 1'b0) begin
                    $fatal(1, "uart_busy should stay low when idle. cycle=%0d", i);
                end
            end
        end
    endtask

    task automatic expect_uart_byte(input logic [7:0] expected_byte);
        int bit_i;
        logic [7:0] captured_byte;
        int timeout;
        begin
            timeout = 0;
            while (uart_tx !== 1'b0) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 3000) begin
                    $fatal(1, "Timed out waiting for UART start bit.");
                end
            end

            repeat (BaudCycles / 2) begin
                @(posedge clk);
            end
            #1;
            if (uart_tx !== 1'b0) begin
                $fatal(1, "UART start bit is not held low at mid-bit sample.");
            end

            for (bit_i = 0; bit_i < 8; bit_i++) begin
                repeat (BaudCycles) begin
                    @(posedge clk);
                end
                #1;
                captured_byte[bit_i] = uart_tx;
            end

            repeat (BaudCycles) begin
                @(posedge clk);
            end
            #1;
            if (uart_tx !== 1'b1) begin
                $fatal(1, "UART stop bit is not high.");
            end

            if (captured_byte !== expected_byte) begin
                $fatal(1, "UART byte mismatch. expected=%h got=%h", expected_byte, captured_byte);
            end
        end
    endtask

    task automatic expect_done_pulse;
        int timeout;
        begin
            timeout = 0;
            while (window_done_seen !== 1'b1) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 1000) begin
                    $fatal(1, "Timed out waiting for uart_window_done pulse.");
                end
            end

            timeout = 0;
            while (uart_window_done !== 1'b1) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 1000) begin
                    $fatal(1, "Timed out waiting for visible uart_window_done pulse.");
                end
            end

            @(posedge clk);
            #1;
            if (uart_window_done !== 1'b0) begin
                $fatal(1, "uart_window_done should be a one-cycle pulse.");
            end
        end
    endtask

    task automatic expect_done_seen;
        int timeout;
        begin
            timeout = 0;
            while (window_done_seen !== 1'b1) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 1000) begin
                    $fatal(1, "Timed out waiting for uart_window_done pulse.");
                end
            end
        end
    endtask

    task automatic expect_all_bytes;
        logic [7:0] expected_byte;
        begin
            while (expected_bytes.size() != 0) begin
                expected_byte = expected_bytes.pop_front();
                expect_uart_byte(expected_byte);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;

        #40;
        rst_n = 1'b1;

        expect_idle_tx(5);

        enqueue_word(16'h1111);
        enqueue_word(16'h2222);
        enqueue_word(16'h3333);
        enqueue_word(16'h4444);
        enqueue_word(16'h5555);
        enqueue_word(16'h6666);

        expected_bytes.push_back(8'hA5);
        expected_bytes.push_back(8'h5A);
        expected_bytes.push_back(8'h00);
        expected_bytes.push_back(8'h03);
        expected_bytes.push_back(8'h11);
        expected_bytes.push_back(8'h11);
        expected_bytes.push_back(8'h22);
        expected_bytes.push_back(8'h22);
        expected_bytes.push_back(8'h33);
        expected_bytes.push_back(8'h33);
        expected_bytes.push_back(8'h44);
        expected_bytes.push_back(8'h44);
        expected_bytes.push_back(8'h55);
        expected_bytes.push_back(8'h55);
        expected_bytes.push_back(8'h66);
        expected_bytes.push_back(8'h66);

        expect_all_bytes();
        expect_done_seen();

        if (payload_q.size() != 0) begin
            $fatal(1, "Payload queue should be empty after one window send. size=%0d",
                   payload_q.size());
        end
        if (uart_busy !== 1'b0) begin
            $fatal(1, "uart_busy should return low after transmission.");
        end

        expect_idle_tx(5);

        $display("tb_UartSender passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
