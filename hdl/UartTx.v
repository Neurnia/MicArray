// UartTx.v
// Minimal UART transmitter with parameterizable baud rate.

module UartTx #(
        parameter integer CLK_HZ  = 50_000_000,
        parameter integer BAUD_HZ = 115_200
    )(
        input  wire clk,
        input  wire rst_n,
        input  wire [7:0] data_in,
        input  wire       data_valid,
        output reg        tx,
        output reg        busy
    );

    localparam integer DIVISOR = CLK_HZ / BAUD_HZ;
    localparam integer DIV_WIDTH = $clog2(DIVISOR);

    reg [DIV_WIDTH-1:0] div_cnt;
    reg baud_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt   <= 0;
            baud_tick <= 1'b0;
        end else if (div_cnt == DIVISOR - 1) begin
            div_cnt   <= 0;
            baud_tick <= 1'b1;
        end else begin
            div_cnt   <= div_cnt + 1'b1;
            baud_tick <= 1'b0;
        end
    end

    reg [9:0] shift_reg;
    reg [3:0] bit_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx       <= 1'b1;
            busy     <= 1'b0;
            shift_reg <= 10'h3FF;
            bit_idx  <= 4'd0;
        end else begin
            if (!busy) begin
                tx <= 1'b1;
                if (data_valid) begin
                    shift_reg <= {1'b1, data_in, 1'b0};
                    bit_idx   <= 4'd0;
                    busy      <= 1'b1;
                end
            end else if (baud_tick) begin
                tx       <= shift_reg[0];
                shift_reg <= {1'b1, shift_reg[9:1]};
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;
                end else begin
                    bit_idx <= bit_idx + 1'b1;
                end
            end
        end
    end

endmodule
