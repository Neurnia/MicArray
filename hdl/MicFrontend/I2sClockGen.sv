// I2sClockGen.sv
// Generate BCLK and WS

module I2sClockGen #(
    parameter integer CLK_HZ  = 50_000_000,  // 50MHz
    parameter integer BCLK_HZ = 1_024_000    // 1.024MHz
) (
    // input
    input logic clk_i,
    input logic rst_n_i,

    // output
    output logic bclk_o,
    output logic ws_o
);

    /*
    system clock is 50MHz.
    bclk and ws all comes from clk.
    - bclk
        - frequency of bclk is defined by parameter.
    - ws
        - in a half period of ws, there are 32 full period of bclk.
        - ws changes along with the negative edge of bclk.

    reset behavior:
    - when reset button is pressed, both bclk and ws are set to 0.
    */

    localparam integer ClkInHalfBclk = (CLK_HZ / BCLK_HZ) >> 1;
    localparam integer BclkInHalfWs = 32;
    localparam integer ClkCntBits = $clog2(ClkInHalfBclk);

    logic [4:0] bclk_cnt;  // count bclk when generating ws
    logic [ClkCntBits - 1:0] clk_cnt;  // count clk when generating bclk

    // generate bclk
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            bclk_o  <= 1'b0;
            clk_cnt <= 0;
        end else if (clk_cnt == ClkInHalfBclk - 1) begin
            bclk_o  <= ~bclk_o;
            clk_cnt <= 0;
        end else begin
            clk_cnt <= clk_cnt + 1;
        end
    end

    // delay bclk
    logic bclk_d, bclk_edge;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            bclk_d <= 1'b0;
        end else begin
            bclk_d <= bclk_o;
        end
    end
    assign bclk_edge = bclk_d ^ bclk_o;  // edge detect

    // generate ws
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ws_o <= 1'b0;
            bclk_cnt <= 0;
        end else if (bclk_edge && !bclk_o) begin
            if (bclk_cnt == BclkInHalfWs - 1) begin
                ws_o <= ~ws_o;
                bclk_cnt <= 0;
            end else begin
                bclk_cnt <= bclk_cnt + 1;
            end
        end
    end

endmodule
