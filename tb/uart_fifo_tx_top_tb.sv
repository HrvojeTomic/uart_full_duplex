`timescale 1ns/1ps

module uart_fifo_tx_top_tb;

    logic       clk;
    logic       rst;
    logic [7:0] data_in;
    logic       write_en;
    logic [7:0] expected_byte;
    wire        tx;
    wire        full;

    // DUT: UART transmitter with an 8-byte FIFO
    uart_fifo_tx_top dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .write_en(write_en),
        .tx(tx),
        .full(full)
    );

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

    // 50 MHz clock generator
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // Save signals for viewing in GTKWave
    initial begin
        $dumpfile("uart_fifo_tx_top.vcd");
        $dumpvars(0, uart_fifo_tx_top_tb);
    end

    initial begin
        // Initialize inputs and apply reset
        rst = 1;
        write_en = 1'b0;
        data_in = 8'h00;
        @(posedge clk);  // Reset is sampled on the rising edge
        @(negedge clk);  // Change inputs away from the sampling edge
        rst = 0;

        // TEST 1: WRITE AND TRANSMIT 3 BYTES
        // One branch writes to the FIFO while the other checks the serial TX output.
        fork
            begin
                // Queue AA, AB, and AC on successive clock cycles
                for (int i = 0; i < 3; i++) begin
                    @(negedge clk);
                    write_en = 1'b1;
                    data_in = 8'hAA + i;
                end
                @(negedge clk);
                write_en = 1'b0;
            end
            begin
                // Verify each UART frame in the same order the bytes were written
                for (int j = 0; j < 3; j++) begin

                    expected_byte = 8'hAA + j;

                    // Falling TX edge marks the start bit; sample at its midpoint
                    @(negedge tx);
                    #(BIT_PERIOD_NS/2);
                    check(tx, 1'b0, "Start bit");
                    // UART sends data least-significant bit first
                    for (int i = 0; i < 8; i++) begin
                        #(BIT_PERIOD_NS);
                        check(tx, expected_byte[i], $sformatf("Data bit %0d",i));
                    end
                    #(BIT_PERIOD_NS);
                    check(tx, 1'b1, "Stop bit");
                end
            end
        join
        // After all 3 frames, TX should return to idle
        #(BIT_PERIOD_NS)
        check(tx, 1'b1, "TX should be HIGH after transmission");
        check(dut.uart_busy, 1'b0, "UART should be idle");

        // TEST 2: FILL THE FIFO AND REJECT AN EXTRA BYTE
        // B0 starts transmitting first, leaving room to queue B1 through B8.
        fork
            begin
                // Start transmission of B0
                @(negedge clk);
                data_in = 8'hB0;
                write_en = 1'b1;
                @(negedge clk);
                write_en = 1'b0;
                wait (dut.uart_busy == 1'b1);

                // While B0 is being sent, fill all 8 FIFO entries
                for (int i = 0; i < 8; i++) begin
                    @(negedge clk);
                    data_in = 8'hB1 + i;
                    write_en = 1'b1;
                end
                @(negedge clk);
                write_en = 1'b0;
                check(full, 1'b1, "FIFO is full");

                // BF is the 9th queued write attempt and should be rejected
                @(negedge clk);
                data_in = 8'hBF;
                write_en = 1'b1;
                @(negedge clk);
                write_en = 1'b0;
                check(dut.fifo_inst.fifo_count, 8, "FIFO rejected extra byte");
            end
            begin
                // Verify the 9 valid frames: B0 through B8
                for (int j = 0; j < 9; j++) begin

                    expected_byte = 8'hB0 + j;

                    @(negedge tx);
                    #(BIT_PERIOD_NS/2);
                    check(tx, 1'b0, "Start bit");
                    for (int i = 0; i < 8; i++) begin
                        #(BIT_PERIOD_NS);
                        check(tx, expected_byte[i], $sformatf("Data bit %0d",i));
                    end
                    #(BIT_PERIOD_NS);
                    check(tx, 1'b1, "Stop bit");
                end

                // After B8 finishes, watch for an unwanted 10th transmission.
                // A new busy pulse means BF was transmitted; otherwise the timeout passes.
                @(negedge dut.uart_busy);
                fork
                    begin
                        @(posedge dut.uart_busy);
                        check(1'b1, 1'b0, "Unexpected 10th transmission!");
                    end
                    begin
                        #(TIMEOUT_NS);
                        check(1'b1, 1'b1, "No extra transmission!");
                    end
                join_any
                // Stop the unused monitoring branch
                disable fork;
            end
        join

        // Confirm that the UART is idle and the FIFO has drained
        #(BIT_PERIOD_NS)
        check(tx, 1'b1, "TX should be HIGH after transmission");
        check(dut.uart_busy, 1'b0, "UART should be idle");
        check(dut.fifo_empty, 1'b1, "FIFO should be empty");

        // Final test summary
        $display("\n========================");
        $display("PASSED: %0d", pass_count);
        $display("FAILED: %0d", fail_count);
        $display("========================");
        $finish;
    end

endmodule

