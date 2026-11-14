module uart_rx_fifo_top (
    input logic        clk,
    input logic        rst,
    input logic        rx,
    input logic        read_en,

    output logic       busy,
    output logic [8:0] data_out,
    output logic       full,
    output logic       empty,
    output logic       overrun_error
);

    // INTERNAL SINGALS
    logic [7:0] uart_data_out;
    logic       uart_framing_error;
    logic       data_valid;
    logic       fifo_full;
    logic       fifo_write_en;

    assign fifo_write_en = data_valid && !fifo_full;
    assign full = fifo_full;

    // INSTANTIATE
    uart_rx uart_inst (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .busy(busy),
        .data_valid(data_valid),
        .data_out(uart_data_out),
        .framing_error(uart_framing_error)
    );

    fifo #(
        .DATA_WIDTH(9)
    ) fifo_inst (
        .clk(clk),
        .rst(rst),
        .read_en(read_en),
        .data_out(data_out),
        .empty(empty),
        .data_in({uart_framing_error, uart_data_out}),
        .full(fifo_full),
        .write_en(fifo_write_en)
    );

    // OVERRUN ERROR FLIP FLOP
    always_ff@(posedge clk) begin
        if (rst)
            overrun_error <= 1'b0;
        else
            overrun_error <= data_valid && fifo_full;
    end

endmodule