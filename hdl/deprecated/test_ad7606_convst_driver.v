// test_ad7606_convst_driver.v (deprecated MicArraySequenceTest)
// Legacy AD7606 CONVST pattern generator retained for historical reference after INMP441 pivot.

// top-level module declaration with clock and output ports
module MicArraySequenceTest (
        input  wire        clk50,    // 50 MHz system clock (20 ns per cycle)
        output reg         convst_a, // drives AD7606 CONVST_A
        output reg         convst_b, // drives AD7606 CONVST_B
        output wire        adc_reset_n, // RESET# held high; we do not toggle reset here
        output reg         cs_n,     // CS# kept inactive (high)
        output reg         rd_n,     // RD# kept inactive (high)
        output reg  [3:0]  led       // LED outputs for visual feedback
    );

    // active-low pulse width in clock cycles (50 * 20 ns = 1 us)
    localparam integer CONVST_LOW_CYC    = 50;
    // interval between pulses (250000 * 20 ns = 5 ms)
    localparam integer SAMPLE_PERIOD_CYC = 250_000;

    // state encoding for the simple two-state controller
    localparam [1:0]
               ST_CONVST_LOW  = 2'd0,   // CONVST asserted low
               ST_CONVST_HIGH = 2'd1;   // CONVST idle high

    // state register initialised to idle high
    reg [1:0] state   = ST_CONVST_HIGH;
    // shared timing counter initialised to zero
    reg [31:0] counter = 32'd0;

    // keep RESET held low (AD7606 reset is active high; LOW keeps the device enabled)
    assign adc_reset_n = 1'b0;

    // sequential logic triggered on every 50 MHz clock edge
    always @(posedge clk50) begin
        case (state)
            ST_CONVST_LOW: begin
                convst_a <= 1'b0;              // assert CONVST low to start conversion
                convst_b <= 1'b0;
                cs_n     <= 1'b1;              // keep CS high (inactive)
                rd_n     <= 1'b1;              // keep RD high (inactive)
                if (counter >= CONVST_LOW_CYC - 1) begin
                    counter <= 32'd0;          // pulse duration reached; reset counter
                    state   <= ST_CONVST_HIGH; // return to idle high state
                    led[0]  <= ~led[0];        // toggle LED0 for visual heartbeat
                end
                else begin
                    counter <= counter + 1'b1; // continue counting while pulse is active
                end
            end

            ST_CONVST_HIGH: begin
                convst_a <= 1'b1;              // maintain CONVST in idle high level
                convst_b <= 1'b1;
                cs_n     <= 1'b1;
                rd_n     <= 1'b1;
                if (counter >= SAMPLE_PERIOD_CYC - 1) begin
                    counter <= 32'd0;          // interval elapsed; prepare next pulse
                    state   <= ST_CONVST_LOW;  // transition to low pulse state
                end
                else begin
                    counter <= counter + 1'b1; // increment counter during idle interval
                end
            end

            default: begin
                state   <= ST_CONVST_HIGH;     // fallback to idle high if state gets corrupted
                counter <= 32'd0;              // clear counter on recovery
            end
        endcase
    end

endmodule
