`timescale 1ns/1ps

module fifo_tb;

    // Testbench for the 8-entry, 8-bit synchronous FIFO.
    // Inputs are changed on falling clock edges so the FIFO can sample
    // them on the next rising edge.

    logic       clk;
    logic       rst;
    logic [7:0] data_in;
    logic       write_en;
    logic       read_en;
    wire  [7:0] data_out;
    wire        full;
    wire        empty;
    logic [7:0] expected_data [0:2];
    logic [7:0] previous_data_out;

    // Device under test (DUT)
    fifo dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .write_en(write_en),
        .read_en(read_en),
        .data_out(data_out),
        .full(full),
        .empty(empty)
    ); 

    localparam int CLK_FREQ = 50_000_000;
    localparam int CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;

    // Check task and pass/fail counters
    int pass_count = 0;
    int fail_count = 0;
    task automatic check(
        input logic [7:0] actual,
        input logic [7:0] expected,
        input string message
    );
        if (actual !== expected) begin
            $display("ERROR: %s | Expected: %0d, Actual: %0d",message, expected, actual);
            fail_count++;
        end
        else begin
            $display("PASS: %s | Expected: %0d, Actual: %0d",message, expected, actual);
            pass_count++;
        end
    endtask

    // Generate a 50 MHz clock (20 ns period)
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    initial begin
        // TEST 1: RESET
        // Initialize inputs and reset the FIFO
        rst = 1'b1;
        write_en = 1'b0;
        read_en = 1'b0;
        data_in = 8'b00000000;

        // Hold reset through a rising edge
        @(posedge clk)
        // Release reset
        @(negedge clk)
        rst = 1'b0;

        check(empty, 1'b1, "FIFO empty after reset");
        check(full, 1'b0, "FIFO not full after reset");

        // TEST 2: SINGLE WRITE AND READ
        // Write one byte into the FIFO
        @(negedge clk);
        data_in = 8'b10101010;
        write_en = 1'b1;
        // Hold write enable for one rising clock edge
        @(negedge clk);
        write_en = 1'b0;
        check(empty, 1'b0, "FIFO not empty after write");
        check(full, 1'b0, "FIFO not full after one write");

        // Read one byte from the FIFO
        @(negedge clk);
        read_en = 1'b1;
        // Hold read enable for one rising clock edge
        @(negedge clk);
        read_en = 1'b0;
        check(data_out, 8'b10101010, "FIFO read correct byte");
        check(empty, 1'b1, "FIFO empty after reading last byte");
        check(full, 1'b0, "FIFO not full after reading");

        // TEST 3: MULTIPLE WRITES AND READS
        // Check that bytes come out in the order they were written
        @(negedge clk);
        data_in = 8'hAA; // Byte A
        write_en = 1;
        @(negedge clk);
        data_in = 8'hBB; // Byte B
        @(negedge clk); 
        data_in = 8'hCC; // Byte C
        @(negedge clk);
        write_en = 1'b0;
        // Reads AA
        @(negedge clk);
        read_en = 1'b1;
        @(negedge clk);
        read_en = 1'b0;
        check(data_out, 8'hAA, "First FIFO read byte correct");
        check(empty, 1'b0, "FIFO not empty after 1st read");
        check(full, 1'b0, "FIFO not full after 1st read");
        // Reads BB
        @(negedge clk);
        read_en = 1'b1;
        @(negedge clk);
        read_en = 1'b0;
        check(data_out, 8'hBB, "Second FIFO read byte correct");
        // Reads CC
        @(negedge clk);
        read_en = 1'b1;
        @(negedge clk);
        read_en = 1'b0;
        check(data_out, 8'hCC, "tHIRD FIFO read byte correct");
        check(empty, 1'b1, "FIFO empty after 3rd read");
        check(full, 1'b0, "FIFO not full after 3rd read");

        // TEST 4: FIFO FULL / EXTRA WRITE
        // Fill all 8 entries, then try writing a 9th byte
        for (int i = 0; i < 8; i++) begin
            @(negedge clk);
            data_in = i;
            write_en = 1'b1;
        end
        @(negedge clk);
        write_en = 1'b0;
        check(empty, 1'b0, "FIFO not empty after 8 writes");
        check(full, 1'b1, "FIFO full after 8 writes");
        // The full FIFO should reject this extra byte
        @(negedge clk);
        data_in = 8'hFF;
        write_en = 1'b1;
        @(negedge clk);
        write_en = 1'b0;
        // Check that FIFO still full
        check(full, 1'b1, "FIFO full after 8+1 writes");
        // Read all 8 entries to verify the rejected write changed nothing
        for (int i = 0; i < 8; i++) begin
            // Assert read on the falling edge
            @(negedge clk);
            read_en = 1'b1;
            // data_out updates on the rising edge, so check after it
            @(negedge clk);
            check(data_out, i, "FIFO read byte correct"); // checks on next negedge
            read_en = 1'b0;
        end
        check(empty, 1'b1, "FIFO empty after 8 reads");
        check(full, 1'b0, "FIFO not full after 8 reads");

        // TEST 5: READ WHILE EMPTY
        // A read request on an empty FIFO should not change the count
        @(negedge clk);
        read_en = 1'b1;
        @(negedge clk);
        read_en = 1'b0;
        check(empty, 1'b1, "FIFO still empty after trying to read on empty");
        check(full, 1'b0, "FIFO not full after trying to read on empty");

        // TEST 6: POINTER WRAPAROUND
        // Write and read pointers are 3 bits wide and wrap from 7 to 0.
        // Write 6 bytes, then read them back and check pointer positions.
        for (int i = 10; i < 16; i++) begin
            @(negedge clk);
            write_en = 1'b1;
            data_in = i;
        end
        @(negedge clk);
        write_en = 1'b0;
        check(dut.write_ptr, 3'd2, "Write pointer wrapped correctly");
        check(dut.read_ptr, 3'd4, "Read pointer remained unchanged");
        check(dut.fifo_count, 4'd6, "FIFO count is 6 bytes");
        // Read the 6 bytes and confirm their order
        for (int i = 10; i < 16; i++) begin
            @(negedge clk);
            read_en = 1'b1;
            @(negedge clk);
            check(data_out, i, "FIFO read byte correct");
            read_en = 1'b0;
        end
        check(empty, 1'b1, "FIFO empty after reading 6 bytes");
        check(full, 1'b0, "FIFO not full after reads");
        check(dut.write_ptr, 3'd2, "Write pointer wrapped correctly");
        check(dut.read_ptr, 3'd2, "Read pointer wrapped correctly");
        check(dut.fifo_count, 4'd0, "FIFO count is zero");

        // TEST 7: SIMULTANEOUS READ AND WRITE
        // Start with 3 bytes in the FIFO
        for (int i = 0; i < 3; i++) begin
            @(negedge clk);
            write_en = 1'b1;
            data_in = 8'hAA + i;
        end
        @(negedge clk);
        write_en = 1'b0;

        // Read the oldest byte while writing a new byte on the same edge
        @(negedge clk);
        write_en = 1'b1;
        data_in = 8'hDD;
        read_en = 1'b1;
        @(negedge clk);
        write_en = 1'b0;
        read_en = 1'b0;
        check(data_out, 8'hAA, "Simultaneous read returns the oldest byte");
        check(dut.write_ptr, 3'd6, "Write pointer advanced correctly");
        check(dut.read_ptr, 3'd3, "Read pointer advanced correctly");
        check(dut.fifo_count, 4'd3, "FIFO count unchanged after simulataneous writes and reads");

        // Check for remaining 3 bytes (AB, AC, DD)
        expected_data[0] = 8'hAB;
        expected_data[1] = 8'hAC;
        expected_data[2] = 8'hDD;
        for (int i = 0; i < 3; i++) begin
            @(negedge clk);
            read_en = 1'b1;
            @(negedge clk);
            read_en = 1'b0;
            check(data_out, expected_data[i], "FIFO read correct byte");
        end
        check(empty, 1'b1, "FIFO empty after 3 writes and 3 reads");
        check(full, 1'b0, "FIFO not full");

        // TEST 8: SIMULTANEOUS READ/WRITE WHEN EMPTY
        // The read should be blocked, but the write should succeed
        previous_data_out = data_out;
        // Perform write and read simultaneously
        @(negedge clk);
        write_en = 1'b1;
        read_en = 1'b1;
        data_in = 8'hBA;
        @(negedge clk);
        write_en = 1'b0;
        read_en = 1'b0;
        check(data_out, previous_data_out, "Read blocked when FIFO empty");
        check(dut.fifo_count, 4'd1, "Only write operation performed");
        check(empty, 1'b0, "FIFO no longer empty");
        // Now perform a read
        @(negedge clk);
        read_en = 1'b1;
        @(negedge clk);
        read_en = 1'b0;
        check(data_out, 8'hBA, "Correct byte read after blocked read");
        check(dut.fifo_count, 4'd0, "FIFO count zero after reading 8'hBA");
        check(empty, 1'b1, "FIFO empty");

        // TEST 9: SIMULTANEOUS READ/WRITE WHEN FULL
        // The write should be blocked, but the read should succeed
        // First we fill up the FIFO
        for (int i = 0; i < 8; i++) begin
            @(negedge clk);
            write_en = 1;
            data_in = 8'hE0 + i;
        end
        @(negedge clk);
        write_en = 1'b0;
        check(empty, 1'b0, "FIFO not empty after 8 writes");
        check(full, 1'b1, "FIFO full after 8 writes");
        check(dut.write_ptr, 3'd7, "Write pointer advanced correctly");
        check(dut.read_ptr, 3'd7, "Read pointer stayed correctly");
        check(dut.fifo_count, 4'd8, "FIFO count is maxed");
        // Perform write and read simultaneously
        @(negedge clk);
        write_en = 1'b1;
        read_en = 1'b1;
        data_in = 8'hF0;
        @(negedge clk);
        write_en = 1'b0;
        read_en = 1'b0;
        check(empty, 1'b0, "FIFO not empty");
        check(full, 1'b0, "FIFO not full anymore");
        check(dut.write_ptr, 3'd7, "Write pointer stayed correctly");
        check(dut.read_ptr, 3'd0, "Read pointer advanced correctly");
        check(dut.fifo_count, 4'd7, "FIFO count decreased correctly");
        check(data_out, 8'hE0, "Oldest byte read when FIFO full");

        // Now perform a write
        @(negedge clk);
        write_en = 1'b1;
        data_in = 8'hE8;
        @(negedge clk);
        write_en = 1'b0;
        check(full, 1'b1, "FIFO full again after writing E8");
        check(dut.fifo_count, 4'd8, "FIFO count is 8 after writing E8");
        // Confirm F0 was rejected and E8 was stored instead
        for (int i = 0; i < 8; i++) begin
            @(negedge clk);
            read_en = 1'b1;
            @(negedge clk);
            read_en = 1'b0;
            check(data_out, 8'hE1 + i, "FIFO remaining 7 bytes are correct");
        end
        check(dut.fifo_count, 4'd0, "FIFO count zero after all reads");
        check(empty, 1'b1, "FIFO empty after all reads");
        check(full, 1'b0, "FIFO not full after all reads");
        check(dut.write_ptr, 3'd0, "Write pointer advanced correctly");
        check(dut.read_ptr, 3'd0, "Read pointer stayed correctly");

        // Print final pass/fail totals
        $display("-------------------------");
        $display("Tests passed: %0d", pass_count);
        $display("Tests failed: %0d", fail_count);
        $display("-------------------------");

        $finish;
    end
endmodule
