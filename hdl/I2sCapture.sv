// I2sCaptureTest.v
// Capture the data sent from INMP441 microphone.
// The module is implemented with an explicit FSM.

module I2sCapture (
    // input
    input logic clk_i,    // system clock
    input logic rst_n_i,  // reset input
    input logic bclk_i,   // clock for I2S
    input logic ws_i,     // ws flip
    input logic sd_i,     // data input

    // output
    output logic [15:0] sample_data_o,
    output logic        sample_valid_o

);

    /*
    FSM states in one period:
    (Whenever we press reset button, we enter the IDLE state)
    (States always change on the rising edge of clk)
    - IDLE state
        - if ws flips and ws is equal to the channel,
        enter the next state.
    - WAIT_MSB state
        - when bclk rises (the first time), enter the next state.
    - READING state
        - read first 16 bits (MSB first).
        - once the 16th bit is read, return to IDLE state.

    for sample_valid_o:
    - set to 0 except the moment when the 16th bit is obtained.
    The pull up lasts only one clk period.
    for sample_data_o:
    - set to 0 when the reset button is pressed.
    - change with sample_valid_o and stay unchanged rest of the time.
    */

    // only use the left channel
    parameter integer CHANNEL_SELECT = 0;

    // delay values
    logic ws_d, bclk_d;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ws_d   <= 1'b0;
            bclk_d <= 1'b0;
        end else begin
            ws_d   <= ws_i;
            bclk_d <= bclk_i;
        end
    end

    // states
    typedef enum logic [1:0] {
        IDLE,
        WAIT_MSB,
        READING
    } state_t;
    state_t state, next_state;

    wire         ws_edge = ws_d ^ ws_i;  // edge detect
    wire         bclk_edge = bclk_d ^ bclk_i;
    logic [ 3:0] bit_idx = 4'd0;  // index of the next bit to acquire
    logic [15:0] shift_reg = 16'd0;

    // states switch & reset
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
            if (ws_edge && ws_i == CHANNEL_SELECT) begin
                next_state = WAIT_MSB;
            end
            WAIT_MSB:
            if (bclk_edge && bclk_i) begin
                next_state = READING;
            end
            READING:
            // make sure the state changes with bclk
            if (bclk_edge && bclk_i) begin
                if (bit_idx == 4'd15) begin
                    next_state = IDLE;
                end
            end
            // fall back to IDLE when there is an undefined state
            default: next_state = IDLE;
        endcase
    end

    // what we should do in each state
    // local values should be handled here
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            bit_idx <= 4'd0;
            shift_reg <= 16'd0;
            sample_valid_o <= 1'd0;
            sample_data_o <= 16'd0;
        end else begin
            case (state)
                IDLE: sample_valid_o <= 1'd0;
                WAIT_MSB: bit_idx <= 4'd0;  // prepare for the index
                READING: begin
                    sample_valid_o <= 1'd0;
                    if (bclk_edge && bclk_i) begin
                        shift_reg <= {shift_reg[14:0], sd_i};
                        if (bit_idx == 4'd15) begin
                            // non-blocking assignment
                            // all the assignment happens at the same time
                            // so sample_data_o would take the shift_reg in the last round
                            sample_data_o  <= {shift_reg[14:0], sd_i};
                            sample_valid_o <= 1'd1;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end
                // reset the only interface that may affect other modules
                default: sample_valid_o <= 1'd0;
            endcase
        end
    end

endmodule
