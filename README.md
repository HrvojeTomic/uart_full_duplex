# Full-Duplex UART with FIFOs

I designed a full-duplex UART in SystemVerilog. It can transmit and receive 8-bit data at the same time. I added a FIFO on each side so bytes can be stored while the UART is busy.

The project was tested with Icarus Verilog and synthesized with Yosys. It has **not** been tested on an FPGA board.

## Design settings

| Setting | Value |
| --- | --- |
| System clock | 50 MHz |
| Baud rate | 115200 |
| UART format | 8 data bits, no parity, 1 stop bit (8N1) |
| TX FIFO | 8 entries, 8 bits each |
| RX FIFO | 8 entries, 9 bits each |
| Reset | Active-high, synchronous |

Each UART frame contains a start bit (`0`), eight data bits sent least-significant bit first, and a stop bit (`1`). With a 50 MHz clock, each bit takes 434 clock cycles in this design.

## How it works

```text
Data in --> TX FIFO --> TX controller --> UART TX --> tx

rx --> UART RX --> RX FIFO --> Data out + framing error
```

The TX and RX paths work independently. The top module connects them together and shares the clock and reset.

The RX FIFO stores 9 bits per entry: 8 data bits and 1 framing-error bit. The top module separates those outputs when a byte is read.

## RTL files

| File | Purpose |
| --- | --- |
| `rtl/fifo.sv` | Eight-entry synchronous FIFO used by TX and RX |
| `rtl/uart_tx.sv` | Sends the start bit, data bits, and stop bit |
| `rtl/uart_rx.sv` | Receives UART frames and checks the stop bit |
| `rtl/uart_fifo_tx_top.sv` | Reads bytes from the TX FIFO and starts transmission |
| `rtl/uart_rx_fifo_top.sv` | Stores received data and detects FIFO overrun |
| `rtl/uart_top.sv` | Connects the TX and RX sides |

The transmitter, receiver, and TX FIFO controller use state machines. The RX input also goes through a two-flip-flop synchronizer before the receiver processes it.

## Important signals

The TX side uses `data_in`, `write_en`, `tx`, and `tx_full`. The RX side uses `rx`, `read_en`, `data_out`, `framing_error`, `rx_busy`, `rx_full`, `rx_empty`, and `overrun_error`.

`framing_error` marks a byte whose stop bit was incorrect. `overrun_error` goes high for one clock cycle if a new received byte arrives while the RX FIFO is full. The FIFO does not store that extra byte.

## Testing

I wrote a top-level testbench (`tb/uart_top_tb.sv`) that checks:

1. Reset conditions
2. Sending one byte
3. Receiving one byte
4. Sending and receiving at the same time
5. Multiple-byte full-duplex communication
6. Framing-error detection
7. RX FIFO overrun
8. TX FIFO full condition
9. Reset during active communication
10. Communication after reset

**Final simulation result: 226 passed, 0 failed.**

To compile and run the testbench from the project folder:

```bash
iverilog -g2012 -s uart_top_tb -o uart_top_sim rtl/*.sv tb/uart_top_tb.sv
vvp uart_top_sim
```

To view the waveform:

```bash
gtkwave uart_top.vcd
```

## Synthesis

I used Yosys to check and synthesize the complete design:

```bash
yosys -l uart_synthesis.log -p 'read_verilog -sv rtl/*.sv; synth -top uart_top; stat'
```

The synthesis completed successfully with `uart_top` as the top-level module. The results were:

| Resource | Count |
| --- | ---: |
| Total generic cells | 669 |
| Flip-flops | 234 |
| Multiplexers | 127 |
| Wires | 485 |
| Wire bits | 836 |

Both FIFOs were synthesized into registers and logic, and no latch cells were reported. An earlier Yosys structural check reported **0 problems**.

The complete synthesis statistics are in [`synthesis_summary.txt`](synthesis_summary.txt). The design has not been tested on an FPGA, so FPGA resource usage and timing have not been verified.

## What I learned / next steps

This project helped me practice writing FSMs, working with FIFOs, using nonblocking assignments, and testing multiple hardware operations at once with `fork...join`.

The design works in the tests I ran, but I have not programmed it onto an FPGA or performed FPGA timing analysis. Those would be the next steps if I continue the project.
