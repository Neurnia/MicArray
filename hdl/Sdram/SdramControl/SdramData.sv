// SdramData.sv
// Handle bidirectional DQ bus behavior and write/read beat data movement.
// Read beats are controller-driven once a read burst starts.

module SdramData #(
    parameter int DATA_WIDTH = 16
) (
    // basic
    input logic clk_i,
    input logic rst_n_i,

    // upstream write
    output logic wr_ready_o,
    input logic wr_valid_i,
    input logic [DATA_WIDTH - 1:0] wr_data_i,

    // upstream read
    output logic rd_beat_o,
    output logic [DATA_WIDTH - 1:0] rd_data_o,

    // control from SdramCore
    input  logic wr_phase_i,
    input  logic wr_beat_i,
    input  logic rd_phase_i,
    input  logic rd_beat_i,
    output logic rd_beat_fire_o,
    output logic wr_beat_fire_o,

    // SDRAM DQ bus
    inout wire [DATA_WIDTH - 1:0] sdram_dq_io
);

    logic [DATA_WIDTH - 1:0] dq_o;
    logic [DATA_WIDTH - 1:0] dq_i;
    logic dq_oe;

    // write signal
    assign wr_ready_o     = wr_phase_i && wr_beat_i;
    assign wr_beat_fire_o = wr_valid_i && wr_ready_o;

    // read signal
    assign rd_beat_fire_o = rd_phase_i && rd_beat_i;

    // data bus direction control
    assign dq_oe          = wr_phase_i && wr_beat_i;  // drive only on active write beats
    assign sdram_dq_io    = dq_oe ? dq_o : 'z;  // drive data when output enable is high
    assign dq_i           = sdram_dq_io;  // read data from bus

    // data wires
    assign dq_o           = wr_data_i;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_beat_o <= 1'b0;
            rd_data_o <= '0;
        end else begin
            rd_beat_o <= rd_beat_fire_o;
            if (rd_beat_fire_o) begin
                rd_data_o <= dq_i;
            end
        end
    end

endmodule
