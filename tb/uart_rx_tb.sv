`timescale 1ns/1ps

module uart_rx_tb;

    logic      clk;
    logic      rst;
    logic      rx;

    wire       busy;
    wire       data_valid;
    wire [7:0] data_out;
    wire       framing_error;

    localparam int CLK_FREQ = 50_000_000;
    localparam int BAUD_RATE = 115200;

    localparam int CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int BIT_PERIOD_NS = CLKS_PER_BIT * CLK_PERIOD_NS;
    localparam int TIMEOUT_NS = BIT_PERIOD_NS * 12;

    // Check a signal against its expected value and track pass/fail counts
    int pass_count = 0;
    int fail_count = 0;
    task automatic check(
        input logic [7:0] actual,
        input logic [7:0] expected,
        input string message
    );
        if (actual !== expected) begin
            $display("ERROR: %s | Expected: %0d, Actual: %0d", message, expected, actual);
            fail_count++;
        end
        else begin
            $display("PASS: %s | Expected: %0d, Actual: %0d", message, expected, actual);
            pass_count++;
        end
    endtask

    // Drive a complete UART frame onto rx (start, 8 data bits, stop)
    task automatic send_uart_byte(
        input logic [7:0] data,
        input logic stop_bit
    );
        // Start bit is LOW for one bit period
        rx = 1'b0;
        #(BIT_PERIOD_NS);
        // Send data least-significant bit first
        for (int i = 0; i < 8; i++) begin
            rx = data[i];
            #(BIT_PERIOD_NS);
        end
        // A LOW stop_bit intentionally creates a framing error
        rx = stop_bit;
        #(BIT_PERIOD_NS);

    endtask

    // 50 MHz clock generator
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // UART receiver under test
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .busy(busy),
        .data_valid(data_valid),
        .data_out(data_out),
        .framing_error(framing_error)
    );

    // Save waveforms for GTKWave
    initial begin
        $dumpfile("uart_rx.vcd");
        $dumpvars(0, uart_rx_tb);
    end

    // Run receiver tests
    initial begin
        // Start in reset with the RX line idle (HIGH)
        rst = 1;
        rx = 1;
        @(negedge clk);
        rst = 0;
        @(negedge clk);

        // TEST 1: RECEIVE ONE BYTE
        $display("\nTEST 1: SEND h'11");
        fork
            // Branch 1: Drive the incoming UART frame
            begin
                send_uart_byte(8'h11,1);
            end
            // Branch 2: Check the received byte and data_valid pulse
            begin
                fork
                    begin
                        @(posedge data_valid);
                        // Wait for nonblocking assignments to settle
                        #1ps;
                        check(data_out, 8'h11, "Received 11");
                        check(framing_error, 8'h00, "No framing error");
                        @(posedge clk);
                        #1ps;
                        check(data_valid, 8'h00, "data_valid returned LOW");
                    end
                    begin
                        // Avoid hanging if the receiver never finishes
                        #(TIMEOUT_NS);
                        $display("ERROR: Timeout!");
                        fail_count++;
                    end
                join_any
                disable fork;
            end
        join

        // TEST 2: RECEIVE TWO CONSECUTIVE BYTES
        $display("\nTEST 2: SEND 2 CONSECUTIVE BYTES (8'h21 & 8'h22)");
        fork
            // Branch 1: Send both frames back-to-back
            begin
                send_uart_byte(8'h21,1);
                send_uart_byte(8'h22,1);
            end
            // Branch 2: Verify both bytes and one-cycle data_valid pulses
            begin
                fork
                    begin
                        @(posedge data_valid);
                        #1ps;
                        check(data_out, 8'h21, "Received 21");
                        check(framing_error, 8'h00, "No framing error");
                        @(posedge clk);
                        #1ps;
                        check(data_valid, 8'h00, "1st data_valid returned LOW after 1 cycle");
                        @(posedge data_valid);
                        #1ps;
                        check(data_out, 8'h22, "Received 22");
                        check(framing_error, 8'h00, "No framing error");
                        @(posedge clk);
                        #1ps;
                        check(data_valid, 8'h00, "2nd data_valid returned LOW after 1 cycle");
                    end
                    begin
                        #(TIMEOUT_NS * 2);
                        $display("ERROR: Timeout!");
                        fail_count++;
                    end
                join_any
                disable fork;
            end
        join

        // TEST 3: REJECT A FALSE START BIT (NOISE)
        $display("\nTEST 3: CHECK FOR INVALID START BIT (NOISE DETECTION)");
        fork
            // Branch 1: Pull rx LOW briefly, then return it to idle
            // The pulse is shorter than half a bit, so the start check should reject it
            begin
                rx = 1'b0;
                #(BIT_PERIOD_NS / 4);
                rx = 1'b1;
                #(BIT_PERIOD_NS / 4);
                #(CLK_PERIOD_NS * 10);
            end
            // Branch 2: Make sure no received-byte pulse occurs
            begin
                fork
                    begin
                        @(posedge data_valid);
                        $display("ERROR: data_valid detected!");
                        fail_count++;
                    end
                    begin
                        #(TIMEOUT_NS);
                        $display("PASS: data_valid stayed low");
                        pass_count++;
                    end
                join_any
                disable fork;
            end
            // Branch 3: Receiver should briefly become busy, then return to IDLE
            begin
                fork
                    begin
                        @(posedge busy);
                        @(negedge busy);
                        pass_count++;
                    end
                    begin
                        #(TIMEOUT_NS);
                        $display("ERROR: busy");
                        fail_count++;
                    end
                join_any
                disable fork;
            end
            // Branch 4: A false start must not produce a framing error
            begin
                fork
                    begin
                        @(posedge framing_error);
                        $display("ERROR: Framing error detected!");
                        fail_count++;
                    end
                    begin
                        #(TIMEOUT_NS);
                        $display("PASS: framing_error stayed low");
                        pass_count++;
                    end
                join_any
                disable fork;
            end
        join
        // The previous valid byte should still be on data_out
        check(busy, 8'h00, "Busy successfully returned low!");
        check(data_out, 8'h22, "False start did not modify data_out");

        // TEST 4: INVALID STOP BIT / FRAMING ERROR
        $display("\nTEST 4: CHECK FOR INVALID STOP BIT (SEND THE BYTE 8'h41 AND DECLARE FRAMING ERROR)");
        fork
            // Branch 1: Send 0x41 with a LOW stop bit
            begin
                send_uart_byte(8'h41,0);
                rx = 1'b1; // Return the RX line to idle
            end
            // Branch 2: Data should still be received, with framing_error asserted
            begin
                fork
                    begin
                        // Both status pulses are expected when the frame completes
                        @(posedge data_valid);
                        #1ps;
                        check(data_out, 8'h41, "Received the byte despite the framing_error!");
                        check(framing_error, 8'h01, "framing_error synchronized with data_valid!");
                        $display("PASS: data_valid detected");
                        pass_count++;
                        // Both pulses should clear on the following clock
                        @(posedge clk);
                        #1ps;
                        check(data_valid, 8'h00, "data_valid returned low");
                        check(framing_error, 8'h00, "framing_error returned low");
                    end
                    begin
                        #(TIMEOUT_NS);
                        $display("ERROR: Timeout waiting for data_valid!");
                        fail_count++;
                    end
                join_any
                disable fork;
            end
        join

        // Final test summary
        $display("================================");
        $display("UART RX Test Results");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("================================");

        $finish;
    end

endmodule

