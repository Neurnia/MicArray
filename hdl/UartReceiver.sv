// UartReceiver.sv
// Receive one UART ASCII command and convert it into a record-start pulse.
// The command is "START\n". The receiver will be idle until it receives the full command.

module UartReceiver #(
    parameter int CLK_HZ  = 50_000_000,
    parameter int BAUD_HZ = 921_600
) (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic uart_rx_i,
    input  logic uart_busy_i,
    output logic start_record_o
);

    localparam int ClksPerBit = (CLK_HZ + (BAUD_HZ / 2)) / BAUD_HZ;
    localparam int HalfBitClks = (ClksPerBit > 1) ? (ClksPerBit / 2) : 1;
    localparam int ClkCntW = $clog2(ClksPerBit + 1);

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;

    typedef enum logic [2:0] {
        MATCH_IDLE,
        MATCH_S,
        MATCH_ST,
        MATCH_STA,
        MATCH_STAR,
        MATCH_START
    } match_state_t;

    logic [2:0] uart_rx_sync;

    rx_state_t rx_state;
    rx_state_t rx_next_state;
    match_state_t match_state;
    match_state_t match_next_state;

    logic [ClkCntW - 1:0] baud_cnt;
    logic [2:0] bit_idx;
    logic [7:0] rx_shift;
    logic [7:0] rx_byte;
    logic rx_byte_valid;
    logic start_edge;
    logic baud_done;

    assign start_edge = uart_rx_sync[2] && !uart_rx_sync[0];
    assign baud_done  = (baud_cnt == '0);

    // 3-flop synchronizer
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            uart_rx_sync <= 3'b111;
        end else begin
            uart_rx_sync <= {uart_rx_sync[1:0], uart_rx_i};
        end
    end

    // RX state switch
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rx_state <= RX_IDLE;
        end else if (uart_busy_i) begin
            rx_state <= RX_IDLE;
        end else begin
            rx_state <= rx_next_state;
        end
    end

    // RX next-state logic
    always_comb begin
        rx_next_state = rx_state;
        case (rx_state)
            RX_IDLE: begin
                if (start_edge) begin
                    rx_next_state = RX_START;
                end
            end

            RX_START: begin
                if (baud_done) begin
                    if (!uart_rx_sync) begin
                        rx_next_state = RX_DATA;
                    end else begin
                        rx_next_state = RX_IDLE;
                    end
                end
            end

            RX_DATA: begin
                if (baud_done && bit_idx == 3'd7) begin
                    rx_next_state = RX_STOP;
                end
            end

            RX_STOP: begin
                if (baud_done) begin
                    rx_next_state = RX_IDLE;
                end
            end

            default: rx_next_state = RX_IDLE;
        endcase
    end

    // RX datapath
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            baud_cnt      <= '0;
            bit_idx       <= '0;
            rx_shift      <= '0;
            rx_byte       <= '0;
            rx_byte_valid <= 1'b0;
        end else begin
            rx_byte_valid <= 1'b0;

            if (uart_busy_i) begin
                baud_cnt <= '0;
                bit_idx  <= '0;
            end else begin
                case (rx_state)
                    RX_IDLE: begin
                        if (start_edge) begin
                            baud_cnt <= HalfBitClks - 1;
                        end
                    end

                    RX_START: begin
                        if (!baud_done) begin
                            baud_cnt <= baud_cnt - 1'b1;
                        end else if (!uart_rx_sync) begin
                            baud_cnt <= ClksPerBit - 1;
                            bit_idx  <= '0;
                        end
                    end

                    RX_DATA: begin
                        if (!baud_done) begin
                            baud_cnt <= baud_cnt - 1'b1;
                        end else begin
                            rx_shift[bit_idx] <= uart_rx_sync;
                            baud_cnt <= ClksPerBit - 1;

                            if (bit_idx != 3'd7) begin
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end
                    end

                    RX_STOP: begin
                        if (!baud_done) begin
                            baud_cnt <= baud_cnt - 1'b1;
                        end else begin
                            if (uart_rx_sync) begin
                                rx_byte <= rx_shift;
                                rx_byte_valid <= 1'b1;
                            end
                        end
                    end

                    default: rx_state <= RX_IDLE;
                endcase
            end
        end
    end

    // MATCH state switch
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            match_state <= MATCH_IDLE;
        end else if (uart_busy_i) begin
            match_state <= MATCH_IDLE;
        end else begin
            match_state <= match_next_state;
        end
    end

    // MATCH next-state logic
    always_comb begin
        match_next_state = match_state;

        if (rx_byte_valid) begin
            case (match_state)
                MATCH_IDLE: begin
                    if (rx_byte == "S") begin
                        match_next_state = MATCH_S;
                    end else begin
                        match_next_state = MATCH_IDLE;
                    end
                end

                MATCH_S: begin
                    if (rx_byte == "T") begin
                        match_next_state = MATCH_ST;
                    end else if (rx_byte == "S") begin
                        match_next_state = MATCH_S;
                    end else begin
                        match_next_state = MATCH_IDLE;
                    end
                end

                MATCH_ST: begin
                    if (rx_byte == "A") begin
                        match_next_state = MATCH_STA;
                    end else if (rx_byte == "S") begin
                        match_next_state = MATCH_S;
                    end else begin
                        match_next_state = MATCH_IDLE;
                    end
                end

                MATCH_STA: begin
                    if (rx_byte == "R") begin
                        match_next_state = MATCH_STAR;
                    end else if (rx_byte == "S") begin
                        match_next_state = MATCH_S;
                    end else begin
                        match_next_state = MATCH_IDLE;
                    end
                end

                MATCH_STAR: begin
                    if (rx_byte == "T") begin
                        match_next_state = MATCH_START;
                    end else if (rx_byte == "S") begin
                        match_next_state = MATCH_S;
                    end else begin
                        match_next_state = MATCH_IDLE;
                    end
                end

                MATCH_START: begin
                    if (rx_byte == "S") begin
                        match_next_state = MATCH_S;
                    end else begin
                        match_next_state = MATCH_IDLE;
                    end
                end

                default: match_next_state = MATCH_IDLE;
            endcase
        end
    end

    // MATCH output logic
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            start_record_o <= 1'b0;
        end else begin
            start_record_o <= 1'b0;

            if (!uart_busy_i &&
                rx_byte_valid &&
                match_state == MATCH_START &&
                rx_byte == "\n") begin
                start_record_o <= 1'b1;
            end
        end
    end

endmodule
