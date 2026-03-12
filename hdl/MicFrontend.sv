// MicFrontend.sv
// Wrapper for MicFrontend layer.
// Include I2sClockGen, I2sCapture and FrameCollect
// Designed downstream: RecordControl

module MicFrontend #(
    parameter int MIC_CNT = 8,
    parameter int SAMPLE_WIDTH = 16,
    parameter integer CLK_HZ = 50_000_000,  // 50MHz
    parameter integer BCLK_HZ = 1_024_000  // 1.024MHz
) (
    // input
    input logic clk_i,
    input logic rst_n_i,
    input logic [MIC_CNT - 1:0] sd_i,  // I2s sd from microphones

    // output
    output logic frame_change_o,  // frame change signal based on ws
    // stay unchanged until the next complete collection
    output logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] frame_data_o,
    // pulse signal for incomplete frame, only activates one clk after frame change
    output logic frame_error_o,

    // handshake
    input  logic frame_ready_i,  // pulse signal
    output logic frame_valid_o   // mark validity of data, stay high until there is a ready signal
);

    // clock generation
    logic bclk;
    logic ws;
    I2sClockGen #(
        .CLK_HZ (CLK_HZ),
        .BCLK_HZ(BCLK_HZ)
    ) u_i2s_clock_gen (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),

        .bclk_o(bclk),
        .ws_o  (ws)
    );

    // frame change generation
    logic ws_d;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ws_d <= 1'b0;
        end else begin
            ws_d <= ws;
        end
    end
    assign frame_change_o = ws_d && !ws;  // negative edge of ws


    // microphone data capture modules
    // use genvar to generate parameterized structure
    logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] sample_data;  // data from all mics
    logic [MIC_CNT - 1:0] sample_valid;  // valid data from all mics
    for (genvar ch = 0; ch < MIC_CNT; ch++) begin : g_i2s_capture
        I2sCapture #(
            .SAMPLE_WIDTH(SAMPLE_WIDTH)
        ) u_i2s_capture (
            .clk_i(clk_i),
            .rst_n_i(rst_n_i),
            .bclk_i(bclk),
            .ws_i(ws),
            .sd_i(sd_i[ch]),

            .sample_data_o (sample_data[ch]),
            .sample_valid_o(sample_valid[ch])
        );
    end

    // frame collecting
    FrameCollect #(
        .MIC_CNT(MIC_CNT),
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) u_frame_collect (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .frame_change_i(frame_change_o),
        .sample_data_i(sample_data),
        .sample_valid_i(sample_valid),

        .frame_data_o (frame_data_o),
        .frame_error_o(frame_error_o),

        .frame_ready_i(frame_ready_i),
        .frame_valid_o(frame_valid_o)
    );

endmodule
