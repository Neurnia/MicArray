// core_ad7606_controller.v (deprecated legacy core)
// Legacy AD7606 parallel ADC driver retained for reference after moving to INMP441 digital mics.
// Generates CONVST pulses at a programmable rate, waits for BUSY to deassert,
// then performs a single 16-bit read using CS/RD strobes. Captured samples
// are exposed on sample_data/sample_valid for debug or downstream logic.

module ad7606_controller #(
        parameter integer SYS_CLK_HZ         = 50_000_000,
        parameter integer SAMPLE_PERIOD_CYC  = 1_000_000, // default placeholder
        parameter integer CONVST_LOW_CYC     = 4,
        parameter integer CONVST_HIGH_GUARD  = 4,
        parameter integer RD_DELAY_CYC       = 6,
        parameter integer RD_PULSE_CYC       = 3,
        parameter integer RESET_PULSE_CYC    = 32
    )(
        input  wire        clk,
        input  wire        rst_n,
        input  wire        enable,

        // AD7606 interface
        output reg         convst_a,
        output reg         convst_b,
        output wire        reset_n,
        output reg         cs_n,
        output reg         rd_n,
        input  wire        busy,
        input  wire        frstdata,
        input  wire [15:0] db,         // parallel data bus from AD7606

        // Output sample
        output reg  [15:0] sample_data,
        output reg         sample_valid
    );

    localparam integer IDLE             = 0;
    localparam integer CONVST_ASSERT    = 1;
    localparam integer WAIT_BUSY_HIGH   = 2;
    localparam integer WAIT_BUSY_LOW    = 3;
    localparam integer PREP_READ        = 4;
    localparam integer RD_STROBE        = 5;
    localparam integer POST_READ        = 6;

    reg [2:0]  state;
    reg [31:0] period_cnt;
    reg [15:0] timer_cnt;
    reg        reset_n_reg;
    reg [15:0] reset_cnt;
    reg        reset_hold;

    assign reset_n = reset_n_reg;

    wire period_done = (period_cnt == SAMPLE_PERIOD_CYC - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_cnt   <= 0;
        end
        else if (state == IDLE) begin
            if (period_done)
                period_cnt <= 0;
            else
                period_cnt <= period_cnt + 1;
        end
        else begin
            period_cnt <= 0;
        end
    end

    // Reset pulse generator: emit a short active-high pulse then hold low
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reset_n_reg <= 1'b0;
            reset_cnt   <= 0;
            reset_hold  <= 1'b1;
        end else if (reset_hold) begin
            if (reset_cnt == RESET_PULSE_CYC - 1) begin
                reset_n_reg <= 1'b0;   // return low after the pulse
                reset_hold  <= 1'b0;
            end else begin
                reset_cnt   <= reset_cnt + 1;
                reset_n_reg <= 1'b1;   // drive high during the pulse window
            end
        end else begin
            reset_n_reg <= 1'b0;       // keep RESET low during normal operation
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            timer_cnt    <= 0;
            convst_a     <= 1'b1;
            convst_b     <= 1'b1;
            cs_n         <= 1'b1;
            rd_n         <= 1'b1;
            sample_data  <= 16'd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;     // default: only raise for a single cycle

            case (state)
                IDLE: begin
                    convst_a <= 1'b1;
                    convst_b <= 1'b1;
                    cs_n     <= 1'b1;
                    rd_n     <= 1'b1;
                    timer_cnt <= 0;

                    if (enable && !reset_hold && period_done) begin
                        state <= CONVST_ASSERT;
                    end
                end

                CONVST_ASSERT: begin
                    convst_a <= 1'b0;
                    convst_b <= 1'b0;
                    if (timer_cnt == CONVST_LOW_CYC - 1) begin
                        convst_a <= 1'b1;
                        convst_b <= 1'b1;
                        timer_cnt <= 0;
                        state <= WAIT_BUSY_HIGH;
                    end
                    else begin
                        timer_cnt <= timer_cnt + 1;
                    end
                end

                WAIT_BUSY_HIGH: begin
                    if (busy) begin
                        timer_cnt <= 0;
                        state <= WAIT_BUSY_LOW;
                    end
                end

                WAIT_BUSY_LOW: begin
                    if (!busy && timer_cnt >= CONVST_HIGH_GUARD - 1) begin
                        timer_cnt <= 0;
                        state <= PREP_READ;
                    end
                    else begin
                        timer_cnt <= timer_cnt + 1;
                    end
                end

                PREP_READ: begin
                    cs_n <= 1'b0;
                    if (timer_cnt == RD_DELAY_CYC - 1) begin
                        timer_cnt <= 0;
                        state <= RD_STROBE;
                    end
                    else begin
                        timer_cnt <= timer_cnt + 1;
                    end
                end

                RD_STROBE: begin
                    rd_n <= 1'b0;
                    if (timer_cnt == RD_PULSE_CYC - 1) begin
                        rd_n <= 1'b1;
                        timer_cnt <= 0;
                        state <= POST_READ;

                        // Capture the first channel (when FRSTDATA is high)
                        sample_data  <= db;
                        sample_valid <= 1'b1;
                    end
                    else begin
                        timer_cnt <= timer_cnt + 1;
                    end
                end

                POST_READ: begin
                    cs_n <= 1'b1;
                    state <= IDLE;
                end

                default:
                    state <= IDLE;
            endcase
        end
    end

endmodule
