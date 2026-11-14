module uart_rx #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115200
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,

    output logic       busy,
    output logic       data_valid,
    output logic [7:0] data_out,
    output logic       framing_error
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // REGISTERS
    logic [$clog2(CLKS_PER_BIT)-1:0] baud_counter;
    logic [2:0] bit_index;
    logic [7:0] data_reg;
    // TWO-FLIP-FLOP SYNCHRONIZER
    logic rx_meta;
    logic rx_sync;

    // STATE
    typedef enum logic [1:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    }state_t;

    state_t state;
    state_t next_state;

    // UPDATE STATE
    always_ff@(posedge clk) begin
        if (rst)
            state <= IDLE;
        else    
            state <= next_state;
    end

    // SYNCHRONIZERS
    always_ff@(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end
        else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    // CAPTURE DATA
    always_ff@(posedge clk) begin
        if (rst)
            data_reg <= 8'h00;
        else if (state == DATA_BITS && baud_counter == (CLKS_PER_BIT - 1))  
            data_reg[bit_index] <= rx_sync;
    end

    // MOVE THE DATA WHEN COMPLETE
    always_ff@(posedge clk) begin
        if (rst)
            data_out <= 8'h00;
        else if (state == STOP_BIT && baud_counter == (CLKS_PER_BIT - 1))
            data_out <= data_reg;
    end

    // BAUD COUNTER
    always_ff@(posedge clk) begin
        if (rst)
            baud_counter <= 0;
        else if (state == IDLE)
            baud_counter <= 0;
        else if (state == START_BIT && baud_counter == (CLKS_PER_BIT/2 - 1))
            baud_counter <= 0;
        else if (baud_counter == (CLKS_PER_BIT - 1) && (state == DATA_BITS || state == STOP_BIT))
            baud_counter <= 0;
        else
            baud_counter <= baud_counter + 1;
    end

    // BIT_INDEX
    always_ff@(posedge clk) begin
        if (rst)
            bit_index <= 0;
        else if (state == DATA_BITS && bit_index == 7 && baud_counter == (CLKS_PER_BIT - 1))
            bit_index <= 0;
        else if (state == DATA_BITS && baud_counter == (CLKS_PER_BIT - 1))
            bit_index <= bit_index + 1;
    end

    // DATA VALID
    always_ff@(posedge clk) begin
        if (rst)
            data_valid <= 0;
        else if (state == STOP_BIT && baud_counter == (CLKS_PER_BIT - 1))
            data_valid <= 1;
        else
            data_valid <= 0;
    end

    // FRAMMING ERROR
    always_ff@(posedge clk) begin
        if (rst)
            framing_error <= 0;
        else if (state == STOP_BIT && baud_counter == (CLKS_PER_BIT - 1) && rx_sync == 0)
            framing_error <= 1;
        else
            framing_error <= 0;
    end

    // COMBINATIONAL LOGIC  
    always_comb begin
        busy = (state != IDLE);
        next_state = state;

        case (state)
            IDLE: begin
                // busy = 0;

                if (rx_sync == 0)
                    next_state = START_BIT;
            end
            START_BIT: begin
                // busy = 1;

                if (rx_sync == 0 && baud_counter == (CLKS_PER_BIT/2 - 1))
                    next_state = DATA_BITS;
                else if (rx_sync == 1 && baud_counter == (CLKS_PER_BIT/2 - 1))
                    next_state = IDLE;
            end
            DATA_BITS: begin
                // busy = 1;

                if (bit_index == 7 && baud_counter == (CLKS_PER_BIT - 1))
                    next_state = STOP_BIT;
            end
            STOP_BIT: begin
                // busy = 1;

                if (baud_counter == (CLKS_PER_BIT - 1))
                    next_state = IDLE;      
            end

            default: begin
                next_state = IDLE;
                busy = 0;
            end
        endcase
    end

endmodule