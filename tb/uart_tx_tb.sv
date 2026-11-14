`timescale 1ns/1ps

module uart_tx_tb;

    // Testbench inputs and expected transmitted data
    logic clk;
    logic rst;
    logic start;
    logic [7:0] data_in;
    logic [7:0] expected_data;

    // UART outputs
    wire tx;
    wire busy;

    // UART timing settings: 50 MHz clock and 115200 baud
    localparam int CLK_FREQ = 50_000_000;
    localparam int BAUD_RATE = 115200;

    localparam int CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int BIT_PERIOD_NS = CLKS_PER_BIT * CLK_PERIOD_NS;
    localparam int TIMEOUT_NS = BIT_PERIOD_NS * 12;

    // Check task and pass/fail counters
    int pass_count = 0;
    int fail_count = 0;
    task automatic check(
        input logic actual,
        input logic expected,
        input string message
    );
        if (actual !== expected) begin
            $display("ERROR: %s",message);
            fail_count++;
        end
        else begin
            $display("PASS: %s", message);
            pass_count++;
        end
    endtask

    // Clock generator
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // UART transmitter under test
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_in(data_in),
        .tx(tx),
        .busy(busy)
    );

    // Save waveforms for GTKWave
    initial begin
        $dumpfile("uart_tx.vcd");
        $dumpvars(0, uart_tx_tb);
    end

    // Apply test inputs and check reset/recovery behavior
    initial begin

        // TEST 1: RESET DURING A TRANSMISSION
        // Start with reset asserted and no transmission request.
        rst = 1;
        start = 0;
        data_in = 8'b00000000;

        // Hold reset HIGH for two clock periods, then release it.
        #(CLK_PERIOD_NS * 2);
        rst = 0;

        #(CLK_PERIOD_NS);

        // Apply inputs on falling edges so they are stable at the next rising edge.
        @(negedge clk);
        expected_data = 8'b10101010;
        data_in       = 8'b10101010;
        start = 1;

        // Pulse start for one clock cycle.
        @(negedge clk);
        start = 0;

        wait (busy == 1'b1);

        // Interrupt the first transmission after three UART bit periods.
        #(BIT_PERIOD_NS * 3);
        @(negedge clk);
        rst = 1;

        // Check outputs after the rising edge updates the UART registers.
        @(posedge clk);
        #1;
        check(tx, 1'b1, "TX returned HIGH after reset!");
        check(busy, 1'b0, "Busy returned LOW after reset!");

        // TEST 2: TRANSMIT AGAIN AFTER RESET
        // Release reset and send the same byte to check recovery.
        @(negedge clk);
        rst = 0;

        @(negedge clk);
        data_in = 8'b10101010;
        start = 1;

        @(negedge clk);
        start = 0;

        // Wait for transmission to finish, but fail if it takes too long.
        fork
            begin
                wait (busy == 1'b1);
                wait (busy == 1'b0);
                $display("PASS: UART completed transmission!");
                pass_count++;
            end

            begin
                #(TIMEOUT_NS);
                $display("ERROR: UART transmission timed out!");
                fail_count++;
            end
        join_any
        // Stop whichever branch did not finish.
        disable fork;

        // Give the separate TX output checker time to complete.
        #(BIT_PERIOD_NS);

        // Final test summary
        $display("\n================================");
        $display("       UART TEST SUMMARY");
        $display("================================");
        $display("Total Checks : %0d", pass_count + fail_count);
        $display("Passed       : %0d", pass_count);
        $display("Failed       : %0d", fail_count);

        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: TEST FAILED");
        $display("================================\n");

        $finish;

    end

    // Check the serial TX bits of the second transmission.
    // Skip the first transmission because it is intentionally reset midway.
    initial begin
        wait (rst == 1'b0);
        @(posedge rst);
        @(negedge rst);

        for (int frame = 0; frame < 1; frame++) begin
            // Detect the falling edge of the start bit and sample at its center.
            @(negedge tx);
            #(BIT_PERIOD_NS/2);

            check(tx, 1'b0, "START TX bit");
            check(busy, 1'b1, "START Busy bit");

            // Sample each of the eight data bits at its center (LSB first).
            for (int i = 0; i < 8; i++) begin
                #(BIT_PERIOD_NS);
                check(tx, expected_data[i], $sformatf("Data TX bit %0d",i));
            end

            // The stop bit must be HIGH while the transmitter is still busy.
            #(BIT_PERIOD_NS);
            check(tx, 1'b1, "STOP TX bit");
            check(busy, 1'b1, "STOP Busy bit");

            // After the stop bit, TX stays HIGH and busy goes LOW.
            #(BIT_PERIOD_NS/2 + CLK_PERIOD_NS);
            check(tx, 1'b1, "IDLE TX bit");
            check(busy, 1'b0, "IDLE Busy bit");

            // Make sure the UART remains idle after the frame.
            #20000;
            check(tx, 1'b1, "TX stayed HIGH");
            check(busy, 1'b0, "UART ignored the start request");
        end
    end

endmodule

