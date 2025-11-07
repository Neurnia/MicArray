// test_ad7606_busy_loop.v (deprecated)
// Legacy AD7606 control-loop top archived for reference; no longer used with INMP441 mics.
// Drives the AD7606 using the ad7606_controller and exposes the captured
// sample_valid strobes so you can probe BUSY/FRSTDATA on a scope.

module Ad7606BusyLoop (
    input  wire        clk50,        // 50 MHz system clock
    input  wire        sys_rst_n,    // active-low push button reset
    input  wire        busy,         // BUSY from AD7606 (after level shifting)
    input  wire        frstdata,     // FRSTDATA from AD7606

    output wire        convst_a,     // CONVST_A output toward ADC
    output wire        convst_b,     // CONVST_B output toward ADC
    output wire        adc_reset_n,  // RESET# toward ADC
    output wire        cs_n,         // CS# toward ADC
    output wire        rd_n,         // RD# toward ADC

    output reg  [3:0]  led           // LED[0] toggles on each sample_valid pulse
);

    // Synchronise the mechanical reset to clk50.
    reg [3:0] rst_sync;
    always @(posedge clk50 or negedge sys_rst_n) begin
        if (!sys_rst_n)
            rst_sync <= 4'b0000;
        else
            rst_sync <= {rst_sync[2:0], 1'b1};
    end
    wire rst_n = rst_sync[3];

    wire [15:0] sample_data;
    wire        sample_valid;

    // Instantiate the controller with slow, scope-friendly timing.
    ad7606_controller #(
        .SYS_CLK_HZ        (50_000_000),
        .SAMPLE_PERIOD_CYC (250_000),   // 5 ms between conversions (~200 SPS)
        .CONVST_LOW_CYC    (500),       // 10 us CONVST low pulse
        .CONVST_HIGH_GUARD (500),       // guard time after BUSY drops
        .RD_DELAY_CYC      (500),       // wait 10 us after BUSY falls
        .RD_PULSE_CYC      (250),       // 5 us RD pulse
        .RESET_PULSE_CYC   (500)        // 10 us RESET low at power-up
    ) ctrl (
        .clk          (clk50),
        .rst_n        (rst_n),
        .enable       (1'b1),
        .convst_a     (convst_a),
        .convst_b     (convst_b),
        .reset_n      (adc_reset_n),
        .cs_n         (cs_n),
        .rd_n         (rd_n),
        .busy         (busy),
        .frstdata     (frstdata),
        .db           (16'h0000),        // data bus not yet wired; tie to zero
        .sample_data  (sample_data),
        .sample_valid (sample_valid)
    );

    // Toggle LED0 whenever a conversion result becomes available.
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n)
            led <= 4'b0000;
        else if (sample_valid)
            led[0] <= ~led[0];
    end

endmodule
