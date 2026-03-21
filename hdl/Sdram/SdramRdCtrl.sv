// SdramRdCtrl.sv
// Read control logic for SDRAM.

module SdramRdCtrl #(
    parameter int MIC_CNT = 2,
    parameter int DATA_WIDTH = 16,
    parameter int FIFO_DEPTH = 512,
    parameter int BURST_LENGTH = 8,
    parameter int ADDR_WIDTH = 24,
    parameter int WINDOW_LENGTH = 1024
) (
    // basic
    input logic clk_i,
    input logic rst_n_i,

    // upstream cmd
    input logic cmd_ready_i,
    output logic cmd_valid_o,
    output logic cmd_we_n_o,  // always read in this module
    output logic [ADDR_WIDTH - 1:0] cmd_addr_o,  // linear
    output logic [$clog2(BURST_LENGTH + 1) - 1:0] cmd_len_o,  // burst length

    // upstream data
    input logic rd_beat_i,
    input logic [DATA_WIDTH - 1:0] rd_data_i,

    // downstream
    input logic fifo_ready_i,
    output logic fifo_valid_o,
    output logic [DATA_WIDTH - 1:0] fifo_data_o,
    input logic [$clog2(FIFO_DEPTH) - 1:0] fifo_level_i
);

    localparam int LenWidth = $clog2(BURST_LENGTH + 1);
    localparam int WindowWords = WINDOW_LENGTH * (MIC_CNT + 1);  // one error word
    localparam int WindowWordsWidth = $clog2(WindowWords + 1);

    logic [WindowWordsWidth - 1:0] remaining_words;
    logic [LenWidth - 1:0] active_len;
    logic [LenWidth - 1:0] burst_words;  // actual burst length
    logic [LenWidth - 1:0] beat_cnt;
    logic [ADDR_WIDTH - 1:0] next_addr;

    logic cmd_fire;  // cmd handshake
    logic fifo_fire;  // fifo handshake
    logic fifo_has_burst_space;

    typedef enum logic [1:0] {
        IDLE,
        WAIT_CMD,   // wait for cmd handshake
        RECEIVING,
        DONE
    } state_t;
    state_t state, next_state;

    assign cmd_we_n_o = 1'b1;  // always read

    assign cmd_fire = cmd_valid_o && cmd_ready_i;
    assign fifo_fire = fifo_valid_o && fifo_ready_i;
    assign fifo_has_burst_space = (fifo_level_i <= FIFO_DEPTH - BURST_LENGTH);
    assign burst_words = (remaining_words >= BURST_LENGTH) ? LenWidth'(BURST_LENGTH) : LenWidth'(remaining_words);

    assign fifo_valid_o = rd_beat_i;
    assign fifo_data_o = rd_data_i;

    // state transition
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (remaining_words == '0) begin
                    next_state = DONE;
                end else if (fifo_has_burst_space) begin
                    next_state = WAIT_CMD;
                end
            end
            WAIT_CMD: begin
                if (cmd_fire) begin
                    next_state = RECEIVING;
                end
            end
            RECEIVING: begin
                if (fifo_fire && (beat_cnt + 1 == active_len)) begin
                    if (remaining_words == active_len) begin
                        next_state = DONE;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end
            DONE: begin
                next_state = DONE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cmd_valid_o <= 1'b0;
            cmd_addr_o  <= '0;
            cmd_len_o   <= '0;
            next_addr   <= '0;
            active_len  <= '0;
            beat_cnt    <= '0;
            remaining_words <= WindowWordsWidth'(WindowWords);
        end else begin
            case (state)
                IDLE: begin
                    cmd_valid_o <= 1'b0;
                    beat_cnt    <= '0;

                    if ((remaining_words != '0) && fifo_has_burst_space) begin
                        cmd_valid_o <= 1'b1;
                        cmd_addr_o  <= next_addr;
                        cmd_len_o   <= burst_words;
                    end
                end
                WAIT_CMD: begin
                    if (cmd_fire) begin
                        cmd_valid_o <= 1'b0;
                        active_len  <= cmd_len_o;
                        beat_cnt    <= '0;
                    end
                end
                RECEIVING: begin
                    if (fifo_fire) begin
                        if (beat_cnt + 1 == active_len) begin
                            next_addr       <= next_addr + active_len;
                            remaining_words <= remaining_words - active_len;
                            beat_cnt        <= '0;
                        end else begin
                            beat_cnt <= beat_cnt + 1'b1;
                        end
                    end
                end
                DONE: begin
                    cmd_valid_o <= 1'b0;
                    beat_cnt    <= '0;
                end
                default: begin
                    cmd_valid_o <= 1'b0;
                end
            endcase
        end
    end

endmodule
