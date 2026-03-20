// tb_SdramWrFifo.sv
// Self-checking test bench for SdramWrFifo.sv

`timescale 1ns / 1ps

module tb_SdramWrFifo;

    localparam int FifoWidth = 16;
    localparam int FifoDepth = 512;

    logic                         wr_clk;
    logic                         rd_clk;
    logic                         rst_n;
    logic                         pack_done;
    logic [        FifoWidth-1:0] wr_data;

    logic                         window_done;
    logic [$clog2(FifoDepth)-1:0] rd_level;
    logic [        FifoWidth-1:0] rd_data;

    logic                         wr_ready;
    logic                         wr_valid;
    logic                         rd_ready;
    logic                         rd_valid;

    int                           window_done_count;

    SdramWrFifo #(
        .FIFO_WIDTH(FifoWidth),
        .FIFO_DEPTH(FifoDepth)
    ) u_dut (
        .wr_clk_i     (wr_clk),
        .rd_clk_i     (rd_clk),
        .rst_n_i      (rst_n),
        .pack_done_i  (pack_done),
        .wr_data_i    (wr_data),
        .window_done_o(window_done),
        .rd_level_o   (rd_level),
        .rd_data_o    (rd_data),
        .wr_ready_o   (wr_ready),
        .wr_valid_i   (wr_valid),
        .rd_ready_i   (rd_ready),
        .rd_valid_o   (rd_valid)
    );

    task automatic push_word(input logic [FifoWidth-1:0] word);
        begin
            @(negedge wr_clk);
            wr_data  <= word;
            wr_valid <= 1'b1;

            @(posedge wr_clk);
            #1;
            if (wr_ready !== 1'b1) begin
                $fatal(1, "Expected wr_ready during write handshake.");
            end

            @(negedge wr_clk);
            wr_valid <= 1'b0;
        end
    endtask

    task automatic pulse_pack_done;
        begin
            @(negedge wr_clk);
            pack_done <= 1'b1;
            @(negedge wr_clk);
            pack_done <= 1'b0;
        end
    endtask

    task automatic wait_level_at_least(input int expected_min);
        int cycles;
        begin
            cycles = 0;
            while (rd_level < expected_min) begin
                @(posedge rd_clk);
                #1;
                cycles++;
                if (cycles > 100) begin
                    $fatal(1, "Timed out waiting for rd_level >= %0d. got=%0d", expected_min,
                           rd_level);
                end
            end
        end
    endtask

    task automatic wait_window_done_event(input int previous_count);
        int cycles;
        begin
            cycles = 0;
            while (window_done_count == previous_count) begin
                @(posedge rd_clk);
                #1;
                cycles++;
                if (cycles > 100) begin
                    $fatal(1, "Timed out waiting for window_done event.");
                end
            end
            @(posedge rd_clk);
            #1;
            if (window_done !== 1'b0) begin
                $fatal(1, "window_done should be a one-cycle pulse in rd_clk domain.");
            end
        end
    endtask

    task automatic expect_word(input logic [FifoWidth-1:0] expected_word, input int stall_cycles);
        int i;
        begin
            i = 0;
            while (rd_valid !== 1'b1) begin
                @(posedge rd_clk);
                #1;
                i++;
                if (i > 100) begin
                    $fatal(1, "Timed out waiting for rd_valid.");
                end
            end

            if (rd_data !== expected_word) begin
                $fatal(1, "Show-ahead data mismatch before read. expected=%h got=%h",
                       expected_word, rd_data);
            end

            repeat (stall_cycles) begin
                @(posedge rd_clk);
                #1;
                if (rd_valid !== 1'b1) begin
                    $fatal(1, "rd_valid dropped during downstream backpressure.");
                end
                if (rd_data !== expected_word) begin
                    $fatal(1, "rd_data changed during downstream backpressure. expected=%h got=%h",
                           expected_word, rd_data);
                end
            end

            @(negedge rd_clk);
            rd_ready <= 1'b1;
            @(posedge rd_clk);
            #1;
            @(negedge rd_clk);
            rd_ready <= 1'b0;
        end
    endtask

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            window_done_count <= 0;
        end else if (window_done) begin
            window_done_count <= window_done_count + 1;
        end
    end

    initial begin
        wr_clk = 1'b0;
        rd_clk = 1'b0;
        rst_n = 1'b0;
        pack_done = 1'b0;
        wr_data = '0;
        wr_valid = 1'b0;
        rd_ready = 1'b0;

        #40;
        rst_n = 1'b1;

        @(posedge wr_clk);
        @(posedge rd_clk);
        #1;
        if (wr_ready !== 1'b1) begin
            $fatal(1, "SdramWrFifo should accept writes after reset.");
        end
        if (rd_valid !== 1'b0) begin
            $fatal(1, "SdramWrFifo should be empty after reset.");
        end
        if (rd_level !== '0) begin
            $fatal(1, "SdramWrFifo level should be zero after reset. got=%0d", rd_level);
        end

        push_word(16'h1111);
        push_word(16'h2222);
        push_word(16'h3333);
        pulse_pack_done();

        wait_level_at_least(3);

        if (rd_valid !== 1'b1) begin
            $fatal(1, "Expected rd_valid once FIFO receives data.");
        end
        if (rd_data !== 16'h1111) begin
            $fatal(1, "Show-ahead first word mismatch. expected=1111 got=%h", rd_data);
        end

        wait_window_done_event(0);

        expect_word(16'h1111, 2);
        expect_word(16'h2222, 0);
        expect_word(16'h3333, 1);

        repeat (20) @(posedge rd_clk);
        #1;
        if (rd_valid !== 1'b0) begin
            $fatal(1, "SdramWrFifo should be empty after reading all words.");
        end
        if (window_done_count !== 1) begin
            $fatal(1, "Expected exactly one window_done pulse. got=%0d", window_done_count);
        end

        $display("tb_SdramWrFifo passed.");
        $stop;
    end

    always #10 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

endmodule
