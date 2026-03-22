// UartSender.sv
// Responsible for UART transmission.

module UartSender #(
    parameter int          CLK_HZ        = 50_000_000,
    parameter int          BAUD_HZ       = 921_600,
    parameter int          DATA_WIDTH    = 16,
    parameter int          MIC_CNT       = 2,
    parameter int          WINDOW_LENGTH = 1024,
    parameter logic [15:0] HEADER_WORD   = 16'hA55A
) (
    // basic & special
    input  logic clk_i,
    input  logic rst_n_i,
    output logic uart_busy_o,        // level
    output logic uart_window_done_o, // pulse

    // upstream interface
    input  logic                  payload_valid_i,
    output logic                  payload_ready_o,
    input  logic [DATA_WIDTH-1:0] payload_data_i,

    // uart pins
    output logic uart_tx_o
);

    /*
    States:
    - IDLE:
        - Wait until upstream payload becomes valid.
        - Start the window transmission by sending HEADER_WORD first.
    - SEND_PREFIX:
        - Send two words before payload:
            1. HEADER_WORD
            2. MIC_CNT + 1
    - SEND_PAYLOAD:
        - Send fixed-length payload words from upstream.
        - Enter DONE after the last payload word is fully sent.
    - DONE:
        - Pulse uart_window_done_o for one clk.
        - Return to IDLE.
    */

    localparam int WordBytes = DATA_WIDTH / 8;
    localparam int FrameWords = MIC_CNT + 1;
    localparam int PayloadWords = WINDOW_LENGTH * FrameWords;
    localparam int PayloadCountWidth = $clog2(PayloadWords + 1);
    localparam int ByteIndexWidth = (WordBytes > 1) ? $clog2(WordBytes) : 1;
    localparam logic [DATA_WIDTH - 1:0] HeaderValue = DATA_WIDTH'(HEADER_WORD);
    localparam logic [DATA_WIDTH - 1:0] FrameWordsValue = DATA_WIDTH'(FrameWords);

    logic [                   63:0] phase_acc;
    logic                           baud_tick;

    logic [                    9:0] shift_reg;
    logic [                    3:0] bit_idx;
    logic                           uart_byte_busy;

    logic [       DATA_WIDTH - 1:0] current_word;
    logic [   ByteIndexWidth - 1:0] byte_idx;
    logic                           prefix_word_idx;
    logic [PayloadCountWidth - 1:0] payload_word_count;

    logic                           start_window;
    logic                           payload_fire;
    logic                           byte_fire;
    logic                           byte_done;
    logic                           word_done;
    logic                           prefix_done;
    logic                           window_done;

    // states
    typedef enum logic [1:0] {
        IDLE,
        SEND_PREFIX,
        SEND_PAYLOAD,
        DONE
    } state_t;
    state_t state, next_state;

    // helper functions
    function automatic logic [7:0] SelectWordByte(input logic [DATA_WIDTH - 1:0] word,
                                                  input int idx);
        SelectWordByte = word[DATA_WIDTH-1-(idx*8)-:8];
    endfunction

    function automatic logic [9:0] MakeUartFrame(input logic [7:0] byte_data);
        MakeUartFrame = {1'b1, byte_data, 1'b0};
    endfunction

    assign payload_ready_o = (state == SEND_PAYLOAD) && !uart_byte_busy;
    assign uart_busy_o = (state == SEND_PREFIX) || (state == SEND_PAYLOAD);

    assign start_window = (state == IDLE) && payload_valid_i;
    assign payload_fire = payload_valid_i && payload_ready_o;
    assign byte_fire = uart_byte_busy && baud_tick;
    assign byte_done = byte_fire && (bit_idx == 4'd9);
    assign word_done = byte_done && (byte_idx == WordBytes - 1);
    assign prefix_done = (state == SEND_PREFIX) && word_done && prefix_word_idx;
    assign window_done = (state == SEND_PAYLOAD) &&
                         word_done &&
                         (payload_word_count == PayloadWords - 1);

    // baud generator
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            phase_acc <= 64'd0;
            baud_tick <= 1'b0;
        end else if (!uart_byte_busy) begin
            phase_acc <= 64'd0;
            baud_tick <= 1'b0;
        end else if (phase_acc + BAUD_HZ >= CLK_HZ) begin
            phase_acc <= phase_acc + BAUD_HZ - CLK_HZ;
            baud_tick <= 1'b1;
        end else begin
            phase_acc <= phase_acc + BAUD_HZ;
            baud_tick <= 1'b0;
        end
    end

    // state switch
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // decide the next state
    always_comb begin
        next_state = state;
        case (state)
            IDLE:
            if (start_window) begin
                next_state = SEND_PREFIX;
            end
            SEND_PREFIX:
            if (prefix_done) begin
                next_state = SEND_PAYLOAD;
            end
            SEND_PAYLOAD:
            if (window_done) begin
                next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // what to do in each state
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            uart_tx_o <= 1'b1;
            uart_window_done_o <= 1'b0;
            shift_reg <= 10'h3FF;
            bit_idx <= '0;
            uart_byte_busy <= 1'b0;
            current_word <= '0;
            byte_idx <= '0;
            prefix_word_idx <= 1'b0;
            payload_word_count <= '0;
        end else begin
            uart_window_done_o <= 1'b0;
            if (!uart_byte_busy) begin
                uart_tx_o <= 1'b1;  // active low
            end

            case (state)
                IDLE: begin
                    prefix_word_idx <= 1'b0;
                    payload_word_count <= '0;
                    uart_byte_busy <= 1'b0;

                    if (start_window) begin
                        current_word <= HeaderValue;
                        byte_idx <= '0;
                        bit_idx <= '0;
                        shift_reg <= MakeUartFrame(SelectWordByte(HeaderValue, 0));
                        uart_byte_busy <= 1'b1;
                    end
                end

                SEND_PREFIX: begin
                    if (byte_fire) begin
                        uart_tx_o <= shift_reg[0];
                        shift_reg <= {1'b1, shift_reg[9:1]};

                        if (bit_idx == 4'd9) begin
                            bit_idx <= '0;
                            if (byte_idx < WordBytes - 1) begin
                                byte_idx <= byte_idx + 1'b1;
                                shift_reg <= MakeUartFrame(
                                    SelectWordByte(current_word, byte_idx + 1)
                                );
                            end else if (!prefix_word_idx) begin
                                prefix_word_idx <= 1'b1;
                                current_word <= FrameWordsValue;
                                byte_idx <= '0;
                                shift_reg <= MakeUartFrame(SelectWordByte(FrameWordsValue, 0));
                            end else begin
                                uart_byte_busy <= 1'b0;
                            end
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end

                SEND_PAYLOAD: begin
                    if (byte_fire) begin
                        uart_tx_o <= shift_reg[0];
                        shift_reg <= {1'b1, shift_reg[9:1]};

                        if (bit_idx == 4'd9) begin
                            bit_idx <= '0;
                            if (byte_idx < WordBytes - 1) begin
                                byte_idx <= byte_idx + 1'b1;
                                shift_reg <= MakeUartFrame(
                                    SelectWordByte(current_word, byte_idx + 1)
                                );
                            end else begin
                                payload_word_count <= payload_word_count + 1'b1;
                                uart_byte_busy <= 1'b0;
                            end
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else if (payload_fire) begin
                        current_word <= payload_data_i;
                        byte_idx <= '0;
                        bit_idx <= '0;
                        shift_reg <= MakeUartFrame(SelectWordByte(payload_data_i, 0));
                        uart_byte_busy <= 1'b1;
                    end
                end

                DONE: begin
                    uart_window_done_o <= 1'b1;
                    uart_byte_busy <= 1'b0;
                end

                default: begin
                    uart_byte_busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
