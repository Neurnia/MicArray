// tb_SdramControl.sv
// Self-checking write/read-path test bench for SdramControl.sv

`timescale 1ns / 1ps

module tb_SdramControl;

    localparam int DataWidth = 16;
    localparam int BurstLength = 8;
    localparam int AddrWidth = 24;
    localparam int RcWidth = 13;
    localparam int BankWidth = 2;
    localparam int DqmWidth = DataWidth / 8;
    localparam int LenWidth = $clog2(BurstLength + 1);
    localparam int ColWidth = AddrWidth - RcWidth - BankWidth;
    localparam int ClkFreqHz = 100_000_000;
    localparam int InitWaitCycles = (ClkFreqHz / 1_000_000) * 200;
    localparam int TrcdCycles = 2;
    localparam int TrpCycles = 2;
    localparam int TrcCycles = 6;
    localparam int TrscCycles = 2;
    localparam int TdalCycles = 4;
    localparam int ReadReturnCycles = 4;
    localparam logic [RcWidth - 1:0] ModeRegValue = {
        3'b000,
        1'b0,
        2'b00,
        3'b011,
        1'b0,
        3'b011
    };

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

    logic cmd_ready;
    logic cmd_valid;
    logic cmd_we_n;
    logic [AddrWidth - 1:0] cmd_addr;
    logic [LenWidth - 1:0] cmd_len;

    logic wr_ready;
    logic wr_valid;
    logic [DataWidth - 1:0] wr_data;

    logic rd_beat;
    logic [DataWidth - 1:0] rd_data;

    logic sdram_cke;
    logic sdram_cs_n;
    logic sdram_ras_n;
    logic sdram_cas_n;
    logic sdram_we_n;
    logic [BankWidth - 1:0] sdram_ba;
    logic [RcWidth - 1:0] sdram_addr;
    logic [DqmWidth - 1:0] sdram_dqm;
    tri [DataWidth - 1:0] sdram_dq;
    logic sdram_drive_en;
    logic [DataWidth - 1:0] sdram_drive_data;

    logic [DataWidth - 1:0] wr_data_q[$];
    int cycle_count;

    logic [DataWidth - 1:0] full_words[0:BurstLength-1];
    logic [DataWidth - 1:0] tail_words[0:BurstLength-1];
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

    SdramControl #(
        .DATA_WIDTH(DataWidth),
        .BURST_LENGTH(BurstLength),
        .ADDR_WIDTH(AddrWidth),
        .RC_WIDTH(RcWidth),
        .BANK_WIDTH(BankWidth)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cmd_ready_o(cmd_ready),
        .cmd_valid_i(cmd_valid),
        .cmd_we_n_i(cmd_we_n),
        .cmd_addr_i(cmd_addr),
        .cmd_len_i(cmd_len),
        .wr_ready_o(wr_ready),
        .wr_valid_i(wr_valid),
        .wr_data_i(wr_data),
        .rd_beat_o(rd_beat),
        .rd_data_o(rd_data),
        .sdram_cke_o(sdram_cke),
        .sdram_cs_n_o(sdram_cs_n),
        .sdram_ras_n_o(sdram_ras_n),
        .sdram_cas_n_o(sdram_cas_n),
        .sdram_we_n_o(sdram_we_n),
        .sdram_ba_o(sdram_ba),
        .sdram_addr_o(sdram_addr),
        .sdram_dqm_o(sdram_dqm),
        .sdram_dq_io(sdram_dq)
    );

    assign sdram_dq = sdram_drive_en ? sdram_drive_data : 'z;

    function automatic cmd_t decode_command;
        if (sdram_cs_n !== 1'b0) begin
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

    function automatic bit is_all_z(input logic [DataWidth - 1:0] value);
        return value === {DataWidth{1'bz}};
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

    always_comb begin
        wr_valid = (wr_data_q.size() != 0);
        wr_data = wr_valid ? wr_data_q[0] : '0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_data_q <= {};
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (wr_ready && wr_valid) begin
                void'(wr_data_q.pop_front());
            end
        end
    end

    task automatic queue_word(input logic [DataWidth - 1:0] word);
        begin
            @(negedge clk);
            wr_data_q.push_back(word);
        end
    endtask

    task automatic start_read_command(input logic [AddrWidth - 1:0] addr,
                                      input logic [LenWidth - 1:0] len);
        begin
            @(negedge clk);
            cmd_addr <= addr;
            cmd_len <= len;
            cmd_we_n <= 1'b1;
            cmd_valid <= 1'b1;
            while (cmd_ready !== 1'b1) begin
                @(negedge clk);
            end
            @(posedge clk);
            #1;
            @(negedge clk);
            cmd_valid <= 1'b0;
        end
    endtask

    task automatic start_write_command(input logic [AddrWidth - 1:0] addr,
                                       input logic [LenWidth - 1:0] len);
        begin
            @(negedge clk);
            cmd_addr <= addr;
            cmd_len <= len;
            cmd_we_n <= 1'b0;
            cmd_valid <= 1'b1;
            while (cmd_ready !== 1'b1) begin
                @(negedge clk);
            end
            @(posedge clk);
            #1;
            @(negedge clk);
            cmd_valid <= 1'b0;
        end
    endtask

    task automatic wait_for_expected_command(input cmd_t expected_cmd,
                                             input int max_cycles,
                                             output int seen_cycle);
        int i;
        cmd_t sampled_cmd;
        begin
            seen_cycle = -1;
            for (i = 0; i < max_cycles; i++) begin
                @(posedge clk);
                #1;
                sampled_cmd = decode_command();
                if (sampled_cmd == expected_cmd) begin
                    seen_cycle = cycle_count;
                    return;
                end
                if (sampled_cmd != CmdNop) begin
                    $fatal(1, "Unexpected SDRAM command before expected command. got=%0d expected=%0d cycle=%0d",
                           sampled_cmd, expected_cmd, cycle_count);
                end
            end
            $fatal(1, "Timed out waiting for SDRAM command %0d.", expected_cmd);
        end
    endtask

    task automatic check_initialization;
        int nop_cycles;
        int precharge_cycle;
        int refresh_cycle;
        int last_refresh_cycle;
        int refresh_count;
        int mrs_cycle;
        begin
            nop_cycles = 0;
            precharge_cycle = -1;
            while (precharge_cycle < 0) begin
                @(posedge clk);
                #1;
                if (sdram_cke !== 1'b1) begin
                    $fatal(1, "CKE must stay high during initial power-up pause. cycle=%0d", cycle_count);
                end
                if (decode_command() == CmdPrecharge) begin
                    precharge_cycle = cycle_count;
                    if (sdram_addr[10] !== 1'b1) begin
                        $fatal(1, "Initial precharge must target all banks.");
                    end
                end else begin
                    if (decode_command() != CmdNop) begin
                        $fatal(1, "Unexpected SDRAM command during initial 200us pause. cycle=%0d",
                               cycle_count);
                    end
                    if (sdram_dqm !== {DqmWidth{1'b1}}) begin
                        $fatal(1, "DQM must stay high during initial power-up pause. cycle=%0d",
                               cycle_count);
                    end
                    nop_cycles++;
                    if (nop_cycles > InitWaitCycles + 8) begin
                        $fatal(1, "Initial pause exceeded expected bound before precharge.");
                    end
                end
            end

            if (nop_cycles < InitWaitCycles) begin
                $fatal(1, "Initial pause too short. expected at least %0d cycles got %0d",
                       InitWaitCycles, nop_cycles);
            end

            last_refresh_cycle = precharge_cycle;
            refresh_count = 0;
            while (refresh_count < 8) begin
                wait_for_expected_command(CmdRefresh, TrcCycles + 4, refresh_cycle);
                if ((refresh_count == 0) && ((refresh_cycle - precharge_cycle) < TrpCycles)) begin
                    $fatal(1, "First refresh violated tRP after precharge. delta=%0d",
                           refresh_cycle - precharge_cycle);
                end
                if ((refresh_count != 0) && ((refresh_cycle - last_refresh_cycle) < TrcCycles)) begin
                    $fatal(1, "Refresh spacing violated tRC. delta=%0d", refresh_cycle - last_refresh_cycle);
                end
                last_refresh_cycle = refresh_cycle;
                refresh_count++;
            end

            wait_for_expected_command(CmdMrs, TrcCycles + 4, mrs_cycle);
            if ((mrs_cycle - last_refresh_cycle) < TrcCycles) begin
                $fatal(1, "MRS violated tRC after the last refresh. delta=%0d",
                       mrs_cycle - last_refresh_cycle);
            end
            if (sdram_addr !== ModeRegValue) begin
                $fatal(1, "Unexpected mode register value. expected=%h got=%h",
                       ModeRegValue, sdram_addr);
            end

            repeat (TrscCycles) begin
                @(posedge clk);
                #1;
                if (decode_command() != CmdNop) begin
                    $fatal(1, "Unexpected command before tRSC elapsed after MRS.");
                end
            end

            while (cmd_ready !== 1'b1) begin
                @(posedge clk);
                #1;
                if (decode_command() != CmdNop) begin
                    $fatal(1, "Unexpected command while waiting for controller idle-ready.");
                end
            end
        end
    endtask

    task automatic check_write_burst(input logic [AddrWidth - 1:0] expected_addr,
                                     input logic [LenWidth - 1:0] logical_len,
                                     input logic [DataWidth - 1:0] expected_words[0:BurstLength-1],
                                     input int min_act_gap,
                                     output int last_beat_cycle);
        int act_cycle;
        int write_cycle;
        int beat_idx;
        logic [BankWidth - 1:0] expected_bank;
        logic [RcWidth - 1:0] expected_row;
        logic [ColWidth - 1:0] expected_col;
        begin
            expected_bank = expected_addr[AddrWidth - 1 -: BankWidth];
            expected_row = expected_addr[ColWidth + RcWidth - 1 -: RcWidth];
            expected_col = expected_addr[ColWidth - 1:0];

            #1;
            if (decode_command() == CmdActivate) begin
                act_cycle = cycle_count;
            end else begin
                wait_for_expected_command(CmdActivate, TdalCycles + 6, act_cycle);
            end
            if (min_act_gap >= 0) begin
                if (act_cycle < min_act_gap) begin
                    $fatal(1, "ACTIVATE arrived too early after the previous write. cycle=%0d min=%0d",
                           act_cycle, min_act_gap);
                end
            end
            if (sdram_ba !== expected_bank) begin
                $fatal(1, "ACTIVATE bank mismatch. expected=%0d got=%0d", expected_bank, sdram_ba);
            end
            if (sdram_addr !== expected_row) begin
                $fatal(1, "ACTIVATE row mismatch. expected=%0h got=%0h", expected_row, sdram_addr);
            end

            wait_for_expected_command(CmdWrite, TrcdCycles + 4, write_cycle);
            if ((write_cycle - act_cycle) < TrcdCycles) begin
                $fatal(1, "WRITE violated tRCD after ACTIVATE. delta=%0d", write_cycle - act_cycle);
            end
            if (sdram_ba !== expected_bank) begin
                $fatal(1, "WRITE bank mismatch. expected=%0d got=%0d", expected_bank, sdram_ba);
            end
            if (sdram_addr[10] !== 1'b1) begin
                $fatal(1, "WRITE command must enable auto-precharge.");
            end
            if (sdram_addr[8:0] !== expected_col[8:0]) begin
                $fatal(1, "WRITE column mismatch. expected=%0h got=%0h",
                       expected_col[8:0], sdram_addr[8:0]);
            end

            for (beat_idx = 0; beat_idx < BurstLength; beat_idx++) begin
                if (beat_idx > 0) begin
                    @(posedge clk);
                    #1;
                    if (decode_command() != CmdNop) begin
                        $fatal(1, "Unexpected command during write burst beat %0d. cycle=%0d",
                               beat_idx, cycle_count);
                    end
                end

                if (beat_idx < logical_len) begin
                    if (wr_ready !== 1'b1) begin
                        $fatal(1, "wr_ready must stay high for valid payload beats. beat=%0d", beat_idx);
                    end
                    if (sdram_dqm !== '0) begin
                        $fatal(1, "DQM must stay low for valid payload beats. beat=%0d got=%b",
                               beat_idx, sdram_dqm);
                    end
                    if (sdram_dq !== expected_words[beat_idx]) begin
                        $fatal(1, "Write data mismatch. beat=%0d expected=%h got=%h",
                               beat_idx, expected_words[beat_idx], sdram_dq);
                    end
                end else begin
                    if (wr_ready !== 1'b0) begin
                        $fatal(1, "wr_ready must drop for masked tail beats. beat=%0d", beat_idx);
                    end
                    if (sdram_dqm !== {DqmWidth{1'b1}}) begin
                        $fatal(1, "DQM must mask tail beats. beat=%0d got=%b",
                               beat_idx, sdram_dqm);
                    end
                    if (!is_all_z(sdram_dq)) begin
                        $fatal(1, "DQ bus should be high-Z on masked tail beats. beat=%0d got=%h",
                               beat_idx, sdram_dq);
                    end
                end
            end

            last_beat_cycle = cycle_count;
        end
    endtask

    task automatic check_read_burst(input logic [AddrWidth - 1:0] expected_addr,
                                    input logic [LenWidth - 1:0] logical_len,
                                    input logic [DataWidth - 1:0] expected_words[0:BurstLength-1],
                                    input int min_act_gap,
                                    output int last_beat_cycle);
        int act_cycle;
        int read_cycle;
        int beat_count;
        logic [BankWidth - 1:0] expected_bank;
        logic [RcWidth - 1:0] expected_row;
        logic [ColWidth - 1:0] expected_col;
        begin
            expected_bank = expected_addr[AddrWidth - 1 -: BankWidth];
            expected_row = expected_addr[ColWidth + RcWidth - 1 -: RcWidth];
            expected_col = expected_addr[ColWidth - 1:0];

            #1;
            if (decode_command() == CmdActivate) begin
                act_cycle = cycle_count;
            end else begin
                wait_for_expected_command(CmdActivate, TrcCycles + 6, act_cycle);
            end
            if (min_act_gap >= 0) begin
                if (act_cycle < min_act_gap) begin
                    $fatal(1, "ACTIVATE arrived too early before read burst. cycle=%0d min=%0d",
                           act_cycle, min_act_gap);
                end
            end
            if (sdram_ba !== expected_bank) begin
                $fatal(1, "READ ACTIVATE bank mismatch. expected=%0d got=%0d", expected_bank, sdram_ba);
            end
            if (sdram_addr !== expected_row) begin
                $fatal(1, "READ ACTIVATE row mismatch. expected=%0h got=%0h", expected_row, sdram_addr);
            end

            wait_for_expected_command(CmdRead, TrcdCycles + 4, read_cycle);
            if ((read_cycle - act_cycle) < TrcdCycles) begin
                $fatal(1, "READ violated tRCD after ACTIVATE. delta=%0d", read_cycle - act_cycle);
            end
            if (sdram_ba !== expected_bank) begin
                $fatal(1, "READ bank mismatch. expected=%0d got=%0d", expected_bank, sdram_ba);
            end
            if (sdram_addr[10] !== 1'b1) begin
                $fatal(1, "READ command must enable auto-precharge.");
            end
            if (sdram_addr[8:0] !== expected_col[8:0]) begin
                $fatal(1, "READ column mismatch. expected=%0h got=%0h",
                       expected_col[8:0], sdram_addr[8:0]);
            end

            beat_count = 0;
            while (beat_count < logical_len) begin
                @(posedge clk);
                #1;
                if (rd_beat === 1'b1) begin
                    if (rd_data !== expected_words[beat_count]) begin
                        $fatal(1, "Read data mismatch. beat=%0d expected=%h got=%h",
                               beat_count, expected_words[beat_count], rd_data);
                    end
                    beat_count++;
                end
            end
            last_beat_cycle = cycle_count;

            repeat (2) begin
                @(posedge clk);
                #1;
                if (rd_beat === 1'b1) begin
                    $fatal(1, "rd_beat should stay low after logical read length completes.");
                end
            end
        end
    endtask

    task automatic check_memory_contents(input logic [AddrWidth - 1:0] base_addr,
                                         input int logical_len,
                                         input logic [DataWidth - 1:0] expected_words[0:BurstLength-1]);
        int unsigned mem_addr;
        begin
            for (int i = 0; i < logical_len; i++) begin
                mem_addr = int'(base_addr) + i;
                if (read_mem_word(mem_addr) !== expected_words[i]) begin
                    $fatal(1, "Stored SDRAM word mismatch at address %0d. expected=%h got=%h",
                           mem_addr, expected_words[i], read_mem_word(mem_addr));
                end
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
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
                if (sdram_dqm == '0) begin
                    sdram_mem[write_base_addr + write_beat_idx] = sdram_dq;
                end
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
                    if (sdram_dqm == '0) begin
                        sdram_mem[cmd_base_addr] = sdram_dq;
                    end
                    write_base_addr <= cmd_base_addr;
                    write_burst_active <= 1'b1;
                    write_beat_idx <= 1;
                end
                CmdRead: begin
                    read_pending <= 1'b1;
                    read_burst_active <= 1'b0;
                    read_base_addr <= calc_mem_addr(sdram_ba, active_row[sdram_ba], sdram_addr[8:0]);
                    read_beat_idx <= '0;
                    read_latency_count <= ReadReturnCycles;
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

    always @(negedge clk or negedge rst_n) begin
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
        logic [AddrWidth - 1:0] full_addr;
        logic [AddrWidth - 1:0] tail_addr;
        logic [AddrWidth - 1:0] read_addr;
        logic [AddrWidth - 1:0] read_tail_addr;
        int last_beat_cycle;
        int min_second_act_cycle;
        int last_read_cycle;
        int min_read_act_cycle;

        clk = 1'b0;
        rst_n = 1'b0;
        cmd_valid = 1'b0;
        cmd_we_n = 1'b1;
        cmd_addr = '0;
        cmd_len = '0;
        full_addr = {2'b10, 13'h123, 9'h040};
        tail_addr = {2'b01, 13'h045, 9'h080};
        read_addr = full_addr;
        read_tail_addr = tail_addr;

        full_words[0] = 16'h1100;
        full_words[1] = 16'h2201;
        full_words[2] = 16'h3302;
        full_words[3] = 16'h4403;
        full_words[4] = 16'h5504;
        full_words[5] = 16'h6605;
        full_words[6] = 16'h7706;
        full_words[7] = 16'h8807;

        tail_words[0] = 16'hA100;
        tail_words[1] = 16'hB201;
        tail_words[2] = 16'hC302;
        tail_words[3] = 16'hD403;
        tail_words[4] = 16'hE504;
        tail_words[5] = 16'h0000;
        tail_words[6] = 16'h0000;
        tail_words[7] = 16'h0000;

        #40;
        rst_n = 1'b1;

        check_initialization();

        queue_word(full_words[0]);
        queue_word(full_words[1]);
        queue_word(full_words[2]);
        queue_word(full_words[3]);
        queue_word(full_words[4]);
        queue_word(full_words[5]);
        queue_word(full_words[6]);
        queue_word(full_words[7]);
        start_write_command(full_addr, LenWidth'(BurstLength));
        check_write_burst(full_addr, LenWidth'(BurstLength), full_words, -1, last_beat_cycle);
        check_memory_contents(full_addr, BurstLength, full_words);

        queue_word(tail_words[0]);
        queue_word(tail_words[1]);
        queue_word(tail_words[2]);
        queue_word(tail_words[3]);
        queue_word(tail_words[4]);
        start_write_command(tail_addr, LenWidth'(5));
        min_second_act_cycle = last_beat_cycle + TdalCycles;
        check_write_burst(tail_addr, LenWidth'(5), tail_words, min_second_act_cycle, last_beat_cycle);
        check_memory_contents(tail_addr, 5, tail_words);

        start_read_command(read_addr, LenWidth'(BurstLength));
        min_read_act_cycle = last_beat_cycle + TdalCycles;
        check_read_burst(read_addr, LenWidth'(BurstLength), full_words, min_read_act_cycle, last_read_cycle);

        start_read_command(read_tail_addr, LenWidth'(5));
        min_read_act_cycle = last_read_cycle + TrpCycles;
        check_read_burst(read_tail_addr, LenWidth'(5), tail_words, min_read_act_cycle, last_read_cycle);

        repeat (6) begin
            @(posedge clk);
            #1;
            if (decode_command() != CmdNop) begin
                $fatal(1, "Unexpected command after the final write transaction. cycle=%0d",
                       cycle_count);
            end
        end

        if (wr_data_q.size() != 0) begin
            $fatal(1, "Write-data queue should be empty after the two test writes. size=%0d",
                   wr_data_q.size());
        end

        $display("tb_SdramControl passed.");
        $stop;
    end

    always #5 clk = ~clk;

endmodule


