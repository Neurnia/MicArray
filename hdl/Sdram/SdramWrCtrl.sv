// SdramWrCtrl.sv
// Write scheduler between SdramWrFifo and SdramControl.

module SdramWrCtrl #(
    parameter int DATA_WIDTH   = 16,
    parameter int FIFO_DEPTH   = 512,
    parameter int BURST_LENGTH = 8,
    parameter int ADDR_WIDTH   = 24
) (
    // basic & special
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic wrrd_clear_i,
    input  logic active_i,
    input  logic window_done_i,
    output logic is_done_o,

    // upstream
    output logic fifo_ready_o,
    input logic fifo_valid_i,
    input logic [DATA_WIDTH - 1:0] fifo_data_i,
    input logic [$clog2(FIFO_DEPTH) - 1:0] fifo_level_i,

    // downstream cmd
    input logic cmd_ready_i,
    output logic cmd_valid_o,
    output logic [ADDR_WIDTH - 1:0] cmd_addr_o,  // linear 16-bit word address
    output logic [$clog2(BURST_LENGTH + 1) - 1:0] cmd_len_o,  // burst length

    // downstream data
    input logic wr_ready_i,
    output logic wr_valid_o,
    output logic [DATA_WIDTH - 1:0] wr_data_o
);

    localparam int LenWidth = $clog2(BURST_LENGTH + 1);

    logic [LenWidth - 1:0] beat_cnt;
    logic [LenWidth - 1:0] active_len;
    logic [ADDR_WIDTH - 1:0] next_addr;
    logic window_done_reg;
    logic is_last_burst;
    logic issue_last_burst;

    logic cmd_fire;
    logic wr_fire;

    typedef enum logic [1:0] {
        IDLE,
        SENDING,
        DONE
    } state_t;
    state_t state, next_state;

    assign cmd_fire = cmd_valid_o && cmd_ready_i;
    assign wr_fire = wr_valid_o && wr_ready_i;
    assign wr_data_o = fifo_data_i;
    assign fifo_ready_o = wr_fire;
    assign issue_last_burst = window_done_reg && (fifo_level_i <= BURST_LENGTH);
    assign is_done_o = (state == DONE);

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state <= IDLE;
        end else if (wrrd_clear_i) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cmd_fire) begin
                    next_state = SENDING;
                end
            end
            SENDING: begin
                if (wr_fire && (beat_cnt + 1'b1 == active_len)) begin
                    if (is_last_burst) next_state = DONE;
                    else next_state = IDLE;
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
            cmd_addr_o <= '0;
            cmd_len_o <= '0;
            wr_valid_o <= 1'b0;
            beat_cnt <= '0;
            active_len <= '0;
            next_addr <= '0;
            window_done_reg <= 1'b0;
            is_last_burst <= 1'b0;
        end else if (wrrd_clear_i) begin
            cmd_valid_o <= 1'b0;
            cmd_addr_o <= '0;
            cmd_len_o <= '0;
            wr_valid_o <= 1'b0;
            beat_cnt <= '0;
            active_len <= '0;
            next_addr <= '0;
            window_done_reg <= 1'b0;
            is_last_burst <= 1'b0;
        end else begin
            if (window_done_i) begin
                window_done_reg <= 1'b1;
            end

            wr_valid_o <= 1'b0;

            case (state)
                IDLE: begin
                    if (!active_i) begin
                        cmd_valid_o <= 1'b0;
                    end else if (!cmd_valid_o) begin
                        if (fifo_level_i >= BURST_LENGTH) begin
                            cmd_valid_o <= 1'b1;
                            cmd_addr_o  <= next_addr;
                            cmd_len_o   <= LenWidth'(BURST_LENGTH);
                        end else if ((fifo_level_i > 0) && window_done_reg) begin
                            cmd_valid_o <= 1'b1;
                            cmd_addr_o  <= next_addr;
                            cmd_len_o   <= LenWidth'(fifo_level_i);
                        end
                    end

                    if (cmd_fire) begin
                        active_len <= cmd_len_o;
                        is_last_burst <= issue_last_burst;
                        next_addr <= next_addr + cmd_len_o;
                        if (issue_last_burst) begin
                            window_done_reg <= 1'b0;
                        end
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
                DONE: begin
                    cmd_valid_o <= 1'b0;
                    wr_valid_o  <= 1'b0;
                end
                default: begin
                    cmd_valid_o <= 1'b0;
                    wr_valid_o  <= 1'b0;
                end
            endcase
        end
    end

endmodule
