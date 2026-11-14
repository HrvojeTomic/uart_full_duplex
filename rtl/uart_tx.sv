module uart_tx #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       start,
    input  logic [7:0] data_in,

    output logic       tx,
    output logic       busy
);
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // Registers
    logic [$clog2(CLKS_PER_BIT)-1:0] baud_counter;
    logic [2:0] bit_index;
    logic [7:0] data_reg;

    // State
    typedef enum logic [1:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    }state_t;

    state_t state;
    state_t next_state;

    // State update
    always_ff@(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Capture data
    always_ff@(posedge clk) begin
        if (rst)
            data_reg <= 8'b0;
        else if (state == IDLE && start)
            data_reg <= data_in;
    end

    // baud_counter
    always_ff@(posedge clk) begin
        if (rst)
            baud_counter <= 0;
        else if (state == IDLE)
            baud_counter <= 0;
        else if (baud_counter == CLKS_PER_BIT - 1)
            baud_counter <= 0;
        else    
            baud_counter <= baud_counter + 1;
    end

    // bit_index
        always_ff@(posedge clk) begin
            if (rst)
                bit_index <= 0;
            else if (state == IDLE)
                bit_index <= 0;
            else if (state == DATA_BITS && baud_counter == CLKS_PER_BIT - 1 && bit_index < 7)
                bit_index <= bit_index + 1;
        end

    // Combinational Logic
    always_comb begin
        busy = (state != IDLE);
        tx = 1;
        next_state = state;

        case (state)
            IDLE: begin
                tx = 1;
                // busy = 0;

                if (start)
                    next_state = START_BIT;
            end

            START_BIT: begin
                tx = 0;
                // busy = 1;

                if (baud_counter == CLKS_PER_BIT - 1)
                    next_state = DATA_BITS;
            end

            DATA_BITS: begin
                tx = data_reg[bit_index];
                // busy = 1;

               if (baud_counter == CLKS_PER_BIT - 1 && bit_index == 7)
                    next_state = STOP_BIT;
            end

            STOP_BIT: begin
                tx = 1;
                // busy = 1;

                if (baud_counter == CLKS_PER_BIT - 1)
                    next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
                tx = 1'b1;
            end
        endcase
    end
        

endmodule