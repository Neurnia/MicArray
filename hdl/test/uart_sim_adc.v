// adc_uart_stream.v
// Synthesises sample ADC frames and streams them to the PC over UART.
// Frame format (little-endian):
//   [0]  0xAA (sync)
//   [1]  0x55 (sync)
//   [2]  frame counter LSB
//   [3]  frame counter MSB
//   For each of CHANNELS channels:
//       low byte, high byte of the 16-bit sample value
//   [last-2] 0x0D (CR)
//   [last-1] 0x0A (LF)
// Samples are synthesised in ANCILLARY logic (monotonic ramp) to mimic ADC output.

module AdcUartStream #(
    parameter integer CHANNELS            = 8,         // number of 16-bit channels
    parameter integer BAUD_DIV            = 434,       // 50 MHz / 115200 ≈ 434
    parameter integer FRAME_INTERVAL_CYC  = 1_000_000  // 20 ms between frames (~50 Hz)
)(
    input  wire        clk50,        // 50 MHz master clock
    input  wire        rst_n,        // active-low synchronous reset (tie high for free-run)
    input  wire        uart_rx,      // UART RX from PC (unused)
    output reg         uart_tx,      // UART TX to PC
    output reg  [3:0]  led           // LED[0] toggles each transmitted frame
);

    localparam integer BYTES_PER_FRAME = 2 + 2 + (CHANNELS * 2) + 2; // header + counter + data + CR/LF

    // ROM buffer to hold the current frame (updated before each transmission).
    reg [7:0] frame [0:BYTES_PER_FRAME-1];

    reg [15:0] frame_id      = 16'd0;   // monotonically increasing frame counter
    reg [15:0] sample_base   = 16'd0;   // base value used to synthesise channel samples

    // UART control signals
    reg [9:0]  tx_shift      = 10'h3FF; // shift register including start/data/stop bits
    reg [3:0]  bit_idx       = 4'd0;    // 0..9 bit index within a UART symbol
    reg [7:0]  byte_idx      = 8'd0;    // index into the frame array
    reg        transmitting  = 1'b0;    // indicates active UART transmission
    reg        load_next     = 1'b0;    // internal flag to load next byte
    reg        baud_tick     = 1'b0;    // pulses once per UART bit interval

    reg [15:0] baud_cnt      = 16'd0;   // counts clock cycles for baud timing
    reg [31:0] frame_cnt     = 32'd0;   // counts clock cycles between frames

    integer ch;

    // LED heartbeat toggles on each completed frame.
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n)
            led <= 4'b0000;
        else if (!transmitting && load_next) // about to load first byte of next frame
            led[0] <= ~led[0];
    end

    // UART baud generator (non-integer divider, acceptable error at 115200).
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= 16'd0;
            baud_tick <= 1'b0;
        end else if (baud_cnt == BAUD_DIV - 1) begin
            baud_cnt  <= 16'd0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 16'd1;
            baud_tick <= 1'b0;
        end
    end

    // Frame interval timer triggers new transmissions.
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            frame_cnt <= 32'd0;
            load_next <= 1'b0;
        end else if (frame_cnt == FRAME_INTERVAL_CYC - 1) begin
            frame_cnt <= 32'd0;
            load_next <= 1'b1;       // request to load and send a new frame
        end else begin
            frame_cnt <= frame_cnt + 32'd1;
            load_next <= 1'b0;
        end
    end

    // Prepare frame contents whenever load_next is asserted.
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            frame_id    <= 16'd0;
            sample_base <= 16'd0;
        end else if (load_next && !transmitting) begin
            // Header
            frame[0] <= 8'hAA;
            frame[1] <= 8'h55;
            // Frame counter (little-endian)
            frame[2] <= frame_id[7:0];
            frame[3] <= frame_id[15:8];
            // Synthesise sample data: simple ramp based on frame counter and channel index.
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                frame[4 + ch*2]     <= (sample_base + ch) & 8'hFF;         // low byte
                frame[5 + ch*2]     <= ((sample_base + ch) >> 8) & 8'hFF;  // high byte
            end
            // Append newline (CR/LF)
            frame[BYTES_PER_FRAME-2] <= 8'h0D;
            frame[BYTES_PER_FRAME-1] <= 8'h0A;

            // Update counters for next frame
            frame_id    <= frame_id + 16'd1;
            sample_base <= sample_base + CHANNELS;
        end
    end

    // UART transmitter: loads bytes from the frame and shifts them out.
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx      <= 1'b1;
            transmitting <= 1'b0;
            bit_idx      <= 4'd0;
            byte_idx     <= 8'd0;
            tx_shift     <= 10'h3FF;
        end else if (!transmitting) begin
            uart_tx <= 1'b1;                     // idle level when not transmitting
            if (load_next) begin
                transmitting <= 1'b1;
                byte_idx     <= 8'd0;
                bit_idx      <= 4'd0;
                tx_shift     <= {1'b1, frame[0], 1'b0}; // start + data + stop
            end
        end else if (baud_tick) begin
            uart_tx  <= tx_shift[0];             // output current bit
            tx_shift <= {1'b1, tx_shift[9:1]};   // shift right, insert 1s for stop bits

            if (bit_idx == 4'd9) begin           // finished sending start/data/stop bits
                bit_idx <= 4'd0;
                if (byte_idx == BYTES_PER_FRAME - 1) begin
                    transmitting <= 1'b0;        // entire frame transmitted
                end else begin
                    byte_idx <= byte_idx + 8'd1;
                    tx_shift <= {1'b1, frame[byte_idx + 1], 1'b0}; // load next byte
                end
            end else begin
                bit_idx <= bit_idx + 4'd1;
            end
        end
    end

endmodule
