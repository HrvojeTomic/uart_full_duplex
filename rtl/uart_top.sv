module uart_top (
    // Shared signals
    input logic        clk,
    input logic        rst,

    // TX signals
    input logic [7:0]  data_in,
    input logic        write_en,
    output logic       tx,
    output logic       tx_full,

    // RX signals
    input logic        rx,
    input logic        read_en,
    output logic [7:0] data_out,
    output logic       framing_error,
    output logic       rx_busy,
    output logic       rx_full,
    output logic       rx_empty,
    output logic       overrun_error
);

// INTERNAL SIGNAL
logic [8:0] rx_fifo_data;

// SEPARATION OF data_out
assign data_out =      rx_fifo_data[7:0];
assign framing_error = rx_fifo_data[8];

// INSTANTIATION
uart_fifo_tx_top tx_unit (
    .clk(clk),
    .rst(rst),
    .data_in(data_in),
    .write_en(write_en),
    .full(tx_full),
    .tx(tx)
);

uart_rx_fifo_top rx_unit (
    .clk(clk),
    .rst(rst),
    .rx(rx),
    .read_en(read_en),
    .data_out(rx_fifo_data),
    .busy(rx_busy),
    .empty(rx_empty),
    .full(rx_full),
    .overrun_error(overrun_error)
);

endmodule

