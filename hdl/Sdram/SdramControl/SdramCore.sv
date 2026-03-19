// SdramCore.sv
// Handle state machine, timing counters, refresh arbitration, and transaction progress.
// All parameters are based on Winbond W9825G6KH-6 SDRAM chip.

module SdramCore #(
    parameter int DATA_WIDTH   = 16,
    parameter int ADDR_WIDTH   = 24,
    parameter int BURST_LENGTH = 8,
    parameter int RC_WIDTH     = 13,          // row and column
    parameter int BANK_WIDTH   = 2,
    parameter int CLK_FREQ_HZ  = 100_000_000
) (
    // basic
    input logic clk_i,
    input logic rst_n_i,

    // upstream cmd
    output logic cmd_ready_o,
    input logic cmd_valid_i,
    input logic cmd_we_n_i,  // active low: 0 for write and 1 for read
    input logic [ADDR_WIDTH - 1:0] cmd_addr_i,
    input logic [$clog2(BURST_LENGTH + 1) - 1:0] cmd_len_i,

    // SdramData control
    output logic wr_phase_o,
    output logic wr_beat_o,  // write beat request for logical payload beats only
    output logic rd_phase_o,
    output logic rd_beat_o,  // read beat request for logical payload beats only
    input logic rd_beat_fire_i,
    input logic wr_beat_fire_i,

    // SDRAM pins
    output logic sdram_cke_o,
    output logic sdram_cs_n_o,
    output logic sdram_ras_n_o,
    output logic sdram_cas_n_o,
    output logic sdram_we_n_o,
    output logic [BANK_WIDTH - 1:0] sdram_ba_o,
    output logic [RC_WIDTH - 1:0] sdram_addr_o,
    output logic [(DATA_WIDTH / 8) - 1:0] sdram_dqm_o
);

    /*
    State Map:
    RESET
    -> INIT_WAIT_200US
    -> INIT_PRECHARGE_ALL
    -> WAIT(tRP)
    -> INIT_AUTO_REFRESH x8
    -> WAIT(tRC) after each
    -> INIT_MRS
    -> WAIT(tRSC)
    -> IDLE

    IDLE
    -> if refresh_due                   REFRESH -> WAIT(tRC) -> IDLE
    -> if cmd_fire && cmd_we_n=0        ACTIVATE -> WAIT(tRCD)
                                      -> WRITE_CMD_DATA
                                      -> WRITE_RECOVERY -> IDLE
    -> if cmd_fire && cmd_we_n=1        ACTIVATE -> WAIT(tRCD) -> READ_CMD
                                      -> READ_LATENCY(CL)
                                      -> READ_DATA
                                      -> READ_RECOVERY -> IDLE

    Assumption:
    Once a write command is accepted and the core enters WRITE_CMD_DATA,
    the upstream write-data source must provide all logical payload beats
    for that command on consecutive cycles where wr_beat_o is asserted.
    This is guaranteed by the FIFO module.

    TODO:
    If this burst-continuity assumption is ever relaxed, add explicit
    underrun detection or a staging buffer because SDRAM write bursts
    cannot pause once the WRITE command is issued.
    */

    localparam int LenWidth = $clog2(BURST_LENGTH + 1);
    localparam int BurstBeatWidth = (BURST_LENGTH > 1) ? $clog2(BURST_LENGTH) : 1;
    localparam int ColWidth = ADDR_WIDTH - RC_WIDTH - BANK_WIDTH;
    localparam int DqmWidth = DATA_WIDTH / 8;
    localparam int CasLatency = 3;  // aka RL, read latency
    localparam int InitRefreshes = 8;  // according to SDRAM spec

    // cycle calculation
    localparam int ClkPeriodNs = 1_000_000_000 / CLK_FREQ_HZ;
    localparam int InitWaitCycles = (CLK_FREQ_HZ / 1_000_000) * 200;
    localparam int RefreshCycles = ((CLK_FREQ_HZ / 1_000) * 64) / 8192;  // 64ms / 8192 at <= 70C
    localparam int TrcdCycles = (18 + ClkPeriodNs - 1) / ClkPeriodNs;
    localparam int TrpCycles = (18 + ClkPeriodNs - 1) / ClkPeriodNs;
    localparam int TrcCycles = (60 + ClkPeriodNs - 1) / ClkPeriodNs;
    localparam int TrasCycles = (42 + ClkPeriodNs - 1) / ClkPeriodNs;  // currently not enforced explicitly
    localparam int TwrCycles = 2;
    localparam int TrscCycles = 2;
    localparam int TdalCycles = TwrCycles + TrpCycles;

    // width for registers (counters)
    localparam int WaitCountWidth = $clog2(InitWaitCycles + 1);
    localparam int RefreshCountW = $clog2(RefreshCycles + 1);
    localparam int LatencyCountW = (CasLatency > 1) ? $clog2(CasLatency) : 1;

    // mode register value for init settings
    localparam logic [RC_WIDTH - 1:0] ModeRegValue = {
        3'b000,  // A12:A10 reserved
        1'b0,  // A9 burst-write mode
        2'b00,  // A8:A7 reserved
        3'b011,  // A6:A4 CAS latency = 3
        1'b0,  // A3 sequential
        3'b011  // A2:A0 burst length = 8
    };

    function automatic logic [WaitCountWidth - 1:0] CmdWaitCount(input int cycles);
        // used when the state has already consumed 1 cycle for the command
        if (cycles <= 1) begin
            return '0;
        end
        return cycles - 2;
    endfunction

    function automatic logic [WaitCountWidth - 1:0] PlainWaitCount(input int cycles);
        // used when the state is purely waiting and has not consumed any cycles yet
        if (cycles <= 1) begin
            return '0;
        end
        return cycles - 1;
    endfunction

    // states
    typedef enum logic [3:0] {
        RESET,

        INIT_WAIT_200US,
        INIT_PRECHARGE_ALL,
        INIT_AUTO_REFRESH,
        INIT_MRS,

        IDLE,
        ACTIVATE,
        WRITE_CMD_DATA,
        WRITE_RECOVERY,  // special wait state
        READ_CMD,
        READ_LATENCY,
        READ_DATA,
        READ_RECOVERY,   // special wait state
        REFRESH,

        WAIT  // general wait state
    } state_t;
    state_t state, next_state;
    state_t wait_return_state;

    // counters
    logic [WaitCountWidth - 1:0] wait_counter;
    logic [RefreshCountW - 1:0] refresh_counter;
    logic [LatencyCountW - 1:0] read_latency_counter;
    logic [3:0] init_refresh_counter;  // 8 times

    // cmd latch
    logic [ADDR_WIDTH - 1:0] cmd_addr_reg;
    logic [LenWidth - 1:0] cmd_len_reg;
    logic cmd_we_n_reg;

    logic init_done_flag;  // level signal
    logic [BurstBeatWidth - 1:0] burst_beat;
    logic cmd_fire;
    logic refresh_due;

    logic [BANK_WIDTH - 1:0] bank_addr;
    logic [RC_WIDTH - 1:0] row_addr;
    logic [ColWidth - 1:0] col_addr;
    logic init_powerup_wait_active;

    assign cmd_fire    = cmd_valid_i && cmd_ready_o;
    assign refresh_due = init_done_flag && (refresh_counter == '0);

    assign bank_addr = cmd_addr_reg[ADDR_WIDTH - 1 -: BANK_WIDTH];
    assign row_addr  = cmd_addr_reg[ColWidth + RC_WIDTH - 1 -: RC_WIDTH];
    assign col_addr  = cmd_addr_reg[ColWidth - 1:0];
    assign init_powerup_wait_active = (state == INIT_WAIT_200US) ||
                                      ((state == WAIT) && (wait_return_state == INIT_PRECHARGE_ALL));

    // Command channel is only accepted when the single-transaction core is idle and refresh is not pending.
    assign cmd_ready_o = (state == IDLE) && !refresh_due;

    // Phase-level controls for SdramData.
    assign wr_phase_o = (state == WRITE_CMD_DATA);
    assign wr_beat_o  = (state == WRITE_CMD_DATA) && (burst_beat < cmd_len_reg);
    assign rd_phase_o = (state == READ_DATA);
    assign rd_beat_o  = (state == READ_DATA) && (burst_beat < cmd_len_reg);

    // state switch
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state <= RESET;
        end else begin
            state <= next_state;
        end
    end

    // next state
    always_comb begin
        next_state = state;
        case (state)
            RESET: begin
                next_state = INIT_WAIT_200US;
            end

            INIT_WAIT_200US: begin
                next_state = WAIT;
            end
            INIT_PRECHARGE_ALL: begin
                next_state = WAIT;
            end
            INIT_AUTO_REFRESH: begin
                next_state = WAIT;
            end
            INIT_MRS: begin
                next_state = WAIT;
            end
            IDLE: begin
                if (refresh_due) begin
                    next_state = REFRESH;
                end else if (cmd_fire) begin
                    next_state = ACTIVATE;
                end
            end
            ACTIVATE: begin
                next_state = WAIT;
            end
            WRITE_CMD_DATA: begin
                if (burst_beat == BURST_LENGTH - 1) begin
                    next_state = WRITE_RECOVERY;
                end
            end
            WRITE_RECOVERY: begin
                if (wait_counter == '0) begin
                    next_state = IDLE;
                end
            end
            READ_CMD: begin
                next_state = READ_LATENCY;
            end
            READ_LATENCY: begin
                if (read_latency_counter == '0) begin
                    next_state = READ_DATA;
                end
            end
            READ_DATA: begin
                if (burst_beat == BURST_LENGTH - 1) begin
                    next_state = READ_RECOVERY;
                end
            end
            READ_RECOVERY: begin
                if (wait_counter == '0) begin
                    next_state = IDLE;
                end
            end
            REFRESH: begin
                next_state = WAIT;
            end
            WAIT: begin
                if (wait_counter == '0) begin
                    // designed for flexible wait states
                    next_state = wait_return_state;
                end
            end
            default: begin
                next_state = RESET;
            end
        endcase
    end

    // sequential state payload and timing tracking
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wait_return_state    <= INIT_PRECHARGE_ALL;
            wait_counter         <= '0;
            refresh_counter      <= '0;
            read_latency_counter <= '0;
            init_refresh_counter <= '0;
            cmd_addr_reg         <= '0;
            cmd_len_reg          <= '0;
            cmd_we_n_reg         <= 1'b1;
            init_done_flag       <= 1'b0;
            burst_beat           <= '0;
        end else begin
            // Refresh timer only runs after initialization and saturates when refresh becomes due.
            if (state == REFRESH) begin
                refresh_counter <= RefreshCycles - 1;
            end else if (init_done_flag && (refresh_counter != '0)) begin
                refresh_counter <= refresh_counter - 1'b1;
            end

            case (state)
                RESET: begin
                    wait_counter         <= '0;
                    read_latency_counter <= '0;
                    init_refresh_counter <= '0;
                    cmd_addr_reg         <= '0;
                    cmd_len_reg          <= '0;
                    cmd_we_n_reg         <= 1'b1;
                    init_done_flag       <= 1'b0;
                    burst_beat           <= '0;
                    refresh_counter      <= '0;
                end

                INIT_WAIT_200US: begin
                    wait_counter         <= PlainWaitCount(InitWaitCycles);
                    wait_return_state    <= INIT_PRECHARGE_ALL;
                    init_refresh_counter <= '0;
                end
                INIT_PRECHARGE_ALL: begin
                    wait_counter         <= CmdWaitCount(TrpCycles);
                    wait_return_state    <= INIT_AUTO_REFRESH;
                    init_refresh_counter <= '0;
                end
                INIT_AUTO_REFRESH: begin
                    wait_counter <= CmdWaitCount(TrcCycles);
                    wait_return_state  <= (init_refresh_counter == InitRefreshes - 1) ? INIT_MRS : INIT_AUTO_REFRESH;
                    init_refresh_counter <= init_refresh_counter + 1'b1;
                end
                INIT_MRS: begin
                    wait_counter      <= CmdWaitCount(TrscCycles);
                    wait_return_state <= IDLE;
                    init_done_flag    <= 1'b1;
                    refresh_counter   <= RefreshCycles - 1;
                end

                IDLE: begin
                    if (cmd_fire) begin
                        cmd_addr_reg <= cmd_addr_i;
                        cmd_len_reg  <= cmd_len_i;
                        cmd_we_n_reg <= cmd_we_n_i;
                        burst_beat   <= '0;
                    end
                end
                ACTIVATE: begin
                    wait_counter      <= CmdWaitCount(TrcdCycles);
                    wait_return_state <= (cmd_we_n_reg == 1'b0) ? WRITE_CMD_DATA : READ_CMD;
                    burst_beat        <= '0;
                end
                WRITE_CMD_DATA: begin
                    if (burst_beat == BURST_LENGTH - 1) begin
                        wait_counter <= CmdWaitCount(TdalCycles);
                    end else begin
                        burst_beat <= burst_beat + 1'b1;
                    end
                end
                WRITE_RECOVERY: begin
                    if (wait_counter != '0) begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                READ_CMD: begin
                    read_latency_counter <= CasLatency - 2;
                    burst_beat           <= '0;
                end
                READ_LATENCY: begin
                    if (read_latency_counter != '0) begin
                        read_latency_counter <= read_latency_counter - 1'b1;
                    end
                end
                READ_DATA: begin
                    if (burst_beat == BURST_LENGTH - 1) begin
                        wait_counter <= CmdWaitCount(TrpCycles);
                    end else begin
                        burst_beat <= burst_beat + 1'b1;
                    end
                end
                READ_RECOVERY: begin
                    if (wait_counter != '0) begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                REFRESH: begin
                    wait_counter      <= CmdWaitCount(TrcCycles);
                    wait_return_state <= IDLE;
                end
                WAIT: begin
                    if (wait_counter != '0) begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                default: begin
                end
            endcase
        end
    end

    // command and SDRAM output generation
    always_comb begin
        sdram_cke_o   = 1'b1;
        sdram_cs_n_o  = 1'b0;
        sdram_ras_n_o = 1'b1;
        sdram_cas_n_o = 1'b1;
        sdram_we_n_o  = 1'b1;
        sdram_ba_o    = '0;
        sdram_addr_o  = '0;
        sdram_dqm_o   = '0;

        case (state)
            RESET: begin
                sdram_dqm_o = {DqmWidth{1'b1}};
            end

            INIT_WAIT_200US: begin
                sdram_dqm_o = {DqmWidth{1'b1}};
            end
            INIT_PRECHARGE_ALL: begin
                sdram_ras_n_o    = 1'b0;
                sdram_cas_n_o    = 1'b1;
                sdram_we_n_o     = 1'b0;
                sdram_addr_o[10] = 1'b1;  // precharge all banks
            end
            INIT_AUTO_REFRESH: begin
                sdram_ras_n_o = 1'b0;
                sdram_cas_n_o = 1'b0;
                sdram_we_n_o  = 1'b1;
            end
            INIT_MRS: begin
                sdram_ras_n_o = 1'b0;
                sdram_cas_n_o = 1'b0;
                sdram_we_n_o  = 1'b0;
                sdram_addr_o  = ModeRegValue;
            end

            IDLE: begin
            end
            ACTIVATE: begin
                sdram_ras_n_o = 1'b0;
                sdram_cas_n_o = 1'b1;
                sdram_we_n_o  = 1'b1;
                sdram_ba_o    = bank_addr;
                sdram_addr_o  = row_addr;
            end
            WRITE_CMD_DATA: begin
                if (burst_beat == '0) begin
                    sdram_ras_n_o = 1'b1;
                    sdram_cas_n_o = 1'b0;
                    sdram_we_n_o  = 1'b0;
                    sdram_ba_o    = bank_addr;
                    if (RC_WIDTH > 11) begin
                        sdram_addr_o[RC_WIDTH-1:11] = '0;
                    end
                    sdram_addr_o[10]  = 1'b1;  // auto-precharge
                    sdram_addr_o[8:0] = col_addr;
                end
                if (burst_beat >= cmd_len_reg) begin
                    sdram_dqm_o = {DqmWidth{1'b1}};
                end
            end
            WRITE_RECOVERY: begin
            end
            READ_CMD: begin
                sdram_ras_n_o = 1'b1;
                sdram_cas_n_o = 1'b0;
                sdram_we_n_o  = 1'b1;
                sdram_ba_o    = bank_addr;
                if (RC_WIDTH > 11) begin
                    sdram_addr_o[RC_WIDTH-1:11] = '0;
                end
                sdram_addr_o[10]  = 1'b1;  // auto-precharge
                sdram_addr_o[8:0] = col_addr;
            end
            READ_LATENCY: begin
            end
            READ_DATA: begin
            end
            READ_RECOVERY: begin
            end
            REFRESH: begin
                sdram_ras_n_o = 1'b0;
                sdram_cas_n_o = 1'b0;
                sdram_we_n_o  = 1'b1;
            end
            WAIT: begin
                if (init_powerup_wait_active) begin
                    sdram_dqm_o = {DqmWidth{1'b1}};
                end
            end
            default: begin
            end
        endcase
    end

endmodule
