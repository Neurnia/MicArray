// SdramWrCtrl.sv
// Write scheduler between SdramWrFifo and SdramControl.

module SdramWrCtrl #(
    parameter int DATA_WIDTH   = 16,
    parameter int FIFO_DEPTH   = 512,
    parameter int BURST_LENGTH = 8,
    parameter int ADDR_WIDTH   = 24
) (
    // basic & special
    input logic clk_i,
    input logic rst_n_i,
    input logic window_done_i,

    // upstream
    output logic fifo_ready_o,
    input logic fifo_valid_i,
    input logic [DATA_WIDTH - 1:0] fifo_data_i,
    input logic [$clog2(FIFO_DEPTH) - 1:0] fifo_level_i,

    // downstream cmd
    input logic cmd_ready_i,
    output logic cmd_valid_o,
    output logic cmd_we_n_o,  // always write in this module
    output logic [ADDR_WIDTH - 1:0] cmd_addr_o,  // linear 16-bit word address
    output logic [$clog2(BURST_LENGTH + 1) - 1:0] cmd_len_o,  // burst length

    // downstream data
    input logic wr_ready_i,
    output logic wr_valid_o,
    output logic [DATA_WIDTH - 1:0] wr_data_o
);

    /*
    One burst in one state cycle.
    States:
    - IDLE:
        - Observe fifo level and window done.
        - Prepare a cmd and pull up cmd valid at the right time.
        - When there is a successful handshake of cmd, enter SENDING.
    - SENDING:
        - Control upstream handshake and downstream data handshake.
        - Return to IDLE when sent data reaches burst length.
    */

    assign cmd_we_n_o = 1'b0;  // always write enable (active low)
    logic [$clog2(BURST_LENGTH + 1) - 1:0] beat_cnt;
    logic [$clog2(BURST_LENGTH + 1) - 1:0] active_len;
    logic window_done_reg;  // latch window done
    logic [ADDR_WIDTH - 1:0] next_addr;

    // handshakes
    logic cmd_fire;
    logic wr_fire;
    assign cmd_fire = cmd_valid_o && cmd_ready_i;
    assign wr_fire = wr_valid_o && wr_ready_i;

    assign wr_data_o = fifo_data_i;  // direct data transfer
    assign fifo_ready_o = wr_fire;  // synced handshake

    // states
    typedef enum logic {
        IDLE,
        SENDING
    } state_t;
    state_t state, next_state;

    // state switch
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) state <= IDLE;
        else state <= next_state;
    end

    // next state decision
    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (cmd_fire) next_state = SENDING;
            SENDING: if (beat_cnt + 1 == active_len && wr_fire) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // in each state
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cmd_valid_o <= 1'b0;
            cmd_len_o <= 1'b0;
            wr_valid_o <= 1'b0;
            window_done_reg <= 1'b0;
            cmd_addr_o <= '0;
            beat_cnt <= '0;
            active_len <= '0;
            next_addr <= '0;
        end else begin
            // window done latch
            if (window_done_i) window_done_reg <= 1'b1;
            if (fifo_level_i == 1 && wr_fire) window_done_reg <= 1'b0;
            // default pull down
            wr_valid_o <= 1'b0;
            case (state)
                IDLE: begin
                    if (cmd_valid_o == 1'b0) begin
                        if (fifo_level_i >= BURST_LENGTH) begin
                            cmd_valid_o <= 1'b1;
                            cmd_addr_o  <= next_addr;
                            cmd_len_o   <= BURST_LENGTH;
                        end else if (fifo_level_i > 0 && window_done_reg) begin
                            cmd_valid_o <= 1'b1;
                            cmd_addr_o  <= next_addr;
                            cmd_len_o   <= fifo_level_i;
                        end
                    end
                    // update address
                    if (cmd_fire) begin
                        active_len <= cmd_len_o;
                        next_addr <= next_addr + cmd_len_o;
                        cmd_valid_o <= 1'b0;
                        beat_cnt <= '0;
                    end
                end
                SENDING: begin
                    wr_valid_o <= fifo_valid_i;
                    if (wr_fire) begin
                        beat_cnt <= beat_cnt + 1;
                    end
                end
                default: begin
                    cmd_valid_o <= 1'b0;
                    wr_valid_o  <= 1'b0;
                end
            endcase
        end
    end

endmodule
