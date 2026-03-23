// MicArrayTop.sv
// Minimal top-level integration for the SDRAM buffer and UART readback path.

module MicArrayTop #(
    parameter int MIC_CNT             = 2,
    parameter int SAMPLE_WIDTH        = 16,
    parameter int WINDOW_LENGTH       = 160_000,
    parameter int FIFO_DEPTH          = 512,
    parameter int SDRAM_ADDR_W        = 24,
    parameter int SDRAM_RC_W          = 13,
    parameter int SDRAM_BANK_W        = 2,
    parameter int CLK_HZ              = 50_000_000,
    parameter int UART_BAUD_HZ        = 921_600,
    parameter int BCLK_HZ             = 1_024_000,
    parameter int KEY_DEBOUNCE_CYCLES = 1_000_000    // 20 ms at 50 MHz
) (
    // System
    input logic clk_i,    // system clock
    input logic rst_n_i,
    input logic key_n_i,  // active-low button for record start

    // I2S
    input logic [MIC_CNT - 1:0] i2s_sd_i,
    output logic i2s_bclk_o,
    output logic i2s_ws_o,

    // UART
    input  logic uart_rx_i,  // reserved for the future UART readback path
    output logic uart_tx_o,

    // LEDs
    output logic [2:0] led_n_o,

    // SDRAM
    output logic sdram_clk,
    output logic sdram_cke,
    output logic sdram_cs_n,
    output logic sdram_ras_n,
    output logic sdram_cas_n,
    output logic sdram_we_n,
    output logic [SDRAM_BANK_W - 1:0] sdram_ba,
    output logic [SDRAM_RC_W - 1:0] sdram_addr,
    output logic [(SAMPLE_WIDTH / 8) - 1:0] sdram_dqm,
    inout wire [SAMPLE_WIDTH - 1:0] sdram_data
);

    logic frame_change;
    logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] frame_data;
    logic frame_error;
    logic frame_ready;
    logic frame_valid;

    logic record_start_raw;
    logic record_start;
    logic record_start_is_allowed;
    logic record_done;
    logic record_error;
    logic [MIC_CNT - 1:0][SAMPLE_WIDTH - 1:0] record_data;
    logic record_ready;
    logic record_valid;

    logic pack_done;
    logic [SAMPLE_WIDTH - 1:0] pack_data;
    logic pack_ready;
    logic pack_valid;

    localparam int KeyDebounceCntW = $clog2(KEY_DEBOUNCE_CYCLES + 1);

    logic key_n_meta;
    logic key_n_sync;
    logic key_n_sync_d;
    logic key_n_db;
    logic key_n_db_d;
    logic [KeyDebounceCntW - 1:0] key_db_cnt;

    logic sdram_rd_ready;
    logic sdram_rd_valid;
    logic [SAMPLE_WIDTH - 1:0] sdram_rd_data;
    logic uart_busy;
    logic recording;

    // key debounce
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            key_n_meta <= 1'b1;
            key_n_sync <= 1'b1;
        end else begin
            key_n_meta <= key_n_i;
            key_n_sync <= key_n_meta;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            key_n_sync_d <= 1'b1;
            key_n_db <= 1'b1;
            key_n_db_d <= 1'b1;
            key_db_cnt <= '0;
        end else begin
            key_n_sync_d <= key_n_sync;
            key_n_db_d   <= key_n_db;

            if (key_n_sync != key_n_sync_d) begin
                key_db_cnt <= '0;
            end else if (key_n_sync != key_n_db) begin
                if (key_db_cnt == KEY_DEBOUNCE_CYCLES - 1) begin
                    key_n_db   <= key_n_sync;
                    key_db_cnt <= '0;
                end else begin
                    key_db_cnt <= key_db_cnt + 1'b1;
                end
            end else begin
                key_db_cnt <= '0;
            end
        end
    end

    assign record_start_raw = key_n_db_d && !key_n_db;  // one-cycle pulse on debounced button press
    assign record_start_is_allowed = !uart_busy;
    assign record_start = record_start_raw && record_start_is_allowed;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            recording <= 1'b0;
        end else begin
            if (record_start) begin
                recording <= 1'b1;
            end
            if (pack_valid) begin
                recording <= 1'b0;
            end
        end
    end

    MicFrontend #(
        .MIC_CNT(MIC_CNT),
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .CLK_HZ(CLK_HZ),
        .BCLK_HZ(BCLK_HZ)
    ) u_mic_frontend (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .sd_i(i2s_sd_i),
        .bclk_o(i2s_bclk_o),
        .ws_o(i2s_ws_o),
        .frame_change_o(frame_change),
        .frame_data_o(frame_data),
        .frame_error_o(frame_error),
        .frame_ready_i(frame_ready),
        .frame_valid_o(frame_valid)
    );

    RecordControl #(
        .WINDOW_LENGTH(WINDOW_LENGTH),
        .MIC_CNT(MIC_CNT),
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) u_record_control (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .frame_change_i(frame_change),
        .record_start_i(record_start),
        .frame_data_i(frame_data),
        .record_done_o(record_done),
        .record_error_o(record_error),
        .record_data_o(record_data),
        .frame_ready_o(frame_ready),
        .frame_valid_i(frame_valid),
        .frame_error_i(frame_error),
        .record_ready_i(record_ready),
        .record_valid_o(record_valid)
    );

    RecordPacker #(
        .MIC_CNT(MIC_CNT),
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .WORD_WIDTH(SAMPLE_WIDTH)
    ) u_record_packer (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .record_done_i(record_done),
        .record_data_i(record_data),
        .pack_done_o(pack_done),
        .pack_data_o(pack_data),
        .record_ready_o(record_ready),
        .record_valid_i(record_valid),
        .record_error_i(record_error),
        .pack_ready_i(pack_ready),
        .pack_valid_o(pack_valid)
    );

    Sdram #(
        .MIC_CNT(MIC_CNT),
        .WINDOW_LENGTH(WINDOW_LENGTH),
        .DATA_WIDTH(SAMPLE_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(SDRAM_ADDR_W),
        .RC_WIDTH(SDRAM_RC_W),
        .BANK_WIDTH(SDRAM_BANK_W)
    ) u_sdram (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .pack_done_i(pack_done),
        .wr_data_i(pack_data),
        .wr_valid_i(pack_valid),
        .wr_ready_o(pack_ready),
        .rd_ready_i(sdram_rd_ready),
        .rd_valid_o(sdram_rd_valid),
        .rd_data_o(sdram_rd_data),
        .sdram_clk_o(sdram_clk),
        .sdram_cke_o(sdram_cke),
        .sdram_cs_n_o(sdram_cs_n),
        .sdram_ras_n_o(sdram_ras_n),
        .sdram_cas_n_o(sdram_cas_n),
        .sdram_we_n_o(sdram_we_n),
        .sdram_ba_o(sdram_ba),
        .sdram_addr_o(sdram_addr),
        .sdram_dqm_o(sdram_dqm),
        .sdram_data_io(sdram_data)
    );

    UartSender #(
        .CLK_HZ(CLK_HZ),
        .BAUD_HZ(UART_BAUD_HZ),
        .DATA_WIDTH(SAMPLE_WIDTH),
        .MIC_CNT(MIC_CNT),
        .WINDOW_LENGTH(WINDOW_LENGTH)
    ) u_uart_sender (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .uart_busy_o(uart_busy),
        .uart_window_done_o(),
        .payload_valid_i(sdram_rd_valid),
        .payload_ready_o(sdram_rd_ready),
        .payload_data_i(sdram_rd_data),
        .uart_tx_o(uart_tx_o)
    );

    assign led_n_o[0] = ~recording;
    assign led_n_o[1] = ~pack_valid;
    assign led_n_o[2] = ~uart_busy;

endmodule
