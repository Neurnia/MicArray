// FrameCollect.sv
// Manage data collection in one single frame.

module FrameCollect #(
    parameter int MIC_CNT = 8,
    parameter int SAMPLE_WIDTH = 16
) (
    // input
    input logic clk_i,
    input logic rst_n_i,
    // frame change pulls high when in every negative edge of ws, one ws period marks one frame
    input logic frame_change_i,
    input logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] sample_data_i,  // data from all mics
    input logic [MIC_CNT - 1:0] sample_valid_i,  // valid data from all mics

    //output
    // stay unchanged until the next complete collection
    output logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] frame_data_o,
    // pulse signal for incomplete frame, only activates one clk after frame change
    output logic frame_error_o,

    // handshake
    input  logic frame_ready_i,  // pulse signal
    output logic frame_valid_o   // mark validity of data, stay high until there is a ready signal

);
    /*
    Frames are synchronized with I2sClockGen module.
    Whole process of in one frame:
    - Receive the data and put them all into the buffers.
    - Once valid_buf is all high, pull frame_valid_o high.
    - When frame_ready_i is high,
    which means other modules have already received the frame,
    reset valid and start the next round.

    There are several assumptions in the module:
    - For a normal frame, all data from all channels arrive well before frame change,
    at least one clk_i period before.
    - In every frame, each channel will only be valid once and send one data.
    - In most of the cases, downstream will finish it work within the frame.
    */

    // buffers
    // in order to check & sync valid
    logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] frame_buf;  // frame buffer
    logic [MIC_CNT - 1:0]                     valid_buf;  // valid buffer

    // check if all channels are collected
    logic                                     collect_done;
    logic                                     collect_done_reg;
    assign collect_done = &valid_buf;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            frame_buf <= '0;  // set all values in the array as 0
            valid_buf <= '0;
            frame_data_o <= '0;
            frame_valid_o <= 1'b0;
            frame_error_o <= 1'b0;
            collect_done_reg <= 1'b0;
        end else begin
            frame_error_o <= 1'b0;  // keep error low
            // 1. handle frame changes
            if (frame_change_i) begin
                if (!collect_done_reg || frame_valid_o) begin
                    frame_error_o <= 1'b1;  // incomplete data or failed handshake
                end
                // reset values
                frame_buf <= '0;
                valid_buf <= '0;
                frame_valid_o <= 1'b0;
                collect_done_reg <= 1'b0;
            end else begin
                // 2. handle within a frame
                if (!frame_valid_o) begin
                    // buffer data
                    for (int ch = 0; ch < MIC_CNT; ch++) begin
                        if (sample_valid_i[ch] && !valid_buf[ch]) begin
                            valid_buf[ch] <= sample_valid_i[ch];
                            frame_buf[ch] <= sample_data_i[ch];
                        end
                    end
                    // output data
                    if (collect_done) begin
                        collect_done_reg <= 1'b1;
                        frame_data_o <= frame_buf;
                        frame_valid_o <= 1'b1;
                    end
                end else if (frame_valid_o && frame_ready_i) begin
                    // reset valid
                    valid_buf <= '0;
                    frame_valid_o <= 1'b0;
                end
            end
        end
    end

endmodule
