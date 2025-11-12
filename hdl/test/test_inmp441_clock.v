// test_inmp441_clock.v
// Minimal top-level to exercise INMP441 clocking. Generates BCLK/WS pairs using
// Inmp441ClockGen and drives the microphone's L/R select line. LED0 toggles on each
// WS rising edge so you can confirm activity without instruments.

module TestInmp441Clock #(
        parameter integer INPUT_CLK_HZ   = 50_000_000,
        parameter integer TARGET_BCLK_HZ = 3_125_000,
        parameter        LR_SELECT       = 1'b0   // 0: left slot, 1: right slot
    )(
        input  wire        clk50,
        input  wire        rst_n,
        output wire        i2s_bclk,
        output wire        i2s_ws,
        output wire        i2s_lr_sel,
        output reg  [3:0]  led
    );

    wire ws_int;
    wire bclk_int;

    Inmp441ClockGen #(
        .INPUT_CLK_HZ   (INPUT_CLK_HZ),
        .TARGET_BCLK_HZ (TARGET_BCLK_HZ)
    ) clkgen (
        .clk (clk50),
        .rst_n (rst_n),
        .bclk (bclk_int),
        .ws (ws_int)
    );

    assign i2s_bclk   = bclk_int;
    assign i2s_ws     = ws_int;
    assign i2s_lr_sel = LR_SELECT;

    reg ws_prev;

    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n)
            ws_prev <= 1'b0;
        else
            ws_prev <= ws_int;
    end

    wire ws_rise = (~ws_prev) & ws_int;

    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n)
            led <= 4'b0000;
        else if (ws_rise)
            led[0] <= ~led[0];
    end

endmodule
