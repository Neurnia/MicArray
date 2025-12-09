// SampleRamFifo.v
// Simple single-clock FIFO backed by block RAM.
// Uses ready/valid handshakes to decouple writer (e.g., I2S capture)
// from reader (e.g., UART streamer).

module SampleRamFifo #(
    parameter integer DATA_WIDTH = 24,
    parameter integer ADDR_WIDTH = 10   // depth = 2^ADDR_WIDTH
) (
    input  wire                  clk_i,
    input  wire                  rst_n_i,
    // Write side
    input  wire                  wr_valid_i,
    input  wire [DATA_WIDTH-1:0] wr_data_i,
    output wire                  wr_ready_o,
    output reg                   overflow_o,
    // Read side
    input  wire                  rd_ready_i,
    output reg                   rd_valid_o,
    output reg  [DATA_WIDTH-1:0] rd_data_o,
    output reg                   underflow_o,
    // Status
    output wire [  ADDR_WIDTH:0] level_o
);

    localparam integer DEPTH = 1 << ADDR_WIDTH;

    // Memory and pointers (extra MSB tracks wrap for full/empty detection).
    reg [DATA_WIDTH-1:0] mem[0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    wire fifo_empty = (wr_ptr == rd_ptr);
    wire fifo_full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                      (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    assign wr_ready_o = ~fifo_full;
    assign level_o    = wr_ptr - rd_ptr;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wr_ptr      <= {ADDR_WIDTH + 1{1'b0}};
            rd_ptr      <= {ADDR_WIDTH + 1{1'b0}};
            rd_data_o   <= {DATA_WIDTH{1'b0}};
            rd_valid_o  <= 1'b0;
            overflow_o  <= 1'b0;
            underflow_o <= 1'b0;
        end else begin
            overflow_o  <= 1'b0;
            underflow_o <= 1'b0;

            // Write
            if (wr_valid_i) begin
                if (!fifo_full) begin
                    mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data_i;
                    wr_ptr <= wr_ptr + 1'b1;
                end else begin
                    overflow_o <= 1'b1;
                end
            end

            // Prefetch current read data; valid flags emptiness.
            rd_data_o  <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            rd_valid_o <= ~fifo_empty;

            // Read pointer advances only on handshake.
            if (rd_ready_i) begin
                if (!fifo_empty) begin
                    rd_ptr <= rd_ptr + 1'b1;
                end else begin
                    underflow_o <= 1'b1;
                end
            end
        end
    end

endmodule

