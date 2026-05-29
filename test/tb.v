`timescale 1ns/1ps

// ============================================================
// TESTBENCH FOR 4-BIT UART TRANSMITTER
// ============================================================

module uart4_tx_tb;

    // ========================================================
    // Testbench Signals
    // ========================================================
    reg        clk;
    reg        rst_n;
    reg        tx_start;
    reg [3:0]  tx_data;

    wire       tx;
    wire       tx_busy;

    // ========================================================
    // DUT INSTANTIATION
    // ========================================================
    uart4_tx uut (

        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),

        .tx(tx),
        .tx_busy(tx_busy)

    );

    // ========================================================
    // CLOCK GENERATION
    // ========================================================
    initial
    begin
        clk = 0;

        forever #5 clk = ~clk;
    end

    // ========================================================
    // TEST SEQUENCE
    // ========================================================
    initial
    begin

        // Initial values
        rst_n    = 0;
        tx_start = 0;
        tx_data  = 4'b1010;

        // Apply reset
        #20;
        rst_n = 1;

        // Start transmission
        #20;
        tx_start = 1;

        #10;
        tx_start = 0;

        // Wait for transmission
        #1000;

        $finish;

    end

    // ========================================================
    // WAVEFORM DUMP
    // ========================================================
    initial
    begin

        $dumpfile("uart4_tx.vcd");
        $dumpvars(0, uart4_tx_tb);

    end

endmodule
