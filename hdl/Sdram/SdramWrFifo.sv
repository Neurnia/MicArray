// SdramWrFifo.sv
// Wrapper for Quartus IP core
// upstream module RecordPacker & downstream module Sdram

module SdramWrFifo #(
    parameter int FIFO_WIDTH = 16,
    parameter int FIFO_DEPTH = 512
) (
    // input
    input logic wr_clk_i,
    input logic rd_clk_i,  // clock for SDRAM
    input logic rst_n_i,
    input logic pack_done_i,  // pulse
    input logic [FIFO_WIDTH - 1:0] wr_data_i,

    // output (sd clk)
    output logic window_done_o,  // pulse
    output logic [$clog2(FIFO_DEPTH) - 1:0] rd_level_o,  // fill level of the fifo
    output logic [FIFO_WIDTH - 1:0] rd_data_o,

    // upstream handshake
    output logic wr_ready_o,
    input  logic wr_valid_i,

    // downstream handshake (sd clk)
    input  logic rd_ready_i,
    output logic rd_valid_o
);

    // handle valid & ready output
    logic full, empty;
    assign wr_ready_o = !full;
    assign rd_valid_o = !empty;

    // upstream handshake
    logic wr_fire;
    assign wr_fire = wr_valid_i && wr_ready_o;
    // downstream handshake
    logic rd_fire;
    assign rd_fire = rd_valid_o && rd_ready_i;

    // dcfifo ip core
    SdramWr_dcfifo u_sdram_wr_dcfifo (
        .aclr(!rst_n_i),  // reset

        .wrclk(wr_clk_i),  // write clock
        .wrreq(wr_fire),  // write request
        .data(wr_data_i),  // input data
        .wrfull(full),  // write full signal

        .rdclk(rd_clk_i),  // read clock
        .rdreq(rd_fire),  // read request
        .q(rd_data_o),  // output data
        .rdempty(empty),  // read empty signal
        .rdusedw(rd_level_o)  // number of words in fifo (read clock)
    );

    // CDC done signal (toggle synchronizer)
    logic done_toggle;
    logic [1:0] toggle_sync;

    // write clock
    always_ff @(posedge wr_clk_i or negedge rst_n_i) begin
        if (!rst_n_i) done_toggle <= 1'b0;
        else if (pack_done_i) begin
            done_toggle <= ~done_toggle;
        end
    end

    // read clock
    always_ff @(posedge rd_clk_i or negedge rst_n_i) begin
        if (!rst_n_i) toggle_sync <= 2'b0;
        else toggle_sync <= {toggle_sync[0], done_toggle};
    end
    assign window_done_o = ^toggle_sync;

endmodule
