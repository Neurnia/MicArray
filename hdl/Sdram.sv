// Sdram.sv
// SDRAM write-path wrapper.
// This module owns the PLL-generated SDRAM clock domain.
// `SdramWrFifo` remains the only CDC boundary from the system clock domain
// into the SDRAM domain.

module Sdram #(
    parameter int DATA_WIDTH   = 16,
    parameter int FIFO_DEPTH   = 512,
    parameter int BURST_LENGTH = 8,
    parameter int ADDR_WIDTH   = 24,
    parameter int RC_WIDTH     = 13,
    parameter int BANK_WIDTH   = 2
) (
    // system-side write ingress
    input logic clk_i,
    input logic rst_n_i,
    input logic pack_done_i,
    input logic [DATA_WIDTH - 1:0] wr_data_i,
    input logic wr_valid_i,
    output logic wr_ready_o,

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

    logic window_done;
    logic [$clog2(FIFO_DEPTH) - 1:0] fifo_level;
    logic [DATA_WIDTH - 1:0] fifo_data;
    logic fifo_ready;
    logic fifo_valid;

    logic cmd_ready;
    logic cmd_valid;
    logic cmd_we_n;
    logic [ADDR_WIDTH - 1:0] cmd_addr;
    logic [$clog2(BURST_LENGTH + 1) - 1:0] cmd_len;

    logic wr_chan_ready;
    logic wr_chan_valid;
    logic [DATA_WIDTH - 1:0] wr_chan_data;

    logic rd_beat_unused;  // reserved for the future SDRAM read path
    logic [DATA_WIDTH - 1:0] rd_data_unused;  // reserved for the future SDRAM read path

    assign rst_n_sdram = rst_n_i && pll_locked;

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
        .rd_level_o(fifo_level),
        .rd_data_o(fifo_data),

        .wr_ready_o(wr_ready_o),
        .wr_valid_i(wr_valid_i),

        .rd_ready_i(fifo_ready),
        .rd_valid_o(fifo_valid)
    );

    SdramWrCtrl #(
        .DATA_WIDTH  (DATA_WIDTH),
        .FIFO_DEPTH  (FIFO_DEPTH),
        .BURST_LENGTH(BURST_LENGTH),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) u_sdram_wr_ctrl (
        .clk_i(clk_sdram),
        .rst_n_i(rst_n_sdram),
        .window_done_i(window_done),

        .fifo_ready_o(fifo_ready),
        .fifo_valid_i(fifo_valid),
        .fifo_data_i (fifo_data),
        .fifo_level_i(fifo_level),

        .cmd_ready_i(cmd_ready),
        .cmd_valid_o(cmd_valid),
        .cmd_we_n_o (cmd_we_n),
        .cmd_addr_o (cmd_addr),
        .cmd_len_o  (cmd_len),

        .wr_ready_i(wr_chan_ready),
        .wr_valid_o(wr_chan_valid),
        .wr_data_o (wr_chan_data)
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

        .wr_ready_o(wr_chan_ready),
        .wr_valid_i(wr_chan_valid),
        .wr_data_i (wr_chan_data),

        .rd_beat_o(rd_beat_unused),
        .rd_data_o(rd_data_unused),

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
