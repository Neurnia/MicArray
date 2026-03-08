// RawPcmUartTop.v
// Capture I2S samples for a fixed window after reset and stream them out over UART.
// Data format on UART: 0xA5, sample[23:16], sample[15:8], sample[7:0], 0x0A per sample.

module RawPcmUartTop #(
    parameter integer CLK_HZ          = 50_000_000,
    parameter integer BAUD_HZ         = 921_600,
    parameter integer SAMPLE_RATE_HZ  = 16_000,
    parameter integer RECORD_SECONDS  = 1,
    parameter integer FIFO_ADDR_WIDTH = 10
) (
    input  wire clk_sys_i,
    input  wire rst_n_i,
    input  wire uart_rx_i,     // unused, keeps pin assignment happy
    output reg  [3:0] led_n_o, // active-low LEDs
    // I2S interface to microphones
    output wire i2s_bclk_o,
    output wire i2s_ws_o,
    input  wire i2s_sd0_i,
    // UART toward PC
    output wire uart_tx_o
);

    // ----------------------------------------------------------------
    // Generate I2S clocks.
    // Note: I2sClockGen uses WS_HZ as the *BCLK* target. WS toggles every
    // 32 BCLK falling edges (64 clocks per stereo frame), so set WS_HZ to
    // SAMPLE_RATE_HZ * 64 to achieve the desired LRCLK.
    localparam integer I2S_WS_PARAM = SAMPLE_RATE_HZ * 64;
    I2sClockGen #(
        .CLK_HZ(CLK_HZ),
        .WS_HZ (I2S_WS_PARAM)
    ) u_clkgen (
        .clk_i (clk_sys_i),
        .rst_n_i (rst_n_i),
        .bclk_o (i2s_bclk_o),
        .ws_o   (i2s_ws_o)
    );

    // ----------------------------------------------------------------
    // Capture left-channel I2S samples (24-bit).
    wire [23:0] i2s_sample;
    wire        i2s_sample_valid;

    I2sCapture #(
        .CHANNEL_SELECT(0)  // 0 = WS low
    ) u_capture (
        .clk_i         (clk_sys_i),
        .rst_n_i       (rst_n_i),
        .bclk_i        (i2s_bclk_o),
        .ws_i          (i2s_ws_o),
        .sd_i          (i2s_sd0_i),
        .sample_data_o (i2s_sample),
        .sample_valid_o(i2s_sample_valid)
    );

    // ----------------------------------------------------------------
    // Recording window control: capture for RECORD_SECONDS after reset.
    localparam integer RECORD_CLKS = CLK_HZ * RECORD_SECONDS;
    reg [31:0] record_cnt;
    reg        capture_en;

    always @(posedge clk_sys_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            record_cnt <= 32'd0;
            capture_en <= 1'b1;
        end else if (capture_en) begin
            if (record_cnt >= RECORD_CLKS - 1) begin
                capture_en <= 1'b0;
            end else begin
                record_cnt <= record_cnt + 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // FIFO between capture and UART.
    wire fifo_wr_ready;
    wire fifo_rd_ready;
    wire fifo_rd_valid;
    wire [23:0] fifo_rd_data;
    wire [FIFO_ADDR_WIDTH:0] fifo_level;
    wire fifo_overflow, fifo_underflow;

    SampleRamFifo #(
        .DATA_WIDTH(24),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_fifo (
        .clk_i      (clk_sys_i),
        .rst_n_i    (rst_n_i),
        .wr_valid_i (capture_en && i2s_sample_valid),
        .wr_data_i  (i2s_sample),
        .wr_ready_o (fifo_wr_ready),
        .overflow_o (fifo_overflow),
        .rd_ready_i (fifo_rd_ready),
        .rd_valid_o (fifo_rd_valid),
        .rd_data_o  (fifo_rd_data),
        .underflow_o(fifo_underflow),
        .level_o    (fifo_level)
    );

    // ----------------------------------------------------------------
    // UART streaming: integrated UART (no external handshakes).
    wire streamer_ready;
    wire frame_sent;
    wire send_now = fifo_rd_valid && streamer_ready;

    assign fifo_rd_ready = send_now;

    PcmUartFramedTx #(
        .CLK_HZ (CLK_HZ),
        .BAUD_HZ(BAUD_HZ)
    ) u_uart_stream (
        .clk_i         (clk_sys_i),
        .rst_n_i       (rst_n_i),
        .sample_data_i (fifo_rd_data),
        .sample_valid_i(send_now),
        .sample_ready_o(streamer_ready),
        .uart_tx_o     (uart_tx_o),
        .frame_sent_o  (frame_sent)
    );

    // ----------------------------------------------------------------
    // Misc assigns
    // ----------------------------------------------------------------
    // Simple status LEDs: on (low) while capturing, overflow/underflow indicators.
    always @(posedge clk_sys_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            led_n_o <= 4'b1111;
        end else begin
            led_n_o[0] <= ~capture_en;
            led_n_o[1] <= ~fifo_overflow;
            led_n_o[2] <= ~fifo_underflow;
            led_n_o[3] <= 1'b1;
        end
    end

endmodule
