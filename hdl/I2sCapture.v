// I2sCapture.v
// Capture a single I2S slot (left or right) into a 24-bit word.
// Assumes BCLK/WS are synchronous to clk (generated on-FPGA).

module I2sCapture #(
    parameter integer CHANNEL_SELECT = 0  // 0 = left (WS low), 1 = right (WS high)
) (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        bclk_i,
    input  wire        ws_i,
    input  wire        sd_i,
    output reg  [23:0] sample_data_o,
    output reg         sample_valid_o
);

    reg bclk_d, ws_d;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            bclk_d <= 1'b0;
            ws_d   <= 1'b0;
        end else begin
            bclk_d <= bclk_i;
            ws_d   <= ws_i;
        end
    end

    wire        bclk_rise = (~bclk_d) & bclk_i;
    wire        ws_edge = ws_i ^ ws_d;

    reg  [23:0] shift_reg;
    reg  [ 4:0] bit_cnt;
    reg         collecting;
    reg         wait_msb;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            shift_reg      <= 24'd0;
            bit_cnt        <= 5'd0;
            collecting     <= 1'b0;
            wait_msb       <= 1'b0;
            sample_data_o  <= 24'd0;
            sample_valid_o <= 1'b0;
        end else begin
            sample_valid_o <= 1'b0;

            if (ws_edge) begin
                collecting <= (ws_i == CHANNEL_SELECT);
                wait_msb   <= (ws_i == CHANNEL_SELECT);
                bit_cnt    <= 5'd0;
            end

            if (collecting && bclk_rise) begin
                if (wait_msb) begin
                    wait_msb <= 1'b0;  // I2S one-bit delay after WS edge
                end else begin
                    shift_reg <= {shift_reg[22:0], sd_i};
                    if (bit_cnt == 5'd23) begin
                        sample_data_o <= {shift_reg[22:0], sd_i};
                        sample_valid_o <= 1'b1;
                        collecting <= 1'b0;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
            end
        end
    end

endmodule
