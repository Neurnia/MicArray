// Inmp441ClockGen.v
// Generates I2S-style bit clock (BCLK) and word select (WS) from the 50 MHz system clock.
// BCLK is produced by integer division; WS toggles every 32 BCLK rising edges so a full frame
// contains 64 BCLK cycles. This module is sufficient for early INMP441 bring-up before
// introducing a PLL for tighter frequency accuracy.

module Inmp441ClockGen #(
        parameter integer INPUT_CLK_HZ = 50_000_000,
        parameter integer TARGET_BCLK_HZ = 3_125_000   // approx 3.072 MHz (48 kHz * 64)
    )(
        input  wire clk,
        input  wire rst_n,
        output reg  bclk,
        output reg  ws
    );

    localparam integer DIVISOR = INPUT_CLK_HZ / TARGET_BCLK_HZ;
    localparam integer HALF_PERIOD = (DIVISOR >> 1);
    localparam integer CNT_WIDTH = $clog2(HALF_PERIOD);

    reg [CNT_WIDTH-1:0] div_cnt;
    reg bclk_prev;
    reg [5:0] ws_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 0;
            bclk    <= 1'b0;
        end else if (div_cnt == HALF_PERIOD - 1) begin
            div_cnt <= 0;
            bclk    <= ~bclk;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bclk_prev <= 1'b0;
        else
            bclk_prev <= bclk;
    end

    wire bclk_rise = (~bclk_prev) & bclk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws      <= 1'b0;
            ws_cnt  <= 6'd0;
        end else if (bclk_rise) begin
            if (ws_cnt == 6'd31) begin
                ws_cnt <= 6'd0;
                ws     <= ~ws;
            end else begin
                ws_cnt <= ws_cnt + 1'b1;
            end
        end
    end

endmodule
