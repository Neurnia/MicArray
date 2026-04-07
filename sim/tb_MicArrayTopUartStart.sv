// tb_MicArrayTopUartStart.sv
// Top-level integration check for UART-triggered record start.

`timescale 1ns / 1ps

module tb_MicArrayTopUartStart;

    localparam int MicCnt = 2;
    localparam int SubArrayCnt = 1;
    localparam int SampleWidth = 16;
    localparam int WindowLength = 2;
    localparam int FifoDepth = 16;
    localparam int SdramAddrW = 24;
    localparam int SdramRcW = 13;
    localparam int SdramBankW = 2;
    localparam int ClkHz = 100;
    localparam int UartBaudHz = 10;
    localparam int BclkHz = 20;
    localparam int ClksPerBit = ClkHz / UartBaudHz;

    logic clk;
    logic rst_n;
    logic key_n;

    logic [MicCnt - 1:0] i2s_sd;
    logic [SubArrayCnt - 1:0] i2s_bclk;
    logic [SubArrayCnt - 1:0] i2s_ws;

    logic uart_rx;
    logic uart_tx;

    logic [2:0] led_n;

    logic sdram_clk;
    logic sdram_cke;
    logic sdram_cs_n;
    logic sdram_ras_n;
    logic sdram_cas_n;
    logic sdram_we_n;
    logic [SdramBankW - 1:0] sdram_ba;
    logic [SdramRcW - 1:0] sdram_addr;
    logic [(SampleWidth / 8) - 1:0] sdram_dqm;
    tri [SampleWidth - 1:0] sdram_data;

    int record_start_count;

    MicArrayTop #(
        .MIC_CNT(MicCnt),
        .SUB_ARRAY_CNT(SubArrayCnt),
        .SAMPLE_WIDTH(SampleWidth),
        .WINDOW_LENGTH(WindowLength),
        .FIFO_DEPTH(FifoDepth),
        .SDRAM_ADDR_W(SdramAddrW),
        .SDRAM_RC_W(SdramRcW),
        .SDRAM_BANK_W(SdramBankW),
        .CLK_HZ(ClkHz),
        .UART_BAUD_HZ(UartBaudHz),
        .BCLK_HZ(BclkHz)
    ) dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .key_n_i(key_n),
        .i2s_sd_i(i2s_sd),
        .i2s_bclk_o(i2s_bclk),
        .i2s_ws_o(i2s_ws),
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx),
        .led_n_o(led_n),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_ba(sdram_ba),
        .sdram_addr(sdram_addr),
        .sdram_dqm(sdram_dqm),
        .sdram_data(sdram_data)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            record_start_count <= 0;
        end else if (dut.record_start) begin
            record_start_count <= record_start_count + 1;
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

    task automatic expect_record_start_count(input int expected_count, input int timeout_cycles);
        int waited;
        begin
            waited = 0;
            while (record_start_count != expected_count) begin
                @(posedge clk);
                #1;
                waited++;
                if (waited > timeout_cycles) begin
                    $fatal(1, "Timed out waiting for record_start_count=%0d (current=%0d).",
                           expected_count, record_start_count);
                end
            end
        end
    endtask

    task automatic expect_no_new_record_start(input int stable_cycles, input string label);
        int base_count;
        begin
            base_count = record_start_count;
            repeat (stable_cycles) begin
                @(posedge clk);
                #1;
                if (record_start_count != base_count) begin
                    $fatal(1, "Unexpected record_start pulse during %s.", label);
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        key_n = 1'b1;
        i2s_sd = '0;
        uart_rx = 1'b1;

        #40;
        rst_n = 1'b1;

        @(negedge clk);
        key_n <= 1'b0;
        repeat (20) @(negedge clk);
        key_n <= 1'b1;
        expect_no_new_record_start(20, "legacy key trigger");

        force dut.uart_busy = 1'b1;
        send_start_command();
        expect_no_new_record_start(20, "busy-time UART command");
        release dut.uart_busy;

        send_start_command();
        expect_record_start_count(1, 50);

        @(posedge clk);
        #1;
        if (dut.recording !== 1'b1) begin
            $fatal(1, "Top-level recording flag should latch high after UART start.");
        end
        if (led_n[0] !== 1'b0) begin
            $fatal(1, "LED[0] should indicate recording after UART start.");
        end

        $display("tb_MicArrayTopUartStart passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
