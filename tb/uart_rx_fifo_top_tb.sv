`timescale 1ns/1ps

module uart_rx_fifo_top_tb;

    // Testbench inputs and outputs
    logic      clk;
    logic      rst;
    logic      rx;
    logic      read_en;

    wire       busy;
    wire [8:0] data_out;
    wire       full;
    wire       empty;
    wire       overrun_error;

    // Device under test: UART receiver connected to a 9-bit FIFO
    uart_rx_fifo_top dut (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .busy(busy),
        .read_en(read_en),
        .data_out(data_out),
        .full(full),
        .empty(empty),
        .overrun_error(overrun_error)
    );

    // UART timing: 50 MHz clock and 115200 baud
    localparam int CLK_FREQ = 50_000_000;
    localparam int BAUD_RATE = 115200;

    localparam int CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int BIT_PERIOD_NS = CLKS_PER_BIT * CLK_PERIOD_NS;
    localparam int TIMEOUT_NS = BIT_PERIOD_NS * 20;

    // Check task and pass/fail counters
    int pass_count = 0;
    int fail_count = 0;
    task automatic check(
        input logic [8:0] actual,
        input logic [8:0] expected,
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

    // Drive a UART frame onto rx (start bit, 8 data bits LSB-first, stop bit)
    task automatic send_uart_byte(
        input logic [7:0] data,
        input logic stop_bit
    );
        // Start bit is LOW for one bit period
        rx = 1'b0;
        #(BIT_PERIOD_NS);
        // Send the eight data bits, least-significant bit first
        for (int i = 0; i < 8; i++) begin
            rx = data[i];
            #(BIT_PERIOD_NS);
        end
        // A LOW stop_bit lets us test framing-error detection
        rx = stop_bit;
        #(BIT_PERIOD_NS);

    endtask

    // Clock generator
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // Save waveforms for GTKWave
    initial begin
        $dumpfile("uart_rx_fifo_top.vcd");
        $dumpvars(0, uart_rx_fifo_top_tb);
    end

    initial begin
        // Initialize inputs and release reset on a falling clock edge
        rst = 1;
        rx= 1;
        read_en = 0;
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        // TEST 1: RECEIVE ONE BYTE AND READ IT FROM THE FIFO
        $display("\nTEST 1: RECEIVE 8'hB1, STORE IT IN FIFO AND READ IT");
        $display("===================================================");
        check(empty, 1'b1, "FIFO initially empty");
        check(full, 1'b0, "FIFO initially not full");
        // Send one frame with a valid stop bit
        send_uart_byte(8'hB1, 1'b1);
        @(posedge clk);
        #1ps;
        check(empty, 1'b0, "FIFO no longer empty after receiving 8'bB1");
        // Assert read_en before the rising edge when the FIFO performs the read
        @(negedge clk);
        read_en = 1'b1;
        @(posedge clk);
        #1ps;
        // The ninth output bit is the framing-error flag (zero here)
        check(data_out, 9'h0B1, "Correct byte read from FIFO");
        check(empty, 1'b1, "FIFO empty again");
        @(negedge clk);
        read_en = 1'b0;

        // TEST 2: RECEIVE THREE BYTES AND CHECK FIFO ORDER
        $display("\nTEST 2: SEND 3 BYTES AND READ THEM IN CORRECT ORDER");
        $display("===================================================");
        // Queue three received bytes before reading any of them
        send_uart_byte(8'hC1, 1'b1);
        send_uart_byte(8'hC2, 1'b1);
        send_uart_byte(8'hC3, 1'b1);
        @(posedge clk);
        #1ps;
        check(empty, 1'b0, "FIFO no longer empty");
        check(full, 1'b0, "FIFO not full after 3 bytes");
        check(dut.fifo_inst.fifo_count, 4'd3, "FIFO contains 3 bytes");
        // Hold read_en HIGH for three rising edges to read all three bytes
        @(negedge clk);
        read_en = 1'b1;
        for (int i = 0; i < 3; i++) begin
            @(posedge clk);
            #1ps;
            check(data_out, 9'h0C1 + i, $sformatf("%0d. byte matches", i+1));
        end
        check(empty, 1'b1, "FIFO empty now");
        check(full, 1'b0, "FIFO not full");
        @(negedge clk);
        read_en = 1'b0;

        // TEST 3: INVALID STOP BIT / FRAMING ERROR
        $display("\nTEST 3: SEND BYTE 8'hD1 WITH INVALID STOP BIT");
        $display("=============================================");
        // Receive D1 with a LOW stop bit, then return rx to idle HIGH
        send_uart_byte(8'hD1, 1'b0);
        @(negedge clk);
        rx = 1'b1;
        @(posedge clk);
        #1ps;
        check(empty, 1'b0, "FIFO no longer empty after receiving 8'bD1");
        // FIFO should preserve the byte and store framing_error as bit 8
        @(negedge clk);
        read_en = 1'b1;
        @(posedge clk);
        #1ps;
        check(data_out, 9'h1D1, "Correct byte read from FIFO");
        check(empty, 1'b1, "FIFO empty again");
        @(negedge clk);
        read_en = 1'b0;

        // TEST 4: FILL FIFO, THEN CHECK OVERRUN ON THE NINTH BYTE
        $display("\nTEST 4: FIFO OVERFLOW AND OVERRUN_ERROR DETECTION");
        $display("=================================================");
        // Two fork branches run together: one sends eight bytes,
        // while the other checks that no overrun occurs before the FIFO is full
        fork
            begin
                for (int i = 0; i < 8; i++) begin
                    send_uart_byte(8'hD1 + i, 1'b1);
                end
            end
            begin
                fork
                    begin
                        @(posedge overrun_error);
                        $display("ERROR: overrun_error detected");
                        fail_count++;
                    end
                    begin
                        #(BIT_PERIOD_NS * 80 + CLK_PERIOD_NS * 2);
                        $display("PASS: overrun_error not detected");
                        pass_count++;
                    end
                join_any
                // Stop waiting for an overrun once the observation period ends
                disable fork;
            end
        join
        @(posedge clk);
        #1ps;
        check(empty, 1'b0, "FIFO no longer empty");
        check(full, 1'b1, "FIFO is full");
        // The ninth byte should be rejected and overrun_error should pulse once
        fork
            begin
                send_uart_byte(8'hFF, 1'b1);
            end
            begin
                fork
                    begin
                        @(posedge overrun_error);
                        #1ps;
                        check(overrun_error, 1'b1, "overrun_error detected");
                        @(posedge clk);
                        #1ps;
                        check(overrun_error, 1'b0, "overrun_error went LOW after 1 clock cycle");
                    end
                    begin
                        #(TIMEOUT_NS);
                        $display("ERROR: overrun_error");
                        fail_count++;
                    end
                join_any
                disable fork;
            end
        join
        check(full, 1'b1, "FIFO is full");
        // Read the original eight bytes to verify FF did not overwrite them
        @(negedge clk);
        read_en = 1'b1;
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            #1ps;
            check(data_out, 9'h0D1 + i, $sformatf("%0d. byte matches", i+1));
        end
        check(empty, 1'b1, "FIFO empty now");
        check(full, 1'b0, "FIFO not full");
        @(negedge clk);
        read_en = 1'b0;

        // TEST 5: FIFO READ AND WRITE ON THE SAME CLOCK EDGE
        $display("\nTEST 5: SIMULTANEOUS FIFO READ AND WRITE");
        $display("========================================");
        check(empty, 1'b1, "FIFO empty");
        check(full, 1'b0, "FIFO not full");
        // First queue E1 and E2
        send_uart_byte(8'hE1, 1'b1);
        send_uart_byte(8'hE2, 1'b1);
        @(posedge clk);
        #1ps;
        check(dut.fifo_inst.fifo_count, 4'd2, "FIFO initially contains 2 bytes");
        // Send E3 while scheduling a FIFO read at its write time
        fork
            // Branch 1: Receive the third byte
            begin
                send_uart_byte(8'hE3, 1'b1);
            end
            // Branch 2: Wait for data_valid, then read the oldest FIFO entry
            begin
                @(posedge dut.data_valid);
                @(negedge clk);
                read_en = 1'b1;
                @(posedge clk);
                #1ps;
                check(data_out, 9'h0E1, "Simultaneous read returned E1");
                @(negedge clk);
                read_en = 1'b0;
            end
        join
        // One byte added and one removed: FIFO count should stay at two
        check(dut.fifo_inst.fifo_count, 4'd2, "FIFO contains 2 bytes");
        // The remaining bytes should be E2 followed by E3
        @(negedge clk);
        read_en = 1'b1;
        for (int i = 0; i < 2; i++) begin
            @(posedge clk);
            #1ps;
            check(data_out, 9'h0E2 + i, $sformatf("%0d. byte matches", i+1));
        end
        check(empty, 1'b1, "FIFO empty now");
        check(full, 1'b0, "FIFO not full");
        @(negedge clk);
        read_en = 1'b0;

        // Final pass/fail summary
        $display("\n========================");
        $display("PASSED: %0d", pass_count);
        $display("FAILED: %0d", fail_count);
        $display("========================");
        $finish;
    end
endmodule

