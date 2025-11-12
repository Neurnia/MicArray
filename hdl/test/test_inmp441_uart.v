// test_inmp441_uart.v
// Generates INMP441 clocks, captures one microphone slot, and streams
// decimated samples over the on-board UART for inspection on a PC.

module TestInmp441Uart #(
        parameter integer INPUT_CLK_HZ   = 50_000_000,
        parameter integer TARGET_BCLK_HZ = 3_072_000,
        parameter integer DECIMATE       = 8,          // send every Nth sample
        parameter integer CHANNEL_SELECT = 0           // 0 = left
    )(
        input  wire        clk50,
        input  wire        rst_n,
        input  wire        i2s_sd0,
        output wire        i2s_bclk,
        output wire        i2s_ws,
        output wire        i2s_lr_sel,
        output wire        uart_tx,
        output reg  [3:0]  led
    );

    wire bclk, ws;
    Inmp441ClockGen #(
        .INPUT_CLK_HZ   (INPUT_CLK_HZ),
        .TARGET_BCLK_HZ (TARGET_BCLK_HZ)
    ) clkgen (
        .clk   (clk50),
        .rst_n (rst_n),
        .bclk  (bclk),
        .ws    (ws)
    );

    assign i2s_bclk   = bclk;
    assign i2s_ws     = ws;
    assign i2s_lr_sel = CHANNEL_SELECT[0];

    wire [23:0] sample_data;
    wire sample_valid;
    Inmp441Capture #(
        .CHANNEL_SELECT (CHANNEL_SELECT)
    ) capture (
        .clk          (clk50),
        .rst_n        (rst_n),
        .bclk         (bclk),
        .ws           (ws),
        .sd           (i2s_sd0),
        .sample_data  (sample_data),
        .sample_valid (sample_valid)
    );

    // Decimate samples before sending over UART
    reg [$clog2(DECIMATE)-1:0] decim_cnt;
    reg start_frame;

    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            decim_cnt  <= 0;
            start_frame <= 1'b0;
        end else begin
            start_frame <= 1'b0;
            if (sample_valid) begin
                if (decim_cnt == DECIMATE - 1) begin
                    decim_cnt  <= 0;
                    start_frame <= 1'b1;
                end else begin
                    decim_cnt <= decim_cnt + 1'b1;
                end
            end
        end
    end

    // Reduce 24-bit sample to signed 16-bit by keeping the lower 16 bits.
    wire [15:0] sample16 = sample_data[15:0];

    // Simple frame: 0xA5, sample16[15:8], sample16[7:0], '\n'
    reg [7:0] frame_bytes [0:3];
    reg [1:0] frame_idx;
    reg sending;

    wire uart_busy;
    reg  uart_valid;
    reg [7:0] uart_data;

    UartTx #(
        .CLK_HZ  (INPUT_CLK_HZ),
        .BAUD_HZ (115_200)
    ) uart (
        .clk        (clk50),
        .rst_n      (rst_n),
        .data_in    (uart_data),
        .data_valid (uart_valid),
        .tx         (uart_tx),
        .busy       (uart_busy)
    );

    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            frame_idx  <= 2'd0;
            sending    <= 1'b0;
            uart_valid <= 1'b0;
            uart_data  <= 8'h00;
        end else begin
            uart_valid <= 1'b0;

            if (start_frame) begin
                frame_bytes[0] <= 8'hA5;
                frame_bytes[1] <= sample16[15:8];
                frame_bytes[2] <= sample16[7:0];
                frame_bytes[3] <= 8'h0A;
                frame_idx      <= 2'd0;
                sending        <= 1'b1;
            end

            if (sending && !uart_busy) begin
                uart_data  <= frame_bytes[frame_idx];
                uart_valid <= 1'b1;
                if (frame_idx == 2'd3) begin
                    sending   <= 1'b0;
                end else begin
                    frame_idx <= frame_idx + 1'b1;
                end
            end
        end
    end

    // LED feedback: LED0 toggles on sample_valid, LED1 toggles when frame sent
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            led <= 4'b0000;
        end else begin
            if (sample_valid)
                led[0] <= ~led[0];
            if (start_frame)
                led[1] <= ~led[1];
        end
    end

endmodule
