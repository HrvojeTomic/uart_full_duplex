`timescale 1ns/1ps

module uart_top_tb;

    logic       clk;
    logic       rst;
    logic [7:0] data_in;
    logic       write_en;
    logic       rx;
    logic       read_en;

    wire       tx;
    wire       tx_full;
    wire [7:0] data_out;
    wire       framing_error;
    wire       rx_busy;
    wire       rx_full;
    wire       rx_empty;
    wire       overrun_error;

    logic [7:0] expected_byte;
    logic       unexpected_overrun;

    uart_top dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .write_en(write_en),
        .rx(rx),
        .read_en(read_en),
        .tx(tx),
        .tx_full(tx_full),
        .data_out(data_out),
        .framing_error(framing_error),
        .rx_busy(rx_busy),
        .rx_full(rx_full),
        .rx_empty(rx_empty),
        .overrun_error(overrun_error)
    );

    localparam int CLK_FREQ = 50_000_000;
    localparam int BAUD_RATE = 115200;

    localparam int CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int BIT_PERIOD_NS = CLKS_PER_BIT * CLK_PERIOD_NS;
    localparam int TIMEOUT_NS = BIT_PERIOD_NS * 20;

    // TASK & Pass/Fail Count
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

    // TASK TO SEND BYTES
    task automatic send_uart_byte(
        input logic [7:0] data,
        input logic stop_bit
    );
        // Send start bit and hold it for one bit period
        rx = 1'b0;
        #(BIT_PERIOD_NS);
        // Send the byte
        for (int i = 0; i < 8; i++) begin
            rx = data[i];
            #(BIT_PERIOD_NS);
        end
        // Send the stop bit and hold it for one bit period
        rx = stop_bit;
        #(BIT_PERIOD_NS);

    endtask

    // Clock Genarator
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // gtkwave form
    initial begin
        $dumpfile("uart_top.vcd");
        $dumpvars(0, uart_top_tb);
    end
    // GLOBAL SIMULATION TIMEOUT
    initial begin
        #20_000_000;

        $display("\nERROR: GLOBAL SIMULATION TIMEOUT");
        $display("Simulation exceeded maximum allowed time.");

        $fatal(1, "UART testbench timed out");
    end

    // START TESTING
    initial begin
        // Initialize inputs
        rst = 1'b1;
        data_in = 8'h00;
        write_en = 1'b0;
        rx = 1'b1;
        read_en = 1'b0;
        // Make sure reset activates then deactivate it
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        // TEST 1: RESET CONDITIONS
        $display("\nTEST 1: RESET CONDITIONS");
        $display("========================");
        
        check(tx, 1'b1, "TX idle high");
        check(tx_full, 1'b0, "TX FIFO not full");
        check(rx_busy, 1'b0, "RX not busy");
        check(rx_empty, 1'b1, "RX FIFO empty");
        check(rx_full, 1'b0, "RX FIFO not full");
        check(overrun_error, 1'b0, "No overrun_error");

        // TEST 2: TRANSMIT A SINGLE BYTE
        $display("\nTEST 2: TRANSMIT BYTE 01");
        $display("========================");
        // Monitor for the byte
        fork
            // Branch 1: Transmission
            begin
                @(negedge clk);
                data_in = 8'h01;
                write_en = 1'b1;
                @(negedge clk);
                write_en = 1'b0;
            end
            // Branch 2: Monitor the transmission
            begin
                expected_byte = 8'h01;
                // Start bit
                @(negedge tx);
                #(BIT_PERIOD_NS / 2);
                check(tx, 1'b0, "TX start bit");
                // 8 bits
                for (int i = 0; i < 8; i++) begin
                    #(BIT_PERIOD_NS);
                    check(tx, expected_byte[i], $sformatf("%0d. bit matches", i+1));
                end
                // Stop bit
                #(BIT_PERIOD_NS);
                check(tx, 1'b1, "TX stop bit");
            end
        join

        // TEST 3: RECEIVE A SINGLE BYTE
        $display("\nTEST 3: RECEIVE BYTE 02");
        $display("=======================");
        send_uart_byte(8'h02, 1'b1);
        @(negedge clk);
        check(rx_empty, 1'b0, "RX FIFO contains data");
        check(rx_full, 1'b0, "RX FIFO not full");
        check(rx_busy, 1'b0, "RX receiver in IDLE");
        // Read the received byte
        @(negedge clk);
        read_en = 1'b1;
        @(posedge clk);
        #1ps;
        check(data_out, 8'h02, "Recevied byte matches");
        check(framing_error, 1'b0, "No framing_error");
        @(negedge clk);
        read_en = 1'b0;
        // After the Read, check if empty
        check(rx_empty, 1'b1, "RX FIFO empty after read");

        // TEST 4: FULL-DUPLEX COMMUNICATION
        $display("\nTEST 4: FULL-DUPLEX COMMUNICATION");
        $display("=================================");

        fork
            // Branch 1: Write byte into TX FIFO
            begin
                @(negedge clk);
                data_in = 8'hA5;
                write_en = 1'b1;
                @(negedge clk);
                write_en = 1'b0;
            end
            // Branch 2: Monitor for serial TX output
            begin
                expected_byte = 8'hA5;
                @(negedge tx);
                #(BIT_PERIOD_NS / 2);
                check(tx, 1'b0, "TX start bit");
                for (int i = 0; i < 8; i++) begin
                    #(BIT_PERIOD_NS);
                    check(tx, expected_byte[i], $sformatf("TX bit %0d matches", i));
                end
                #(BIT_PERIOD_NS);
                check(tx, 1'b1, "TX stop bit");
            end
            // Branch 3: Send a byte into RX a read it
            begin
                send_uart_byte(8'h3C, 1'b1);
                @(negedge clk);
                check(rx_empty, 1'b0, "RX FIFO contains a byte");
                @(negedge clk);
                read_en = 1'b1;
                @(posedge clk);
                #1ps;
                check(data_out, 8'h3C, "Received byte matches");
                check(framing_error, 1'b0, "No framing_error");
                @(negedge clk);
                read_en = 1'b0;
                check(rx_empty, 1'b1, "RX FIFO empty after read");
            end
        join

        // TEST 5: MULTIPLE-BYTE FULL-DUPLEX COMMUNICATION
        $display("\nTEST 5: MULTIPLE-BYTE FULL-DUPLEX COMMUNICATION");
        $display("===============================================");
        fork
            // Branch 1: Send multiple bytes to TX FIFO
            begin
                @(negedge clk);
                write_en = 1'b1;
                for (int i = 0; i < 3; i++) begin
                    data_in = 8'hC1 + i;
                    @(negedge clk);
                end
                write_en = 1'b0;
            end
            // Branch 2: Monitor for multiple bytes transmission
            begin
                for (int j = 0; j < 3; j++) begin

                    expected_byte = 8'hC1 + j;

                    @(negedge tx);
                    #(BIT_PERIOD_NS/2);
                    check(tx, 1'b0, "Start bit"); // Start bit
                    for (int i = 0; i < 8; i++) begin
                        #(BIT_PERIOD_NS);
                        check(tx, expected_byte[i], $sformatf("TX bit %0d matches",i)); // Data bit i
                    end
                    #(BIT_PERIOD_NS);
                    check(tx, 1'b1, "Stop bit"); // Stop bit
                end
            end
            // Branch 3: RX receives multiple bytes and reads them
            begin
                // Send 3 bytes
                for (int i = 0; i < 3; i++) begin
                    send_uart_byte(8'hD1 + i, 1'b1);
                end
                @(negedge clk);
                check(rx_empty, 1'b0, "RX FIFO no longer empty");
                check(rx_full, 1'b0, "RX FIFO not full");
                // Read 3 bytes
                read_en = 1'b1;
                for (int i = 0; i < 3; i++) begin
                    @(posedge clk);
                    #1ps;
                    check(data_out, 9'h0D1 + i, $sformatf("RX byte %0d byte matches", i+1));
                    check(framing_error, 1'b0, $sformatf("RX byte %0d no framing_error", i+1));

                end
                @(negedge clk);
                read_en = 1'b0;
                check(rx_empty, 1'b1, "RX FIFO empty now");
                check(rx_full, 1'b0, "RX FIFO not full");
            end
        join

        // TEST 6: FRAMING ERROR DETECTION
        $display("\nTEST 6: FRAMING ERROR DETECTION");
        $display("===============================");
        // Send a byte with invalid stop bit
        send_uart_byte(8'hAA, 1'b0); 
        // Return UART line back to IDLE
        @(negedge clk);
        rx = 1'b1;
        @(posedge clk);
        #1ps;
        check(rx_empty, 1'b0, "RX FIFO no longer empty");
        // Perform a read now
        @(negedge clk);
        read_en = 1'b1;
        @(posedge clk);
        #1ps;
        check(data_out, 8'hAA, "Correct byte read from RX FIFO");
        check(framing_error, 1'b1, "Byte AA -> framing_error detected");
        @(negedge clk);
        read_en = 1'b0;
        check(rx_empty, 1'b1, "RX FIFO empty again");

        // TEST 7: RX FIFO OVERRUN DETECTION
        $display("\nTEST 7: RX FIFO OVERRUN DETECTION");
        $display("=================================");
        // Write 8 bytes and scan for overrun
        unexpected_overrun = 1'b0;
        fork
            begin
                // Send all 8 bytes
                for (int i = 0; i < 8; i++) begin
                    send_uart_byte(8'hF0 + i, 1'b1);
                end
            end
            begin
                fork
                    begin
                        // Observe for overrun detection
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
                disable fork;
            end
        join
        @(posedge clk);
        #1ps;
        check(rx_empty, 1'b0, "FIFO no longer empty");
        check(rx_full, 1'b1, "FIFO is full");
        // Send 9th byte and simultaneously observe for overrun_error
        fork
            begin
                send_uart_byte(8'hFF, 1'b1);
            end
            begin
                fork
                    begin
                        // Observe for overrun detection
                        @(posedge overrun_error);
                        #1ps;
                        check(overrun_error, 1'b1, "overrun_error detected");
                        @(posedge clk);
                        #1ps;
                        check(overrun_error, 1'b0, "overrun_error went LOW after 1 clock cycle");
                    end
                    begin
                        #(TIMEOUT_NS);
                        $display("ERROR: overrun_error never went high");
                        fail_count++;
                    end
                join_any
                disable fork;
            end
        join
        check(rx_full, 1'b1, "RX FIFO is full");
        // Read the bytes
        @(negedge clk);
        read_en = 1'b1;
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            #1ps;
            check(data_out, 8'hF0 + i, $sformatf("RX byte %0d byte matches", i+1));
            check(framing_error, 1'b0, $sformatf("RX byte %0d no framing_error", i+1));
        end
        check(rx_empty, 1'b1, "RX FIFO empty now");
        check(rx_full, 1'b0, "RX FIFO not full");
        @(negedge clk);
        read_en = 1'b0;

        // TEST 8: TX FIFO FULL CONDITION
        $display("\nTEST 8: TX FIFO FULL CONDITION");
        $display("==============================");
        fork
            begin
                // Write one byte
                @(negedge clk);
                data_in = 8'hB0;
                write_en = 1'b1;
                @(negedge clk);
                write_en = 1'b0;
                wait (dut.tx_unit.uart_inst.busy == 1'b1);
                // While it's busy write 8 more
                for (int i = 0; i < 8; i++) begin
                    @(negedge clk);
                    data_in = 8'hB1 + i;
                    write_en = 1'b1;
                end
                @(negedge clk);
                write_en = 1'b0;
                // Check it's full
                check(tx_full, 1'b1, "FIFO is full");
                // Attempt to write 10th byte while FIFO is full
                @(negedge clk);
                data_in = 8'hBF;
                write_en = 1'b1;
                @(negedge clk);
                write_en = 1'b0;
                check(dut.tx_unit.fifo_inst.fifo_count, 8, "FIFO rejected extra byte");
            end
            begin
                // Check the transmission of 9 bytes
                for (int j = 0; j < 9; j++) begin

                    expected_byte = 8'hB0 + j;

                    @(negedge tx);
                    #(BIT_PERIOD_NS/2);
                    check(tx, 1'b0, "Start bit"); // Start bit
                    for (int i = 0; i < 8; i++) begin
                        #(BIT_PERIOD_NS);
                        check(tx, expected_byte[i], $sformatf("Data bit %0d",i)); // Data bit i
                    end
                    #(BIT_PERIOD_NS);
                    check(tx, 1'b1, "Stop bit"); // Stop bit
                end
                // Check that 10th transmission never starts
                wait (dut.tx_unit.uart_inst.busy == 1'b0);
                fork
                    begin
                        @(negedge tx);
                        check(1'b1, 1'b0, "Unexpected 10th transmission!");
                    end
                    begin
                        #(TIMEOUT_NS);
                        check(tx, 1'b1, "TX remained HIGH");
                    end
                join_any
                disable fork;
            end
        join
        #(BIT_PERIOD_NS)
        check(tx, 1'b1, "TX should be HIGH after transmission"); // make sure tx = 1 in IDLE
        check(dut.tx_unit.uart_inst.busy, 1'b0, "UART should be idle"); // make sure UART is done transmitting before moving on
        check(dut.tx_unit.fifo_inst.empty, 1'b1, "FIFO should be empty"); // make sure 9th byte (8'hBF) wasn't accpeted


        // TEST 9: RESET DURING ACTIVE COMMUNICATION
        $display("\nTEST 9: RESET DURING ACTIVE COMMUNICATION");
        $display("=========================================");
        fork
            // Branch 1: Start TX transmission
            begin
                @(negedge clk);
                data_in = 8'hA5;
                write_en = 1'b1;
                @(negedge clk);
                write_en = 1'b0;
            end
            // Branch 2: Start receiving a byte through RX
            begin
                fork
                    begin
                        send_uart_byte(8'h3C, 1'b1);
                    end
                    begin
                        @(posedge rst);
                    end
                join_any
                disable fork;
                // Return RX line to IDLE
                rx = 1'b1;
            end
            // Branch 3: Wailt until both are busy then reset
            begin
                wait (dut.tx_unit.uart_inst.busy && 
                      dut.rx_unit.uart_inst.busy);
                #(BIT_PERIOD_NS * 5);
                check(dut.tx_unit.uart_inst.busy, 1'b1, "TX busy before reset");
                check(rx_busy, 1'b1, "RX busy before reset");
                @(negedge clk);
                rst = 1'b1;
                repeat (3) @(posedge clk);
                #1ps;
                check(tx, 1'b1, "TX returned to IDLE");
                check(rx_busy, 1'b0, "RX returned to IDLE");
                check(dut.tx_unit.fifo_empty, 1'b1, "TX FIFO empty");
                check(rx_empty, 1'b1, "RX FIFO empty");
                check(overrun_error, 1'b0, "Overrun error cleared");
                @(negedge clk);
                rst = 1'b0;
            end
        join

        // TEST 10: POST-RESET RECOVERY
        $display("\nTEST 10: POST-RESET RECOVERY");
        $display("============================");
        fork
            // Branch 1: Write byte into TX FIFO
            begin
                @(negedge clk);
                data_in = 8'hB6;
                write_en = 1'b1;
                @(negedge clk);
                write_en = 1'b0;
            end
            // Branch 2: Monitor for serial TX output
            begin
                expected_byte = 8'hB6;
                @(negedge tx);
                #(BIT_PERIOD_NS / 2);
                check(tx, 1'b0, "TX start bit");
                for (int i = 0; i < 8; i++) begin
                    #(BIT_PERIOD_NS);
                    check(tx, expected_byte[i], $sformatf("TX bit %0d matches", i));
                end
                #(BIT_PERIOD_NS);
                check(tx, 1'b1, "TX stop bit");
            end
            // Branch 3: Send a byte into RX a read it
            begin
                send_uart_byte(8'h7F, 1'b1);
                @(negedge clk);
                check(rx_empty, 1'b0, "RX FIFO contains a byte");
                @(negedge clk);
                read_en = 1'b1;
                @(posedge clk);
                #1ps;
                check(data_out, 8'h7F, "Received byte matches");
                check(framing_error, 1'b0, "No framing_error");
                @(negedge clk);
                read_en = 1'b0;
                check(rx_empty, 1'b1, "RX FIFO empty after read");
            end
        join
        check(tx, 1'b1, "TX idle after recovery");
        check(rx_busy, 1'b0, "RX idle after recovery");
        check(dut.tx_unit.fifo_empty, 1'b1, "TX FIFO empty after recovery");
        check(rx_empty, 1'b1, "RX FIFO empty after recovery");
        check(overrun_error, 1'b0, "No overrun after recovery");


        $display("\n=========================");
        $display("   FINAL TEST SUMMARY    ");
        $display("=========================");
        $display("PASSED: %0d", pass_count);
        $display("FAILED: %0d", fail_count);   
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED!");
        end
        else begin
            $fatal(1, "UART TESTBENCH FAILED!");
        end
        $display("=========================");
        $finish;

    end

endmodule