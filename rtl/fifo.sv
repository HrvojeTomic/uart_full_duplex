module fifo #(
    parameter int DATA_WIDTH = 8
)(
    input  logic                    clk,         // Clock
    input  logic                    rst,         // Reset
    input  logic [DATA_WIDTH - 1:0] data_in,     // Byte to store
    input  logic                    write_en,    // Request to store a byte
    input  logic                    read_en,     // Request to retrieve a byte
    output logic [DATA_WIDTH - 1:0] data_out,    // Next byte available
    output logic                    full,        // No more space in the buffer
    output logic                    empty        // Buffer empty
); 

logic [DATA_WIDTH - 1:0] fifo_mem [0:7];         // My buffer
logic              [2:0] write_ptr;              // Next location to put the byte in
logic              [2:0] read_ptr;               // Next location to read a byte form
logic              [3:0] fifo_count;             // Number of bytes in the buffer

logic do_write;
logic do_read;
assign do_write = (write_en && !full);
assign do_read  = (read_en && !empty);           

assign empty = (fifo_count == 0);
assign full  = (fifo_count == 8);

always_ff@(posedge clk) begin
    if (rst) begin
        write_ptr  <= 0;
        read_ptr   <= 0;
        fifo_count <= 0;
        data_out <= 0;
    end
    else begin
        // Writing a byte in
        if (do_write) begin
            fifo_mem[write_ptr] <= data_in;
            write_ptr <= write_ptr + 1;
        end
        // Reading it out
        if (do_read) begin
            data_out <= fifo_mem[read_ptr];
            read_ptr <= read_ptr + 1;
        end
        // Update fifo_count
        if (do_write && !do_read)
            fifo_count <= fifo_count + 1;
        else if (!do_write && do_read)
            fifo_count <= fifo_count - 1;
    end
end
endmodule
