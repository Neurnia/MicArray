// tb_UartReceiver.sv
// Self-checking test bench for UartReceiver.sv

`timescale 1ns / 1ps

module tb_UartReceiver;

    localparam int ClkHz = 100;
    localparam int BaudHz = 10;
    localparam int ClksPerBit = ClkHz / BaudHz;

    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_busy;
    logic start_record;

    int start_count;

    UartReceiver #(
        .CLK_HZ(ClkHz),
        .BAUD_HZ(BaudHz)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .uart_rx_i(uart_rx),
        .uart_busy_i(uart_busy),
        .start_record_o(start_record)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_count <= 0;
        end else if (start_record) begin
            start_count <= start_count + 1;
        end
    end

    task automatic send_uart_byte(input logic [7:0] byte_data);
        begin
            @(negedge clk);
            uart_rx <= 1'b0;
            repeat (ClksPerBit) @(negedge clk);

            for (int bit_i = 0; bit_i < 8; bit_i++) begin
                uart_rx <= byte_data[bit_i];
                repeat (ClksPerBit) @(negedge clk);
            end

            uart_rx <= 1'b1;
            repeat (ClksPerBit) @(negedge clk);
        end
    endtask

    task automatic send_start_command;
        begin
            send_uart_byte("S");
            send_uart_byte("T");
            send_uart_byte("A");
            send_uart_byte("R");
            send_uart_byte("T");
            send_uart_byte("\n");
        end
    endtask

    task automatic expect_start_count(input int expected_count, input int timeout_cycles);
        int waited;
        begin
            waited = 0;
            while (start_count != expected_count) begin
                @(posedge clk);
                #1;
                waited++;
                if (waited > timeout_cycles) begin
                    $fatal(1, "Timed out waiting for start_count=%0d (current=%0d).",
                           expected_count, start_count);
                end
            end
        end
    endtask

    task automatic expect_no_new_start(input int stable_cycles, input string label);
        int base_count;
        begin
            base_count = start_count;
            repeat (stable_cycles) begin
                @(posedge clk);
                #1;
                if (start_count != base_count) begin
                    $fatal(1, "Unexpected start pulse during %s.", label);
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        uart_rx = 1'b1;
        uart_busy = 1'b0;

        #40;
        rst_n = 1'b1;

        send_start_command();
        expect_start_count(1, 50);

        send_uart_byte("S");
        send_uart_byte("T");
        send_uart_byte("A");
        send_uart_byte("R");
        send_uart_byte("\n");
        expect_no_new_start(20, "invalid STAR\\n command");

        send_uart_byte("s");
        send_uart_byte("t");
        send_uart_byte("a");
        send_uart_byte("r");
        send_uart_byte("t");
        send_uart_byte("\n");
        expect_no_new_start(20, "lower-case start\\n command");

        uart_busy = 1'b1;
        send_start_command();
        uart_busy = 1'b0;
        expect_no_new_start(20, "busy-time START\\n command");

        send_uart_byte("S");
        send_uart_byte("T");
        send_uart_byte("A");
        uart_busy = 1'b1;
        repeat (5) @(posedge clk);
        uart_busy = 1'b0;
        send_uart_byte("R");
        send_uart_byte("T");
        send_uart_byte("\n");
        expect_no_new_start(20, "partial command after busy reset");

        send_start_command();
        expect_start_count(2, 50);

        $display("tb_UartReceiver passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
