// SdramControl.sv
// SDRAM chip-level transaction execution module.
// Wrapper for SdramCore & SdramData module.

module SdramControl #(
    parameter int DATA_WIDTH = 16,
    parameter int BURST_LENGTH = 8,
    parameter int ADDR_WIDTH = 24,
    parameter int RC_WIDTH = 13,
    parameter int BANK_WIDTH = 2
) (
    // basic
    input logic clk_i,
    input logic rst_n_i,

    // cmd
    output logic cmd_ready_o,
    input logic cmd_valid_i,
    input logic cmd_we_n_i,  // 0 for write and 1 for read
    input logic [ADDR_WIDTH - 1:0] cmd_addr_i,  // linear 16-bit word address
    input logic [$clog2(BURST_LENGTH + 1) - 1:0] cmd_len_i,  // transaction length

    // write
    output logic wr_ready_o,
    input logic wr_valid_i,
    input logic [DATA_WIDTH - 1:0] wr_data_i,

    // read
    input logic rd_ready_i,
    output logic rd_valid_o,
    output logic [DATA_WIDTH - 1:0] rd_data_o,

    // SDRAM pins
    output logic sdram_cke_o,
    output logic sdram_cs_n_o,
    output logic sdram_ras_n_o,
    output logic sdram_cas_n_o,
    output logic sdram_we_n_o,
    output logic [BANK_WIDTH - 1:0] sdram_ba_o,
    output logic [RC_WIDTH - 1:0] sdram_addr_o,
    output logic [(DATA_WIDTH / 8) - 1:0] sdram_dqm_o,  // mask
    inout wire [DATA_WIDTH - 1:0] sdram_dq_io  // data
);

    // internal signals
    logic wr_phase;
    logic wr_beat;
    logic rd_phase;
    logic rd_beat;
    logic wr_beat_fire;
    logic rd_beat_fire;

    SdramCore #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .BURST_LENGTH(BURST_LENGTH),
        .RC_WIDTH(RC_WIDTH),
        .BANK_WIDTH(BANK_WIDTH)
    ) u_sdram_core (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),

        .cmd_ready_o(cmd_ready_o),
        .cmd_valid_i(cmd_valid_i),
        .cmd_we_n_i (cmd_we_n_i),
        .cmd_addr_i (cmd_addr_i),
        .cmd_len_i  (cmd_len_i),

        .wr_phase_o(wr_phase),
        .wr_beat_o(wr_beat),
        .rd_phase_o(rd_phase),
        .rd_beat_o(rd_beat),
        .rd_beat_fire_i(rd_beat_fire),
        .wr_beat_fire_i(wr_beat_fire),

        .sdram_cke_o(sdram_cke_o),
        .sdram_cs_n_o(sdram_cs_n_o),
        .sdram_ras_n_o(sdram_ras_n_o),
        .sdram_cas_n_o(sdram_cas_n_o),
        .sdram_we_n_o(sdram_we_n_o),
        .sdram_ba_o(sdram_ba_o),
        .sdram_addr_o(sdram_addr_o),
        .sdram_dqm_o(sdram_dqm_o)
    );

    SdramData #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_sdram_data (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),

        .wr_ready_o(wr_ready_o),
        .wr_valid_i(wr_valid_i),
        .wr_data_i (wr_data_i),

        .rd_ready_i(rd_ready_i),
        .rd_valid_o(rd_valid_o),
        .rd_data_o (rd_data_o),

        .wr_phase_i(wr_phase),
        .wr_beat_i(wr_beat),
        .rd_phase_i(rd_phase),
        .rd_beat_i(rd_beat),
        .rd_beat_fire_o(rd_beat_fire),
        .wr_beat_fire_o(wr_beat_fire),

        .sdram_dq_io(sdram_dq_io)
    );

endmodule
