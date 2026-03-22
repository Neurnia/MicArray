// tb_MicArrayTopReadback.sv
// Top-level integration smoke test for the SDRAM readback and UART export path.
//
// Scope:
// - Keep MicArrayTop parameters at their real default values.
// - Inject a short packed-word stream at the packer boundary.
// - Use a datasheet-aligned SDRAM responder for BL=8, CL=3, sequential bursts.
// - Check the UART prefix and the first injected payload words.

`timescale 1ns / 1ps

module tb_MicArrayTopReadback;

    localparam int MicCnt = 2;
    localparam int SampleWidth = 16;
    localparam int SdramAddrW = 24;
    localparam int SdramRcW = 13;
    localparam int SdramBankW = 2;
    localparam int ClkHz = 50_000_000;
    localparam int UartBaudHz = 921_600;
    localparam int BaudCycles = ClkHz / UartBaudHz;
    localparam int BurstLength = 8;
    localparam int CasLatency = 3;
    localparam int ColWidth = SdramAddrW - SdramRcW - SdramBankW;
    localparam int InjectedWords = 6;

    typedef enum int {
        CmdNop,
        CmdActivate,
        CmdWrite,
        CmdRead,
        CmdPrecharge,
        CmdRefresh,
        CmdMrs,
        CmdUnknown
    } cmd_t;

    logic clk;
    logic rst_n;
    logic key_n;

    logic [MicCnt - 1:0] i2s_sd;
    logic i2s_bclk;
    logic i2s_ws;

    logic uart_rx;
    logic uart_tx;

    logic [2:0] led_n;

    logic sdram_clk;
    logic sdram_cke;
    logic sdram_cs_n;
    logic sdram_ras_n;
    logic sdram_cas_n;
    logic sdram_we_n;
    logic [SdramBankW - 1:0] sdram_ba;
    logic [SdramRcW - 1:0] sdram_addr;
    logic [(SampleWidth / 8) - 1:0] sdram_dqm;
    tri [SampleWidth - 1:0] sdram_data;

    logic sdram_drive_en;
    logic [SampleWidth - 1:0] sdram_drive_data;

    logic pack_valid_drv;
    logic [SampleWidth - 1:0] pack_data_drv;
    logic pack_done_drv;

    logic [SampleWidth - 1:0] expected_words[0:InjectedWords - 1];
    logic [7:0] expected_bytes[$];

    logic [SdramRcW - 1:0] active_row[0:(1 << SdramBankW) - 1];
    logic write_burst_active;
    int unsigned write_base_addr;
    int unsigned write_beat_idx;

    logic read_pending;
    logic read_burst_active;
    int unsigned read_base_addr;
    int unsigned read_beat_idx;
    int unsigned read_latency_count;

    logic [SampleWidth - 1:0] sdram_mem[int unsigned];

    MicArrayTop dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .key_n_i(key_n),
        .i2s_sd_i(i2s_sd),
        .i2s_bclk_o(i2s_bclk),
        .i2s_ws_o(i2s_ws),
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx),
        .led_n_o(led_n),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_ba(sdram_ba),
        .sdram_addr(sdram_addr),
        .sdram_dqm(sdram_dqm),
        .sdram_data(sdram_data)
    );

    assign sdram_data = sdram_drive_en ? sdram_drive_data : 'z;

    initial begin
        force dut.pack_valid = pack_valid_drv;
        force dut.pack_data = pack_data_drv;
        force dut.pack_done = pack_done_drv;
    end

    function automatic cmd_t decode_command;
        if (sdram_cke !== 1'b1 || sdram_cs_n !== 1'b0) begin
            return CmdUnknown;
        end
        case ({sdram_ras_n, sdram_cas_n, sdram_we_n})
            3'b111: return CmdNop;
            3'b011: return CmdActivate;
            3'b100: return CmdWrite;
            3'b101: return CmdRead;
            3'b010: return CmdPrecharge;
            3'b001: return CmdRefresh;
            3'b000: return CmdMrs;
            default: return CmdUnknown;
        endcase
    endfunction

    function automatic int unsigned calc_mem_addr(input logic [SdramBankW - 1:0] bank,
                                                  input logic [SdramRcW - 1:0] row,
                                                  input logic [ColWidth - 1:0] col);
        logic [SdramAddrW - 1:0] addr_bits;
        begin
            addr_bits = {bank, row, col};
            return int'(addr_bits);
        end
    endfunction

    function automatic logic [SampleWidth - 1:0] read_mem_word(input int unsigned addr);
        if (sdram_mem.exists(addr)) begin
            return sdram_mem[addr];
        end
        return '0;
    endfunction

    task automatic store_write_beat(input int unsigned addr, input int unsigned beat_idx_i);
        begin
            if (sdram_dqm == '0) begin
                sdram_mem[addr + beat_idx_i] = sdram_data;
            end
        end
    endtask

    task automatic drive_pack_word(input logic [SampleWidth - 1:0] word);
        begin
            @(negedge clk);
            pack_data_drv <= word;
            pack_valid_drv <= 1'b1;

            while (!(dut.pack_valid && dut.pack_ready)) begin
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            pack_valid_drv <= 1'b0;
            pack_data_drv <= '0;
        end
    endtask

    task automatic pulse_pack_done;
        begin
            @(negedge clk);
            pack_done_drv <= 1'b1;
            @(negedge clk);
            pack_done_drv <= 1'b0;
        end
    endtask

    task automatic build_expected_bytes;
        logic [7:0] frame_words_byte;
        begin
            frame_words_byte = MicCnt + 1;
            expected_bytes = {};
            expected_bytes.push_back(8'hA5);
            expected_bytes.push_back(8'h5A);
            expected_bytes.push_back(8'h00);
            expected_bytes.push_back(frame_words_byte);

            for (int i = 0; i < InjectedWords; i++) begin
                expected_bytes.push_back(expected_words[i][15:8]);
                expected_bytes.push_back(expected_words[i][7:0]);
            end
        end
    endtask

    task automatic expect_uart_byte(input logic [7:0] expected_byte);
        int bit_i;
        logic [7:0] captured_byte;
        int timeout;
        begin
            timeout = 0;
            while (uart_tx !== 1'b0) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 2_000_000) begin
                    $fatal(1, "Timed out waiting for UART start bit.");
                end
            end

            repeat (BaudCycles / 2) @(posedge clk);
            #1;
            if (uart_tx !== 1'b0) begin
                $fatal(1, "UART start bit is not held low at mid-bit sample.");
            end

            for (bit_i = 0; bit_i < 8; bit_i++) begin
                repeat (BaudCycles) @(posedge clk);
                #1;
                captured_byte[bit_i] = uart_tx;
            end

            repeat (BaudCycles) @(posedge clk);
            #1;
            if (uart_tx !== 1'b1) begin
                $fatal(1, "UART stop bit is not high.");
            end

            if (captured_byte !== expected_byte) begin
                $fatal(1, "UART byte mismatch. expected=%h got=%h", expected_byte, captured_byte);
            end
        end
    endtask

    task automatic expect_all_uart_bytes;
        logic [7:0] expected_byte;
        begin
            while (expected_bytes.size() != 0) begin
                expected_byte = expected_bytes.pop_front();
                expect_uart_byte(expected_byte);
            end
        end
    endtask

    always @(posedge sdram_clk or negedge rst_n) begin
        cmd_t cmd;
        int unsigned cmd_base_addr;

        if (!rst_n) begin
            for (int bank = 0; bank < (1 << SdramBankW); bank++) begin
                active_row[bank] <= '0;
            end
            write_burst_active <= 1'b0;
            write_base_addr <= '0;
            write_beat_idx <= '0;
            read_pending <= 1'b0;
            read_burst_active <= 1'b0;
            read_base_addr <= '0;
            read_beat_idx <= '0;
            read_latency_count <= '0;
        end else begin
            #1;
            cmd = decode_command();

            if (write_burst_active) begin
                store_write_beat(write_base_addr, write_beat_idx);
                if (write_beat_idx == BurstLength - 1) begin
                    write_burst_active <= 1'b0;
                    write_beat_idx <= '0;
                end else begin
                    write_beat_idx <= write_beat_idx + 1'b1;
                end
            end

            case (cmd)
                CmdActivate: begin
                    active_row[sdram_ba] <= sdram_addr;
                end
                CmdWrite: begin
                    cmd_base_addr = calc_mem_addr(sdram_ba, active_row[sdram_ba], sdram_addr[8:0]);
                    store_write_beat(cmd_base_addr, '0);
                    write_base_addr <= cmd_base_addr;
                    write_burst_active <= 1'b1;
                    write_beat_idx <= 1;
                end
                CmdRead: begin
                    read_pending <= 1'b1;
                    read_burst_active <= 1'b0;
                    read_base_addr <= calc_mem_addr(sdram_ba, active_row[sdram_ba], sdram_addr[8:0]);
                    read_beat_idx <= '0;
                    read_latency_count <= CasLatency;
                end
                CmdPrecharge: begin
                    if (sdram_addr[10]) begin
                        for (int bank = 0; bank < (1 << SdramBankW); bank++) begin
                            active_row[bank] <= '0;
                        end
                    end else begin
                        active_row[sdram_ba] <= '0;
                    end
                end
                default: begin
                end
            endcase
        end
    end

    always @(negedge sdram_clk or negedge rst_n) begin
        if (!rst_n) begin
            sdram_drive_en <= 1'b0;
            sdram_drive_data <= '0;
        end else if (read_burst_active) begin
            #1;
            sdram_drive_en <= 1'b1;
            sdram_drive_data <= read_mem_word(read_base_addr + read_beat_idx);

            if (read_beat_idx == BurstLength - 1) begin
                read_burst_active <= 1'b0;
                read_beat_idx <= '0;
            end else begin
                read_beat_idx <= read_beat_idx + 1'b1;
            end
        end else if (read_pending) begin
            #1;
            if (read_latency_count > 1) begin
                read_latency_count <= read_latency_count - 1'b1;
                sdram_drive_en <= 1'b0;
            end else begin
                read_pending <= 1'b0;
                read_burst_active <= 1'b1;
                read_latency_count <= '0;
                read_beat_idx <= 1;
                sdram_drive_en <= 1'b1;
                sdram_drive_data <= read_mem_word(read_base_addr);
            end
        end else begin
            #1;
            sdram_drive_en <= 1'b0;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        key_n = 1'b1;
        i2s_sd = '0;
        uart_rx = 1'b1;
        pack_valid_drv = 1'b0;
        pack_data_drv = '0;
        pack_done_drv = 1'b0;

        expected_words[0] = 16'h8000;
        expected_words[1] = 16'h1111;
        expected_words[2] = 16'h2222;
        expected_words[3] = 16'h0000;
        expected_words[4] = 16'h3333;
        expected_words[5] = 16'h4444;

        build_expected_bytes();

        #100;
        rst_n = 1'b1;

        for (int i = 0; i < InjectedWords; i++) begin
            drive_pack_word(expected_words[i]);
        end
        pulse_pack_done();

        wait (dut.u_sdram.wr_is_done === 1'b1);
        #1;
        for (int i = 0; i < InjectedWords; i++) begin
            if (read_mem_word(i) !== expected_words[i]) begin
                $fatal(1, "SDRAM memory mismatch at word %0d. expected=%h got=%h",
                       i, expected_words[i], read_mem_word(i));
            end
        end

        expect_all_uart_bytes();

        if (dut.u_uart_sender.uart_busy_o !== 1'b1) begin
            $fatal(1, "uart_busy_o should already be high while the prefix/payload is being sent.");
        end

        $display("tb_MicArrayTopReadback passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
