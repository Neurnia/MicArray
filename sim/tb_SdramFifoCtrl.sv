// tb_SdramFifoCtrl.sv
// Self-checking test bench for SdramFifoCtrl.sv

`timescale 1ns / 1ps

module tb_SdramFifoCtrl;

    localparam int DataWidth = 16;
    localparam int FifoDepth = 16;
    localparam int BurstLength = 4;
    localparam int AddrWidth = 12;
    localparam int FifoLevelWidth = $clog2(FifoDepth);
    localparam int CmdLenWidth = $clog2(BurstLength + 1);

    logic clk;
    logic rst_n;
    logic window_done;

    logic                  fifo_ready;
    logic                  fifo_valid;
    logic [DataWidth-1:0]  fifo_data;
    logic [FifoLevelWidth-1:0] fifo_level;

    logic                  cmd_ready;
    logic                  cmd_valid;
    logic                  cmd_we;
    logic [AddrWidth-1:0]  cmd_addr;
    logic [CmdLenWidth-1:0] cmd_len;

    logic                  wr_ready;
    logic                  wr_valid;
    logic [DataWidth-1:0]  wr_data;

    logic [DataWidth-1:0] fifo_q[$];

    SdramFifoCtrl #(
        .DATA_WIDTH  (DataWidth),
        .FIFO_DEPTH  (FifoDepth),
        .BURST_LENGTH(BurstLength),
        .ADDR_WIDTH  (AddrWidth)
    ) u_dut (
        .clk_i       (clk),
        .rst_n_i     (rst_n),
        .window_done_i(window_done),
        .fifo_ready_o(fifo_ready),
        .fifo_valid_i(fifo_valid),
        .fifo_data_i (fifo_data),
        .fifo_level_i(fifo_level),
        .cmd_ready_i (cmd_ready),
        .cmd_valid_o (cmd_valid),
        .cmd_we_o    (cmd_we),
        .cmd_addr_o  (cmd_addr),
        .cmd_len_o   (cmd_len),
        .wr_ready_i  (wr_ready),
        .wr_valid_o  (wr_valid),
        .wr_data_o   (wr_data)
    );

    always_comb begin
        fifo_valid = (fifo_q.size() != 0);
        fifo_data = fifo_valid ? fifo_q[0] : '0;
        fifo_level = FifoLevelWidth'(fifo_q.size());
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_q = {};
        end else if (fifo_ready && fifo_valid) begin
            void'(fifo_q.pop_front());
        end
    end

    task automatic enqueue_word(input logic [DataWidth-1:0] word);
        begin
            @(negedge clk);
            fifo_q.push_back(word);
        end
    endtask

    task automatic pulse_window_done;
        begin
            @(negedge clk);
            window_done <= 1'b1;
            @(negedge clk);
            window_done <= 1'b0;
        end
    endtask

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
        logic hold_we;
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
            if (cmd_we !== 1'b1) begin
                $fatal(1, "cmd_we should stay high for SdramFifoCtrl write commands.");
            end

            hold_addr = cmd_addr;
            hold_len = cmd_len;
            hold_we = cmd_we;

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
                if (cmd_we !== hold_we) begin
                    $fatal(1, "cmd_we changed during command backpressure.");
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

    task automatic expect_write_word(input logic [DataWidth-1:0] expected_word,
                                     input int stall_cycles);
        int i;
        begin
            i = 0;
            while (wr_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                i++;
                if (i > 100) begin
                    $fatal(1, "Timed out waiting for wr_valid.");
                end
            end

            if (wr_data !== expected_word) begin
                $fatal(1, "wr_data mismatch before write handshake. expected=%h got=%h",
                       expected_word, wr_data);
            end

            wr_ready <= 1'b0;
            repeat (stall_cycles) begin
                @(posedge clk);
                #1;
                if (wr_valid !== 1'b1) begin
                    $fatal(1, "wr_valid dropped during write backpressure.");
                end
                if (wr_data !== expected_word) begin
                    $fatal(1, "wr_data changed during write backpressure. expected=%h got=%h",
                           expected_word, wr_data);
                end
                if (fifo_ready !== 1'b0) begin
                    $fatal(1, "fifo_ready should stay low while write beat is stalled.");
                end
            end

            @(negedge clk);
            wr_ready <= 1'b1;
            @(posedge clk);
            #1;
            if (fifo_ready !== 1'b1) begin
                $fatal(1, "fifo_ready should pulse when a write beat is accepted.");
            end
            @(negedge clk);
            wr_ready <= 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        window_done = 1'b0;
        cmd_ready = 1'b0;
        wr_ready = 1'b0;

        #40;
        rst_n = 1'b1;

        expect_no_command(3);

        enqueue_word(16'h1111);
        enqueue_word(16'h2222);
        enqueue_word(16'h3333);
        expect_no_command(4);

        enqueue_word(16'h4444);
        stall_command_until_stable(12'd0, 3'd4, 3);
        expect_write_word(16'h1111, 2);
        expect_write_word(16'h2222, 0);
        expect_write_word(16'h3333, 1);
        expect_write_word(16'h4444, 0);

        expect_no_command(3);

        enqueue_word(16'hAAAA);
        enqueue_word(16'hBBBB);
        pulse_window_done();
        stall_command_until_stable(12'd4, 3'd2, 2);
        expect_write_word(16'hAAAA, 1);
        expect_write_word(16'hBBBB, 0);

        expect_no_command(6);
        if (fifo_q.size() != 0) begin
            $fatal(1, "FIFO model should be empty after all writes. size=%0d", fifo_q.size());
        end

        $display("tb_SdramFifoCtrl passed.");
        $stop;
    end

    always #10 clk = ~clk;

endmodule
