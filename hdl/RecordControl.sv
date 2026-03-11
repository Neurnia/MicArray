// RecordControl.sv
// Manage the whole record process (frames and information).
// The module is implemented with Explicit FSM.

module RecordControl #(
    parameter int WINDOW_LENGTH = 1024,  // frame number in one window
    parameter int MIC_CNT = 8,
    parameter int SAMPLE_WIDTH = 16
) (
    // input
    input logic clk_i,
    input logic rst_n_i,
    input logic frame_change_i,
    input logic record_start_i,
    input logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] frame_data_i,

    // output (data & information)
    output logic record_done_o,
    output logic record_error_o,  // hold frame_error_i until write_ready_i
    output logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] record_data_o,

    // upstream handshake & error information
    output logic frame_ready_o,
    input  logic frame_valid_i,
    input  logic frame_error_i,

    // downstream handshake
    input  logic write_ready_i,
    output logic record_valid_o

);

    /*
    States:
    - IDLE:
        - Enter the state after reset.
        - Enter COLLECTING state when it is the first frame_change after record_start.
    - COLLECTING:
        - Enter COMMITTING state after each frame_change.
        (This also solves the problem when there is actually no data after the first frame_change.)
    - COMMITTING:
        - Enter IDLE state when it is the first downstream handshake after frame count reaches window width.
        - (or) If it has not reach the windows length, enter COLLECTING state when downstream handshake is done.

    Assumption:
    - Downstream handshake will always complete within one frame.
    */

    localparam int WindowLengthBit = $clog2(WINDOW_LENGTH) + 1;
    logic [WindowLengthBit - 1:0] window_cnt;  // count current committing frame

    logic recording;  // recording flag

    // states
    typedef enum logic [1:0] {
        IDLE,
        COLLECTING,
        COMMITTING
    } state_t;
    state_t state, next_state;

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
            if (recording && frame_change_i) begin
                next_state = COLLECTING;
            end
            COLLECTING:
            if (frame_change_i) begin
                next_state = COMMITTING;
            end
            COMMITTING:
            if (write_ready_i && window_cnt < WINDOW_LENGTH) begin
                next_state = COLLECTING;
            end else if (window_cnt == WINDOW_LENGTH && write_ready_i) begin
                next_state = IDLE;
            end
            // fall back
            default: next_state = IDLE;
        endcase
    end

    // window counting
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            window_cnt <= '0;
        end else begin
            if (!recording) begin
                window_cnt <= '0;
            end else begin
                // count frames
                if (state == COLLECTING && frame_change_i) begin
                    window_cnt <= window_cnt + 1;
                end
            end
        end
    end

    // recording flag & record_done
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            recording <= 1'b0;
            record_done_o <= 1'b0;
        end else begin
            record_done_o <= 1'b0;
            if (state == IDLE && record_start_i) begin
                recording <= 1'b1;  // set flag
            end
            if (window_cnt == WINDOW_LENGTH && write_ready_i) begin
                recording <= 1'b0;
                record_done_o <= 1'b1;
            end
        end
    end

    // what we should do in each state
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            record_data_o  <= '0;
            record_error_o <= 1'b0;
            record_valid_o <= 1'b0;
            frame_ready_o  <= 1'b0;
        end else begin
            // keep valid low by default
            record_valid_o <= 1'b0;
            frame_ready_o  <= 1'b0;
            case (state)
                IDLE: record_error_o <= 1'b0;  // reset error
                COLLECTING: begin
                    record_error_o <= 1'b0;  // reset error
                    if (frame_valid_i) begin
                        record_data_o <= frame_data_i;
                        frame_ready_o <= 1'b1;  // upstream handshake
                    end
                end
                COMMITTING: begin
                    record_valid_o <= 1'b1;
                    if (frame_error_i) begin
                        record_error_o <= 1'b1;
                    end
                end
                default: begin
                    record_valid_o <= 1'b0;
                    frame_ready_o  <= 1'b0;
                    record_error_o <= 1'b0;
                end
            endcase
        end
    end

endmodule
