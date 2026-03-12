// I2sClockGen.v
// Generate BCLK and WS (LRCLK) from a single system clock.
// WS toggles every 32 BCLK falling edges (64 BCLK per full stereo frame),
// matching the typical I2S convention where LRCLK changes on BCLK falling.

module I2sClockGen #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer WS_HZ  = 1_024_000    // 16 kHz * 64
) (
    input  wire clk_i,
    input  wire rst_n_i,
    output reg  bclk_o,
    output reg  ws_o
);

    localparam integer DIVISOR = CLK_HZ / WS_HZ;
    localparam integer HALF_PERIOD = DIVISOR >> 1;
    localparam integer CNT_WIDTH = $clog2(HALF_PERIOD);

    reg [CNT_WIDTH-1:0] div_cnt;
    reg                 bclk_d;
    reg [          5:0] ws_cnt;

    // BCLK divider
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            div_cnt <= 0;
            bclk_o  <= 1'b0;
        end else if (div_cnt == HALF_PERIOD - 1) begin
            div_cnt <= 0;
            bclk_o  <= ~bclk_o;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    // Edge detect
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) bclk_d <= 1'b0;
        else bclk_d <= bclk_o;
    end
    wire bclk_rise = (~bclk_d) & bclk_o;
    wire bclk_fall = bclk_d & (~bclk_o);

    // WS divider: toggle every 32 BCLK falling edges
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ws_o   <= 1'b0;
            ws_cnt <= 6'd0;
        end else if (bclk_fall) begin
            if (ws_cnt == 6'd31) begin
                ws_cnt <= 6'd0;
                ws_o   <= ~ws_o;
            end else begin
                ws_cnt <= ws_cnt + 1'b1;
            end
        end
    end

endmodule
