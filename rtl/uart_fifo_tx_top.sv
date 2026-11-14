module uart_fifo_tx_top (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] data_in,
    input  logic       write_en,
    output logic       tx,
    output logic       full
);
    // INTERNAL SIGNALS
    logic [7:0] fifo_data_out;
    logic fifo_empty;
    logic fifo_read_en;
    logic uart_busy;
    logic uart_start;

    // INSTANTIATE
    uart_tx uart_inst (
        .clk(clk),
        .rst(rst),
        .tx(tx),
        .start(uart_start),
        .busy(uart_busy),
        .data_in(fifo_data_out)
    );

    fifo fifo_inst (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .write_en(write_en),
        .full(full),
        .empty(fifo_empty),
        .data_out(fifo_data_out),
        .read_en(fifo_read_en)
    );

    // STATES
    typedef enum logic [1:0] {
        IDLE,
        READ_FIFO,
        START_UART,
        WAIT_UART
    }state_t;

    state_t state;
    state_t next_state;

    // Update state
    always_ff@(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        fifo_read_en = 0;
        uart_start = 0;

        case (state)
            IDLE: begin
                if (!uart_busy && !fifo_empty)
                    next_state = READ_FIFO;
            end

            READ_FIFO: begin
                fifo_read_en = 1;
                next_state = START_UART;
            end

            START_UART: begin
                uart_start = 1;
                next_state = WAIT_UART;
            end

            WAIT_UART: begin
                if (!uart_busy)
                    next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
endmodule