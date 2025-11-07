// test_micarray_ad7606.v (deprecated legacy top)
// Archived AD7606 bring-up top kept for reference after migrating to INMP441 digital microphones.
// Drives the ADC using the board's 50 MHz clock and exposes a LED heartbeat
// whenever a new sample is captured. Data pins remain inputs so you can probe
// them with an oscilloscope/logic analyzer during bring-up.

module MicArray (
        input  wire        clk50,        // 50 MHz system clock
        input  wire        sys_rst_n,    // active-low push button reset

        // AD7606 interface
        output wire        convst_a,
        output wire        convst_b,
        output wire        adc_reset_n,
        output wire        cs_n,
        output wire        rd_n,
        input  wire        busy,
        input  wire        frstdata,
        input  wire [15:0] db,

        // Debug LEDs
        output reg  [3:0]  led
    );

    // Synchronize and stretch reset so RESETN stays low for a few cycles
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

    // Slow conversion settings make oscilloscope observation easier.
    localparam integer SAMPLE_PERIOD_CYC   = 250_000; // 50 MHz / 200 SPS
    localparam integer CONVST_LOW_CYC      = 500;     // 10 us low pulse
    localparam integer CONVST_HIGH_GUARD   = 500;     // ensure BUSY has time to rise/fall
    localparam integer RD_DELAY_CYC        = 500;     // wait 10 us after BUSY falls
    localparam integer RD_PULSE_CYC        = 250;     // 5 us low pulse
    localparam integer RESET_PULSE_CYC     = 500;     // hold RESET low for 10 us

    ad7606_controller #(
        .SYS_CLK_HZ        (50_000_000),
        .SAMPLE_PERIOD_CYC (SAMPLE_PERIOD_CYC),
        .CONVST_LOW_CYC    (CONVST_LOW_CYC),
        .CONVST_HIGH_GUARD (CONVST_HIGH_GUARD),
        .RD_DELAY_CYC      (RD_DELAY_CYC),
        .RD_PULSE_CYC      (RD_PULSE_CYC),
        .RESET_PULSE_CYC   (RESET_PULSE_CYC)
    ) adc_ctrl (
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
        .db           (db),
        .sample_data  (sample_data),
        .sample_valid (sample_valid)
    );

    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            led <= 4'b0000;
        end
        else begin
            // Toggle LED0 on each captured sample, others left available.
            if (sample_valid)
                led[0] <= ~led[0];
        end
    end

endmodule
