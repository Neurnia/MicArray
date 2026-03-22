// tb_SdramRdCtrl.sv
// Self-checking test bench for SdramRdCtrl.sv

`timescale 1ns / 1ps

module tb_SdramRdCtrl;

    localparam int MicCnt = 2;
    localparam int WindowLength = 3;
    localparam int DataWidth = 16;
    localparam int FifoDepth = 16;
    localparam int BurstLength = 4;
    localparam int AddrWidth = 12;
    localparam int FifoLevelWidth = $clog2(FifoDepth);
    localparam int CmdLenWidth = $clog2(BurstLength + 1);
    localparam int PayloadWords = WindowLength * (MicCnt + 1);

    logic                      clk;
    logic                      rst_n;
    logic                      wrrd_clear;
    logic                      active;
    logic                      is_done;

    logic                      cmd_ready;
    logic                      cmd_valid;
    logic [     AddrWidth-1:0] cmd_addr;
    logic [   CmdLenWidth-1:0] cmd_len;

    logic                      rd_beat;
    logic [     DataWidth-1:0] rd_data;

    logic                      fifo_ready;
    logic                      fifo_valid;
    logic [     DataWidth-1:0] fifo_data;
    logic [FifoLevelWidth-1:0] fifo_level;

    int                        fifo_count;
    logic [     DataWidth-1:0] fifo_q[$];

    SdramRdCtrl #(
        .MIC_CNT      (MicCnt),
        .DATA_WIDTH   (DataWidth),
        .FIFO_DEPTH   (FifoDepth),
        .BURST_LENGTH (BurstLength),
        .ADDR_WIDTH   (AddrWidth),
        .WINDOW_LENGTH(WindowLength)
    ) u_dut (
        .clk_i        (clk),
        .rst_n_i      (rst_n),
        .wrrd_clear_i (wrrd_clear),
        .active_i     (active),
        .is_done_o    (is_done),
        .cmd_ready_i  (cmd_ready),
        .cmd_valid_o  (cmd_valid),
        .cmd_addr_o   (cmd_addr),
        .cmd_len_o    (cmd_len),
        .rd_beat_i    (rd_beat),
        .rd_data_i    (rd_data),
        .fifo_ready_i (fifo_ready),
        .fifo_valid_o (fifo_valid),
        .fifo_data_o  (fifo_data),
        .fifo_level_i (fifo_level)
    );

    always_comb begin
        fifo_level = FifoLevelWidth'(fifo_count);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_count <= 0;
            fifo_q = {};
        end else if (fifo_valid && fifo_ready) begin
            fifo_count <= fifo_count + 1;
            fifo_q.push_back(fifo_data);
        end
    end

    task automatic expect_no_command(input int cycles);
        int i;
        begin
            for (i = 0; i < cycles; i++) begin
                @(posedge clk);
                #1;
                if (cmd_valid !== 1'b0) begin
                    $fatal(1, "Unexpected cmd_valid while no command should be pending. cycle=%0d",
                           i);
                end
            end
        end
    endtask

    task automatic stall_command_until_stable(input logic [AddrWidth-1:0] expected_addr,
                                              input logic [CmdLenWidth-1:0] expected_len,
                                              input int stall_cycles);
        int i;
        logic [AddrWidth-1:0] hold_addr;
        logic [CmdLenWidth-1:0] hold_len;
        begin
            i = 0;
            while (cmd_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                i++;
                if (i > 100) begin
                    $fatal(1, "Timed out waiting for cmd_valid.");
                end
            end

            if (cmd_addr !== expected_addr) begin
                $fatal(1, "cmd_addr mismatch. expected=%0d got=%0d", expected_addr, cmd_addr);
            end
            if (cmd_len !== expected_len) begin
                $fatal(1, "cmd_len mismatch. expected=%0d got=%0d", expected_len, cmd_len);
            end

            hold_addr = cmd_addr;
            hold_len = cmd_len;

            cmd_ready <= 1'b0;
            repeat (stall_cycles) begin
                @(posedge clk);
                #1;
                if (cmd_valid !== 1'b1) begin
                    $fatal(1, "cmd_valid dropped during command backpressure.");
                end
                if (cmd_addr !== hold_addr) begin
                    $fatal(1, "cmd_addr changed during command backpressure. expected=%0d got=%0d",
                           hold_addr, cmd_addr);
                end
                if (cmd_len !== hold_len) begin
                    $fatal(1, "cmd_len changed during command backpressure. expected=%0d got=%0d",
                           hold_len, cmd_len);
                end
            end

            @(negedge clk);
            cmd_ready <= 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            cmd_ready <= 1'b0;
        end
    endtask

    task automatic expect_read_word(input logic [DataWidth-1:0] expected_word,
                                    input int stall_cycles);
        int i;
        begin
            @(negedge clk);
            rd_data <= expected_word;
            rd_beat <= 1'b1;

            i = 0;
            while (fifo_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                i++;
                if (i > 20) begin
                    $fatal(1, "Timed out waiting for fifo_valid.");
                end
            end

            if (fifo_data !== expected_word) begin
                $fatal(1, "fifo_data mismatch before fifo handshake. expected=%h got=%h",
                       expected_word, fifo_data);
            end

            fifo_ready <= 1'b0;
            repeat (stall_cycles) begin
                @(posedge clk);
                #1;
                if (fifo_valid !== 1'b1) begin
                    $fatal(1, "fifo_valid dropped during fifo backpressure.");
                end
                if (fifo_data !== expected_word) begin
                    $fatal(1, "fifo_data changed during fifo backpressure. expected=%h got=%h",
                           expected_word, fifo_data);
                end
            end

            @(negedge clk);
            fifo_ready <= 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            fifo_ready <= 1'b0;
            rd_beat <= 1'b0;
            rd_data <= '0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        wrrd_clear = 1'b0;
        active = 1'b1;
        cmd_ready = 1'b0;
        rd_beat = 1'b0;
        rd_data = '0;
        fifo_ready = 1'b0;

        #40;
        rst_n = 1'b1;

        stall_command_until_stable(12'd0, 3'd4, 3);
        expect_read_word(16'h1111, 2);
        expect_read_word(16'h2222, 0);
        expect_read_word(16'h3333, 1);
        expect_read_word(16'h4444, 0);

        stall_command_until_stable(12'd4, 3'd4, 2);
        expect_read_word(16'h5555, 1);
        expect_read_word(16'h6666, 0);
        expect_read_word(16'h7777, 0);
        expect_read_word(16'h8888, 1);

        stall_command_until_stable(12'd8, 3'd1, 2);
        expect_read_word(16'h9999, 0);

        expect_no_command(6);

        if (fifo_q.size() != PayloadWords) begin
            $fatal(1, "FIFO model should contain %0d words. size=%0d",
                   PayloadWords, fifo_q.size());
        end
        if (fifo_q[0] !== 16'h1111 || fifo_q[4] !== 16'h5555 || fifo_q[8] !== 16'h9999) begin
            $fatal(1, "Captured FIFO words are not in the expected order.");
        end
        if (is_done !== 1'b1) begin
            $fatal(1, "is_done should stay high after the final read beat completes.");
        end

        @(negedge clk);
        wrrd_clear <= 1'b1;
        @(negedge clk);
        wrrd_clear <= 1'b0;
        @(posedge clk);
        #1;
        if (is_done !== 1'b0) begin
            $fatal(1, "is_done should clear after wrrd_clear.");
        end

        $display("tb_SdramRdCtrl passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
