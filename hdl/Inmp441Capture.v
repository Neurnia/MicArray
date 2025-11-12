// Inmp441Capture.v
// Deserializes a single INMP441 I2S slot (left or right) into 24-bit samples.
// Assumes bclk/ws are generated synchronously from the provided clk.

module Inmp441Capture #(
        parameter integer CHANNEL_SELECT = 0  // 0 = left (WS low), 1 = right (WS high)
    )(
        input  wire        clk,
        input  wire        rst_n,
        input  wire        bclk,
        input  wire        ws,
        input  wire        sd,
        output reg  [23:0] sample_data,
        output reg         sample_valid
    );

    reg bclk_d, ws_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_d <= 1'b0;
            ws_d   <= 1'b0;
        end else begin
            bclk_d <= bclk;
            ws_d   <= ws;
        end
    end

    wire bclk_rise = ~bclk_d & bclk;
    wire ws_toggle = ws ^ ws_d;

    reg [4:0] bit_cnt;
    reg [23:0] shift_reg;
    reg collecting;
    reg wait_msb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt      <= 5'd0;
            shift_reg    <= 24'd0;
            collecting   <= 1'b0;
            wait_msb     <= 1'b0;
            sample_data  <= 24'd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;

            if (ws_toggle) begin
                collecting <= (ws == CHANNEL_SELECT);
                wait_msb   <= (ws == CHANNEL_SELECT);
                bit_cnt    <= 5'd0;
            end

            if (collecting && bclk_rise) begin
                if (wait_msb) begin
                    wait_msb <= 1'b0; // skip the first BCLK after WS transition per I2S
                end else begin
                    shift_reg <= {shift_reg[22:0], sd};
                    if (bit_cnt == 5'd23) begin
                        sample_data  <= {shift_reg[22:0], sd};
                        sample_valid <= 1'b1;
                        collecting   <= 1'b0;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
            end
        end
    end

endmodule
