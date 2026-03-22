// Sdram.sv
// SDRAM top-level wrapper.
// This module owns the PLL-generated SDRAM clock domain and sequences one
// window through write then read phases.

module Sdram #(
    parameter int MIC_CNT       = 2,
    parameter int WINDOW_LENGTH = 1024,
    parameter int DATA_WIDTH    = 16,
    parameter int FIFO_DEPTH    = 512,
    parameter int BURST_LENGTH  = 8,
    parameter int ADDR_WIDTH    = 24,
    parameter int RC_WIDTH      = 13,
    parameter int BANK_WIDTH    = 2
) (
    // basic & special
    input logic clk_i,
    input logic rst_n_i,
    input logic pack_done_i,

    // system-side write interface
    output logic wr_ready_o,
    input logic wr_valid_i,
    input logic [DATA_WIDTH - 1:0] wr_data_i,

    // system-side read interface
    input logic rd_ready_i,
    output logic rd_valid_o,
    output logic [DATA_WIDTH - 1:0] rd_data_o,

    // SDRAM pins
    output logic sdram_clk_o,
    output logic sdram_cke_o,
    output logic sdram_cs_n_o,
    output logic sdram_ras_n_o,
    output logic sdram_cas_n_o,
    output logic sdram_we_n_o,
    output logic [BANK_WIDTH - 1:0] sdram_ba_o,
    output logic [RC_WIDTH - 1:0] sdram_addr_o,
    output logic [(DATA_WIDTH / 8) - 1:0] sdram_dqm_o,
    inout wire [DATA_WIDTH - 1:0] sdram_data_io
);

    logic clk_sdram;
    logic pll_locked;
    logic rst_n_sdram;  // reset signal for SDRAM domain

    // write fifo internal signals
    logic window_done;
    logic [$clog2(FIFO_DEPTH) - 1:0] wr_fifo_level;
    logic [DATA_WIDTH - 1:0] wr_fifo_data;
    logic wr_fifo_ready;
    logic wr_fifo_valid;

    // read fifo internal signals
    logic [$clog2(FIFO_DEPTH) - 1:0] rd_fifo_level;
    logic [DATA_WIDTH - 1:0] rd_fifo_data;
    logic rd_fifo_ready;
    logic rd_fifo_valid;

    // SDRAM cmd (assigned by either write or read ctrl, depending on active state)
    logic cmd_ready;
    logic cmd_valid;
    logic cmd_we_n;
    logic [ADDR_WIDTH - 1:0] cmd_addr;
    logic [$clog2(BURST_LENGTH + 1) - 1:0] cmd_len;

    // internal write handshakes & signals
    logic wr_ctrl_cmd_valid;
    logic [ADDR_WIDTH - 1:0] wr_ctrl_cmd_addr;
    logic [$clog2(BURST_LENGTH + 1) - 1:0] wr_ctrl_cmd_len;
    logic wr_ctrl_ready;
    logic wr_ctrl_valid;
    logic [DATA_WIDTH - 1:0] wr_ctrl_data;
    logic wr_active;
    logic wr_is_done;

    // internal read handshakes & signals
    logic rd_ctrl_cmd_valid;
    logic [ADDR_WIDTH - 1:0] rd_ctrl_cmd_addr;
    logic [$clog2(BURST_LENGTH + 1) - 1:0] rd_ctrl_cmd_len;
    logic rd_ctrl_beat;
    logic [DATA_WIDTH - 1:0] rd_ctrl_data;
    logic rd_active;
    logic rd_is_done;

    // clear signal to both write and read ctrl, asserted when transitioning from active to idle state
    logic wrrd_clear;

    // state
    typedef enum logic [1:0] {
        IDLE,
        WRITE_ACTIVE,
        READ_ACTIVE
    } state_t;
    state_t state, next_state, prev_state;

    assign rst_n_sdram = rst_n_i && pll_locked;
    assign wr_active = (state == WRITE_ACTIVE);
    assign rd_active = (state == READ_ACTIVE);
    assign wrrd_clear = (state == IDLE) && (prev_state != IDLE);  // state transition detection

    assign cmd_valid = wr_active ? wr_ctrl_cmd_valid : rd_active ? rd_ctrl_cmd_valid : 1'b0;
    assign cmd_addr = wr_active ? wr_ctrl_cmd_addr : rd_active ? rd_ctrl_cmd_addr : '0;
    assign cmd_len = wr_active ? wr_ctrl_cmd_len : rd_active ? rd_ctrl_cmd_len : '0;
    assign cmd_we_n = rd_active;


    always_ff @(posedge clk_sdram or negedge rst_n_sdram) begin
        if (!rst_n_sdram) begin
            state <= IDLE;
            prev_state <= IDLE;
        end else begin
            prev_state <= state;
            state <= next_state;
        end
    end

    // state transition logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (wr_fifo_level != '0) begin
                    next_state = WRITE_ACTIVE;
                end
            end
            WRITE_ACTIVE: begin
                if (wr_is_done) begin
                    next_state = READ_ACTIVE;
                end
            end
            READ_ACTIVE: begin
                if (rd_is_done) begin
                    next_state = IDLE;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    Sdram_pll u_sdram_pll (
        .areset(!rst_n_i),
        .inclk0(clk_i),
        .c0(clk_sdram),
        .c1(sdram_clk_o),
        .locked(pll_locked)
    );

    SdramWrFifo #(
        .FIFO_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_sdram_wr_fifo (
        .wr_clk_i(clk_i),
        .rd_clk_i(clk_sdram),
        .rst_n_i(rst_n_i),
        .pack_done_i(pack_done_i),
        .wr_data_i(wr_data_i),

        .window_done_o(window_done),
        .rd_level_o(wr_fifo_level),
        .rd_data_o(wr_fifo_data),

        .wr_ready_o(wr_ready_o),
        .wr_valid_i(wr_valid_i),

        .rd_ready_i(wr_fifo_ready),
        .rd_valid_o(wr_fifo_valid)
    );

    SdramWrCtrl #(
        .DATA_WIDTH  (DATA_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH),
        .BURST_LENGTH(BURST_LENGTH),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) u_sdram_wr_ctrl (
        .clk_i(clk_sdram),
        .rst_n_i(rst_n_sdram),
        .wrrd_clear_i(wrrd_clear),
        .active_i(wr_active),
        .window_done_i(window_done),
        .is_done_o(wr_is_done),

        .fifo_ready_o(wr_fifo_ready),
        .fifo_valid_i(wr_fifo_valid),
        .fifo_data_i (wr_fifo_data),
        .fifo_level_i(wr_fifo_level),

        .cmd_ready_i(cmd_ready && wr_active),
        .cmd_valid_o(wr_ctrl_cmd_valid),
        .cmd_addr_o (wr_ctrl_cmd_addr),
        .cmd_len_o  (wr_ctrl_cmd_len),

        .wr_ready_i(wr_ctrl_ready),
        .wr_valid_o(wr_ctrl_valid),
        .wr_data_o (wr_ctrl_data)
    );

    SdramRdCtrl #(
        .MIC_CNT      (MIC_CNT),
        .DATA_WIDTH   (DATA_WIDTH),
        .FIFO_DEPTH   (FIFO_DEPTH),
        .BURST_LENGTH (BURST_LENGTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .WINDOW_LENGTH(WINDOW_LENGTH)
    ) u_sdram_rd_ctrl (
        .clk_i(clk_sdram),
        .rst_n_i(rst_n_sdram),
        .wrrd_clear_i(wrrd_clear),
        .active_i(rd_active),
        .is_done_o(rd_is_done),

        .cmd_ready_i(cmd_ready && rd_active),
        .cmd_valid_o(rd_ctrl_cmd_valid),
        .cmd_addr_o (rd_ctrl_cmd_addr),
        .cmd_len_o  (rd_ctrl_cmd_len),

        .rd_beat_i(rd_active ? rd_ctrl_beat : 1'b0),
        .rd_data_i(rd_ctrl_data),

        .fifo_ready_i(rd_fifo_ready),
        .fifo_valid_o(rd_fifo_valid),
        .fifo_data_o (rd_fifo_data),
        .fifo_level_i(rd_fifo_level)
    );

    SdramRdFifo #(
        .FIFO_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_sdram_rd_fifo (
        .rst_n_i(rst_n_i),

        .rd_clk_i  (clk_i),
        .rd_ready_i(rd_ready_i),
        .rd_valid_o(rd_valid_o),
        .rd_data_o (rd_data_o),

        .wr_clk_i  (clk_sdram),
        .wr_ready_o(rd_fifo_ready),
        .wr_valid_i(rd_fifo_valid),
        .wr_data_i (rd_fifo_data),
        .wr_level_o(rd_fifo_level)
    );

    SdramControl #(
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_LENGTH(BURST_LENGTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RC_WIDTH(RC_WIDTH),
        .BANK_WIDTH(BANK_WIDTH)
    ) u_sdram_control (
        .clk_i  (clk_sdram),
        .rst_n_i(rst_n_sdram),

        .cmd_ready_o(cmd_ready),
        .cmd_valid_i(cmd_valid),
        .cmd_we_n_i (cmd_we_n),
        .cmd_addr_i (cmd_addr),
        .cmd_len_i  (cmd_len),

        .wr_ready_o(wr_ctrl_ready),
        .wr_valid_i(wr_active ? wr_ctrl_valid : 1'b0),
        .wr_data_i (wr_ctrl_data),

        .rd_beat_o(rd_ctrl_beat),
        .rd_data_o(rd_ctrl_data),

        .sdram_cke_o(sdram_cke_o),
        .sdram_cs_n_o(sdram_cs_n_o),
        .sdram_ras_n_o(sdram_ras_n_o),
        .sdram_cas_n_o(sdram_cas_n_o),
        .sdram_we_n_o(sdram_we_n_o),
        .sdram_ba_o(sdram_ba_o),
        .sdram_addr_o(sdram_addr_o),
        .sdram_dqm_o(sdram_dqm_o),
        .sdram_dq_io(sdram_data_io)
    );

endmodule
