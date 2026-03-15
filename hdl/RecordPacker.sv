// RecordPacker.sv
// Serialize record data into 16-bit words

module RecordPacker #(
    parameter int MIC_CNT = 8,
    parameter int SAMPLE_WIDTH = 16,
    parameter int WORD_WIDTH = 16
) (
    // input
    input logic clk_i,
    input logic rst_n_i,
    // pulse: upstream has finished issuing all frames in the current window
    input logic record_done_i,
    // upstream parallel data
    input logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] record_data_i,

    // output
    // pulse: all buffered words of the current window have been packed out
    output logic pack_done_o,
    output logic [WORD_WIDTH - 1:0] pack_data_o,  // based on word width

    // upstream handshake & error message (frame-level valid-ready)
    output logic record_ready_o,
    input  logic record_valid_i,
    // when error word is non-zero, following data words are invalid and must be ignored
    input  logic record_error_i,

    // downstream handshake (word-level valid-ready)
    input  logic pack_ready_i,
    output logic pack_valid_o
);

    /*
    States:
    - IDLE: Default state. Wait for frames.
        - Enter PACK_ERROR when there is a successful upstream handshake.
        - Latch data and error from record (when handshake).
    - PACK_ERROR: Send one word of error information.
        - Enter PACK_DATA after one successful downstream handshake.
    - PACK_DATA: Send MIC_CNT words of data.
        - Enter IDLE after all words are sent (with successful downstream handshake).

    Important assumption:
    One packed frame (MIC_CNT + 1 words) can be accepted by downstream within one frame period under normal operation.
    */

    localparam int MicCntBit = $clog2(MIC_CNT);
    logic [MicCntBit - 1:0] ch_idx;  // channel index of the next word
    logic record_done_reg;  // done pulse latch
    logic record_error_reg;
    logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] record_data_reg;

    // upstream handshake
    logic record_fire;
    assign record_fire = record_valid_i && record_ready_o;
    // downstream handshake
    logic pack_fire;
    assign pack_fire = pack_valid_o && pack_ready_i;

    // states
    typedef enum logic [1:0] {
        IDLE,
        PACK_ERROR,
        PACK_DATA
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
            IDLE: if (record_fire) next_state = PACK_ERROR;
            PACK_ERROR: if (pack_fire) next_state = PACK_DATA;
            PACK_DATA: if (pack_fire && ch_idx == MIC_CNT - 1) next_state = IDLE;
            // fall back
            default: next_state = IDLE;
        endcase
    end

    // record done latch & pack done
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pack_done_o <= 1'b0;
            record_done_reg <= 1'b0;
        end else begin
            pack_done_o <= 1'b0;  // keep low
            if (record_done_i) record_done_reg <= 1'b1;
            if (record_done_reg && pack_fire && ch_idx == MIC_CNT - 1) begin
                pack_done_o <= 1'b1;  // pulse
                record_done_reg <= 1'b0;  // reset
            end
        end
    end

    // what we should do in each state
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pack_data_o <= '0;
            pack_valid_o <= 1'b0;
            record_ready_o <= 1'b0;
        end else begin
            record_ready_o <= 1'b0;
            pack_valid_o   <= 1'b0;
            case (state)
                IDLE: begin
                    // prepared for the handshake
                    record_ready_o <= 1'b1;
                    if (record_fire) begin
                        record_error_reg <= record_error_i;
                        record_data_reg  <= record_data_i;
                    end
                end
                PACK_ERROR: begin
                    pack_data_o <= {record_error_reg, {(WORD_WIDTH - 1) {1'b0}}};
                    pack_valid_o <= 1'b1;
                    ch_idx <= '0;  // reset channel
                    if (pack_fire) begin
                        pack_valid_o <= 1'b0;
                    end
                end
                PACK_DATA: begin
                    // take the upper bits of each channel
                    pack_data_o  <= record_data_reg[ch_idx][SAMPLE_WIDTH-1-:WORD_WIDTH];
                    pack_valid_o <= 1'b1;
                    if (pack_fire) begin
                        if (ch_idx < MIC_CNT - 1) ch_idx <= ch_idx + 1;
                        if (ch_idx == MIC_CNT - 1) pack_valid_o <= 1'b0;
                    end
                end
                default: begin
                    pack_valid_o   <= 1'b0;
                    record_ready_o <= 1'b0;
                end
            endcase
        end
    end



endmodule
