// PcmUartFramedTx.v
// Integrated UART transmitter that frames a 24-bit sample into:
//   0xA5, sample[23:16], sample[15:8], sample[7:0], 0x0A
// No external UART handshake; the module latches a sample when idle and
// streams all 5 bytes back-to-back using its own baud generator.

module PcmUartFramedTx #(
    parameter integer CLK_HZ  = 50_000_000,
    parameter integer BAUD_HZ = 921_600
) (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire [23:0] sample_data_i,
    input  wire        sample_valid_i,  // pulse when new sample available
    output reg         sample_ready_o,  // high when idle/ready to accept
    output reg         uart_tx_o,
    output reg         frame_sent_o     // pulses high for one clk when full frame sent
);

    // Fractional baud tick using phase accumulator:
    //   phase_acc += BAUD_HZ; when phase_acc >= CLK_HZ -> tick and subtract CLK_HZ.
    // Average tick rate equals BAUD_HZ with <=1 clk cycle jitter.
    reg [63:0] phase_acc;
    reg        baud_tick;

    reg [ 9:0] shift_reg;
    reg [ 3:0] bit_idx;
    reg [ 2:0] byte_idx;
    reg        busy;
    reg [23:0] sample_buf;

    // Baud generator runs only while busy
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            phase_acc <= 64'd0;
            baud_tick <= 1'b0;
        end else if (!busy) begin
            phase_acc <= 64'd0;
            baud_tick <= 1'b0;
        end else begin
            // accumulator
            if (phase_acc + BAUD_HZ >= CLK_HZ) begin
                baud_tick <= 1'b1;
                phase_acc <= phase_acc + BAUD_HZ - CLK_HZ;
            end else begin
                baud_tick <= 1'b0;
                phase_acc <= phase_acc + BAUD_HZ;
            end
        end
    end

    // Select byte based on byte_idx
    function [7:0] select_byte;
        input [2:0] idx;
        input [23:0] s;
        begin
            case (idx)
                3'd0: select_byte = 8'hA5;
                3'd1: select_byte = s[23:16];
                3'd2: select_byte = s[15:8];
                3'd3: select_byte = s[7:0];
                default: select_byte = 8'h0A;
            endcase
        end
    endfunction

    // Control + TX shift
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy           <= 1'b0;
            shift_reg      <= 10'h3FF;
            bit_idx        <= 4'd0;
            byte_idx       <= 3'd0;
            uart_tx_o      <= 1'b1;
            sample_buf     <= 24'd0;
            sample_ready_o <= 1'b1;
            frame_sent_o   <= 1'b0;
        end else begin
            frame_sent_o   <= 1'b0;
            sample_ready_o <= ~busy;

            if (!busy) begin
                uart_tx_o <= 1'b1;
                if (sample_valid_i) begin
                    // Latch sample and start first byte
                    sample_buf <= sample_data_i;
                    byte_idx   <= 3'd0;
                    bit_idx    <= 4'd0;
                    shift_reg  <= {1'b1, select_byte(3'd0, sample_data_i), 1'b0};
                    busy       <= 1'b1;
                end
            end else if (baud_tick) begin
                uart_tx_o <= shift_reg[0];
                shift_reg <= {1'b1, shift_reg[9:1]};  // shift right, fill stop bits

                if (bit_idx == 4'd9) begin
                    bit_idx <= 4'd0;
                    if (byte_idx == 3'd4) begin
                        busy         <= 1'b0;
                        frame_sent_o <= 1'b1;
                    end else begin
                        byte_idx  <= byte_idx + 1'b1;
                        shift_reg <= {1'b1, select_byte(byte_idx + 1'b1, sample_buf), 1'b0};
                    end
                end else begin
                    bit_idx <= bit_idx + 1'b1;
                end
            end
        end
    end

endmodule
