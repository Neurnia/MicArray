// uart_heartbeat.v
// Simple UART heartbeat generator for verifying the board's USB-UART bridge.
// Periodically transmits an ASCII message at 115200 baud using the 50 MHz system clock.

module UartHeartbeat (
    input  wire        clk50,      // 50 MHz oscillator on the FPGA board
    input  wire        rst_n,      // active-low synchronous reset (tie high for free-run)
    input  wire        uart_rx,    // UART RX from PC (unused, kept for pin compatibility)
    output reg         uart_tx,    // UART TX toward the PC
    output reg  [3:0]  led         // LED[0] toggles every transmitted message
);

    // UART configuration: 115200 baud with 50 MHz clock -> divider ≈ 434 (0.006% error).
    localparam integer BAUD_DIV      = 434;
    // Send the heartbeat once every second (50 MHz clock cycles).
    localparam integer HEARTBEAT_DIV = 50_000_000;
    localparam integer MSG_LEN       = 11;             // "FPGA HELLO\r\n"

    // ROM storing the message bytes.
    reg [7:0] msg_rom [0:MSG_LEN-1];
    initial begin
        msg_rom[0]  = "F";
        msg_rom[1]  = "P";
        msg_rom[2]  = "G";
        msg_rom[3]  = "A";
        msg_rom[4]  = " ";
        msg_rom[5]  = "H";
        msg_rom[6]  = "E";
        msg_rom[7]  = "L";
        msg_rom[8]  = "L";
        msg_rom[9]  = "O";
        msg_rom[10] = "\n";        // newline terminator (LF)
    end

    reg [15:0] baud_cnt   = 16'd0;  // baud-rate counter
    reg [31:0] beat_cnt   = 32'd0;  // inter-message interval counter
    reg        baud_tick  = 1'b0;   // asserted for one clk when baud counter expires
    reg        trigger_tx = 1'b0;   // asserted when it's time to start a new message

    reg [9:0]  tx_shift   = 10'b11_1111_1111; // UART shift register (start/data/stop bits)
    reg [3:0]  bit_idx    = 4'd0;             // bit counter within a character (0..9)
    reg [3:0]  msg_idx    = 4'd0;             // index of next character in the ROM
    reg        transmitting = 1'b0;           // indicates active UART transmission

    // LED heartbeat: LED0 toggles each time we finish sending the message.
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n)
            led <= 4'b0000;
        else if (transmitting == 1'b0 && trigger_tx == 1'b1)
            led[0] <= ~led[0];
    end

    // Baud-rate generator (non-integer divider, acceptable ppm error).
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

    // Generate trigger each second to launch a new message.
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            beat_cnt   <= 32'd0;
            trigger_tx <= 1'b0;
        end else if (beat_cnt == HEARTBEAT_DIV - 1) begin
            beat_cnt   <= 32'd0;
            trigger_tx <= 1'b1;
        end else begin
            beat_cnt   <= beat_cnt + 32'd1;
            trigger_tx <= 1'b0;
        end
    end

    // UART transmitter state machine.
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx       <= 1'b1;            // idle level is high
            transmitting  <= 1'b0;
            bit_idx       <= 4'd0;
            msg_idx       <= 4'd0;
            tx_shift      <= 10'h3FF;
        end else if (!transmitting) begin
            uart_tx <= 1'b1;
            if (trigger_tx) begin
                // Load first character: format is {stop bit, data[7:0], start bit}
                tx_shift      <= {1'b1, msg_rom[0], 1'b0};
                bit_idx       <= 4'd0;
                msg_idx       <= 4'd0;
                transmitting  <= 1'b1;
            end
        end else if (baud_tick) begin
            uart_tx  <= tx_shift[0];          // output LSB of shift register
            tx_shift <= {1'b1, tx_shift[9:1]}; // shift right; fill with 1s (stop bits)

            if (bit_idx == 4'd9) begin
                bit_idx <= 4'd0;
                if (msg_idx == MSG_LEN - 1) begin
                    transmitting <= 1'b0;     // complete message transmitted
                end else begin
                    msg_idx  <= msg_idx + 4'd1;
                    tx_shift <= {1'b1, msg_rom[msg_idx + 1], 1'b0}; // load next char
                end
            end else begin
                bit_idx <= bit_idx + 4'd1;
            end
        end
    end

endmodule
