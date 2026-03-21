// SdramRdFifo.sv
// Quartus FIFO IP wrapper for read path.

module SdramRdFifo #(
    parameter int FIFO_WIDTH = 16,
    parameter int FIFO_DEPTH = 512
) (
    // basic
    input logic rst_n_i,

    // read side
    input logic rd_clk_i,
    input logic rd_ready_i,
    output logic rd_valid_o,
    output logic [FIFO_WIDTH - 1:0] rd_data_o,

    // write side
    input logic wr_clk_i,
    output logic wr_ready_o,
    input logic wr_valid_i,
    input logic [FIFO_WIDTH - 1:0] wr_data_i,
    output logic [$clog2(FIFO_DEPTH) - 1:0] wr_level_o  // used level
);

    logic full;
    logic empty;
    logic wr_fire;
    logic rd_fire;

    assign wr_ready_o = !full;
    assign rd_valid_o = !empty;

    assign wr_fire = wr_valid_i && wr_ready_o;
    assign rd_fire = rd_valid_o && rd_ready_i;

    SdramRd_dcfifo u_sdram_rd_dcfifo (
        .aclr(!rst_n_i),

        .data(wr_data_i),
        .wrclk(wr_clk_i),
        .wrreq(wr_fire),
        .wrfull(full),
        .wrusedw(wr_level_o),

        .rdclk  (rd_clk_i),
        .rdreq  (rd_fire),
        .q      (rd_data_o),
        .rdempty(empty)
    );

endmodule
