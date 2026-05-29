/*
 * tb.v  —  Verilog testbench wrapper for CocoTB
 * TinyTapeout GF180  UART  1×1
 *
 * This file is the thin Verilog adapter that CocoTB drives.
 * All real test logic lives in test.py.
 */

`default_nettype none
`timescale 1ns/1ps

module tb ();

    // ── Clock & Reset ───────────────────────────────────────
    reg clk;
    reg rst_n;
    reg ena;

    // ── DUT ports ───────────────────────────────────────────
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // ── Initial conditions ──────────────────────────────────
    initial begin
        clk    = 1'b0;
        rst_n  = 1'b0;
        ena    = 1'b1;
        ui_in  = 8'h00;
        uio_in = 8'h00;
    end

    // ── Clock: 10 ns period → 100 MHz  ─────────────────────
    // (CocoTB will override the clock if needed)
    always #5 clk = ~clk;

    // ── VCD dump for GTKWave ────────────────────────────────
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
    end

    // ── DUT instantiation ───────────────────────────────────
    tt_um_uart #(
        .CLKS_PER_BIT(16)    // baud = clk/16  (matches test.py)
    ) dut (
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe),
        .ena    (ena),
        .clk    (clk),
        .rst_n  (rst_n)
    );

endmodule
