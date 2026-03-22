// tb_Sdram.sv
// Self-checking integration test bench for Sdram.sv

`timescale 1ns / 1ps

module tb_Sdram;

    localparam int MicCnt = 2;
    localparam int WindowLength = 3;
    localparam int DataWidth = 16;
    localparam int FifoDepth = 512;
    localparam int BurstLength = 8;
    localparam int AddrWidth = 24;
    localparam int RcWidth = 13;
    localparam int BankWidth = 2;
    localparam int SampleWords = WindowLength * (MicCnt + 1);
    localparam int ColWidth = AddrWidth - RcWidth - BankWidth;
    localparam int CasLatency = 3;

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
    logic pack_done;

    logic wr_ready;
    logic wr_valid;
    logic [DataWidth - 1:0] wr_data;

    logic rd_ready;
    logic rd_valid;
    logic [DataWidth - 1:0] rd_data;

    logic sdram_clk;
    logic sdram_cke;
    logic sdram_cs_n;
    logic sdram_ras_n;
    logic sdram_cas_n;
    logic sdram_we_n;
    logic [BankWidth - 1:0] sdram_ba;
    logic [RcWidth - 1:0] sdram_addr;
    logic [(DataWidth / 8) - 1:0] sdram_dqm;
    tri [DataWidth - 1:0] sdram_dq;

    logic sdram_drive_en;
    logic [DataWidth - 1:0] sdram_drive_data;
    logic wr_fifo_valid_drv;
    logic [DataWidth - 1:0] wr_fifo_data_drv;
    logic [$clog2(FifoDepth) - 1:0] wr_fifo_level_drv;
    logic window_done_drv;

    logic [DataWidth - 1:0] expected_words[0:SampleWords - 1];
    logic [RcWidth - 1:0] active_row[0:(1 << BankWidth) - 1];
    logic write_burst_active;
    int unsigned write_base_addr;
    int unsigned write_beat_idx;
    logic read_pending;
    logic read_burst_active;
    int unsigned read_base_addr;
    int unsigned read_beat_idx;
    int unsigned read_latency_count;
    logic [DataWidth - 1:0] sdram_mem[int unsigned];

    Sdram #(
        .MIC_CNT(MicCnt),
        .WINDOW_LENGTH(WindowLength),
        .DATA_WIDTH(DataWidth),
        .FIFO_DEPTH(FifoDepth),
        .BURST_LENGTH(BurstLength),
        .ADDR_WIDTH(AddrWidth),
        .RC_WIDTH(RcWidth),
        .BANK_WIDTH(BankWidth)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .pack_done_i(pack_done),
        .wr_ready_o(wr_ready),
        .wr_valid_i(wr_valid),
        .wr_data_i(wr_data),
        .rd_ready_i(rd_ready),
        .rd_valid_o(rd_valid),
        .rd_data_o(rd_data),
        .sdram_clk_o(sdram_clk),
        .sdram_cke_o(sdram_cke),
        .sdram_cs_n_o(sdram_cs_n),
        .sdram_ras_n_o(sdram_ras_n),
        .sdram_cas_n_o(sdram_cas_n),
        .sdram_we_n_o(sdram_we_n),
        .sdram_ba_o(sdram_ba),
        .sdram_addr_o(sdram_addr),
        .sdram_dqm_o(sdram_dqm),
        .sdram_data_io(sdram_dq)
    );

    assign sdram_dq = sdram_drive_en ? sdram_drive_data : 'z;

    initial begin
        force u_dut.wr_fifo_valid = wr_fifo_valid_drv;
        force u_dut.wr_fifo_data = wr_fifo_data_drv;
        force u_dut.wr_fifo_level = wr_fifo_level_drv;
        force u_dut.window_done = window_done_drv;
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

    function automatic int unsigned calc_mem_addr(input logic [BankWidth - 1:0] bank,
                                                  input logic [RcWidth - 1:0] row,
                                                  input logic [ColWidth - 1:0] col);
        logic [AddrWidth - 1:0] addr_bits;
        begin
            addr_bits = {bank, row, col};
            return int'(addr_bits);
        end
    endfunction

    function automatic logic [DataWidth - 1:0] read_mem_word(input int unsigned addr);
        if (sdram_mem.exists(addr)) begin
            return sdram_mem[addr];
        end
        return '0;
    endfunction

    task automatic store_write_beat(input int unsigned addr, input int unsigned beat_idx_i);
        begin
            if (sdram_dqm == '0) begin
                sdram_mem[addr + beat_idx_i] = sdram_dq;
            end
        end
    endtask

    task automatic expect_read_word(input logic [DataWidth - 1:0] expected_word,
                                    input int stall_cycles);
        int cycles;
        begin
            cycles = 0;
            while (rd_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                cycles++;
                if (cycles > 50000) begin
                    $fatal(1, "Timed out waiting for rd_valid.");
                end
            end

            if (rd_data !== expected_word) begin
                $fatal(1, "Read data mismatch before handshake. expected=%h got=%h",
                       expected_word, rd_data);
            end

            repeat (stall_cycles) begin
                @(posedge clk);
                #1;
                if (rd_valid !== 1'b1) begin
                    $fatal(1, "rd_valid dropped during downstream backpressure.");
                end
                if (rd_data !== expected_word) begin
                    $fatal(1, "rd_data changed during downstream backpressure. expected=%h got=%h",
                           expected_word, rd_data);
                end
            end

            @(negedge clk);
            rd_ready <= 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            rd_ready <= 1'b0;
        end
    endtask

    always @(posedge sdram_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_fifo_valid_drv <= 1'b0;
            wr_fifo_data_drv <= '0;
            wr_fifo_level_drv <= '0;
            window_done_drv <= 1'b0;
        end else begin
            window_done_drv <= 1'b0;

            if (wr_fifo_level_drv == '0) begin
                wr_fifo_valid_drv <= 1'b0;
                wr_fifo_data_drv <= '0;
            end else begin
                wr_fifo_valid_drv <= 1'b1;
                wr_fifo_data_drv <= expected_words[SampleWords - wr_fifo_level_drv];

                if (u_dut.wr_fifo_ready) begin
                    wr_fifo_level_drv <= wr_fifo_level_drv - 1'b1;
                end
            end
        end
    end

    always @(posedge sdram_clk or negedge rst_n) begin
        cmd_t cmd;
        int unsigned cmd_base_addr;

        if (!rst_n) begin
            for (int bank = 0; bank < (1 << BankWidth); bank++) begin
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
                        for (int bank = 0; bank < (1 << BankWidth); bank++) begin
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
        pack_done = 1'b0;
        wr_valid = 1'b0;
        wr_data = '0;
        rd_ready = 1'b0;
        wr_fifo_valid_drv = 1'b0;
        wr_fifo_data_drv = '0;
        wr_fifo_level_drv = '0;
        window_done_drv = 1'b0;

        expected_words[0] = 16'h8000;
        expected_words[1] = 16'h1111;
        expected_words[2] = 16'h2222;
        expected_words[3] = 16'h0000;
        expected_words[4] = 16'h3333;
        expected_words[5] = 16'h4444;
        expected_words[6] = 16'hFFFF;
        expected_words[7] = 16'h1357;
        expected_words[8] = 16'h2468;

        #100;
        rst_n = 1'b1;

        wait (sdram_clk === 1'b1);
        @(posedge sdram_clk);
        wr_fifo_level_drv <= SampleWords;
        wr_fifo_valid_drv <= 1'b1;
        wr_fifo_data_drv <= expected_words[0];
        window_done_drv <= 1'b1;

        expect_read_word(expected_words[0], 2);
        expect_read_word(expected_words[1], 0);
        expect_read_word(expected_words[2], 1);
        expect_read_word(expected_words[3], 0);
        expect_read_word(expected_words[4], 0);
        expect_read_word(expected_words[5], 2);
        expect_read_word(expected_words[6], 0);
        expect_read_word(expected_words[7], 1);
        expect_read_word(expected_words[8], 0);

        for (int i = 0; i < SampleWords; i++) begin
            if (read_mem_word(i) !== expected_words[i]) begin
                $fatal(1, "SDRAM memory mismatch at word %0d. expected=%h got=%h",
                       i, expected_words[i], read_mem_word(i));
            end
        end

        repeat (20) @(posedge clk);
        #1;
        if (rd_valid !== 1'b0) begin
            $fatal(1, "Read FIFO should be empty after reading the whole window.");
        end

        $display("tb_Sdram passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
