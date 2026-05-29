<!--- docs/info.md — This page is shown on https://tinytapeout.com -->

## How it works

This project implements a full-duplex **8-bit UART** (Universal Asynchronous
Receiver/Transmitter) designed for the TinyTapeout GF180 1×1 tile.

The baud rate is `clk / CLKS_PER_BIT` where `CLKS_PER_BIT = 16` by default.
At 100 MHz this gives 6.25 Mbaud; at 153,600 Hz it gives standard 9,600 baud.

**Transmitter (TX)**
- Load the byte to send on `uio_in[7:0]`
- Pulse `ui_in[1]` (tx_start) HIGH for one clock cycle
- The TX FSM sends: start bit → 8 data bits (LSB first) → stop bit
- `uo_out[1]` (tx_busy) stays HIGH for the entire frame duration

**Receiver (RX)**
- Connect the incoming serial stream to `ui_in[0]` (rx)
- A 2-flip-flop synchroniser removes metastability
- The RX FSM samples at the mid-point of each bit (half-bit delay)
- Short glitches shorter than half a bit period are rejected
- On a valid frame: `uo_out[2]` (rx_valid) pulses HIGH for exactly 1 clock
- The received byte appears on `uio_out[7:0]` and `uo_out[7:3]` (lower 5 bits)

TX and RX operate **independently and simultaneously** (full duplex).

## How to test

### Simulation (CocoTB)
```bash
cd test
pip install -r requirements.txt
make SIM=icarus
```
All 14 test cases should pass covering: reset, idle line, TX patterns,
RX receive, rx_valid pulse, loopback, tx_busy flag, back-to-back TX,
glitch rejection, multiple RX bytes, and simultaneous TX+RX.

### On hardware
1. Connect a USB-UART adapter to the UART pins
2. Apply a clock at a known frequency
3. Set baud rate = clock_frequency / 16
4. Send bytes from a terminal — received data appears on `uio_out`

## External hardware

A USB-to-UART adapter (e.g. CP2102, CH340, FT232) for hardware testing.
No other external components required.
