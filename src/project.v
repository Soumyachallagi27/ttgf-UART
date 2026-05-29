/*
 * UART for Tiny Tapeout GF180  —  1×1 tile (160 × 100 µm)
 * ──────────────────────────────────────────────────────────
 * Pin map  (all TT standard)
 *
 *  ui_in[0]   = rx          — serial data IN
 *  ui_in[7:1] = unused (tie low)
 *
 *  uo_out[0]  = tx          — serial data OUT
 *  uo_out[1]  = tx_busy     — HIGH while transmitting
 *  uo_out[2]  = rx_valid    — pulses HIGH for 1 clk when byte ready
 *  uo_out[7:3]= rx_data[4:0]— lower 5 bits of received byte
 *
 *  uio_in[7:0]= tx_data     — byte to send (latched on tx_start)
 *  uio_out[7:0]= rx_data    — last received byte (full 8 bits)
 *  uio_oe     = 8'hFF       — bidir pins are outputs
 *
 *  clk        = system clock (use 9600×16 = 153600 Hz, or set
 *               CLKS_PER_BIT parameter below for your clock)
 *  rst_n      = active-low async reset
 *  ena        = module enable (from TT harness, keep HIGH)
 *
 *  To transmit: put byte on uio_in, assert ui_in[1] (tx_start)
 *               for at least 1 clock cycle.
 *
 * Baud = clk / CLKS_PER_BIT
 * Default: CLKS_PER_BIT=16  →  baud = clk/16
 * For 9600 baud @ 25 MHz:   CLKS_PER_BIT = 2604
 * For 9600 baud @ 10 MHz:   CLKS_PER_BIT = 1042
 * For 9600 baud @ 153600 Hz: CLKS_PER_BIT = 16  (demo default)
 */

`default_nettype none
`timescale 1ns/1ps

module tt_um_uart #(
    parameter CLKS_PER_BIT = 16   // adjust for your clock & baud
)(
    input  wire [7:0] ui_in,      // dedicated inputs
    output wire [7:0] uo_out,     // dedicated outputs
    input  wire [7:0] uio_in,     // bidir IOs — input path
    output wire [7:0] uio_out,    // bidir IOs — output path
    output wire [7:0] uio_oe,     // bidir IO enable (1=output)
    input  wire       ena,        // design enable
    input  wire       clk,        // clock
    input  wire       rst_n       // reset, active low
);

    // ── Port aliases ────────────────────────────────────────
    wire       rx       = ui_in[0];
    wire       tx_start = ui_in[1];   // 1-cycle pulse to start TX
    wire [7:0] tx_data  = uio_in;     // byte to transmit

    wire       tx;
    wire       tx_busy;
    wire       rx_valid;
    wire [7:0] rx_data;

    // ── Outputs ─────────────────────────────────────────────
    assign uo_out[0]   = tx;
    assign uo_out[1]   = tx_busy;
    assign uo_out[2]   = rx_valid;
    assign uo_out[7:3] = rx_data[4:0];

    assign uio_out     = rx_data;     // full received byte
    assign uio_oe      = 8'hFF;       // all bidir pins = output

    // ────────────────────────────────────────────────────────
    //  UART TRANSMITTER
    // ────────────────────────────────────────────────────────
    reg [3:0]  tx_state;
    reg [12:0] tx_clk_cnt;
    reg [7:0]  tx_shift;
    reg [2:0]  tx_bit_cnt;
    reg        tx_reg;
    reg        tx_busy_reg;

    localparam TX_IDLE  = 4'd0,
               TX_START = 4'd1,
               TX_DATA  = 4'd2,
               TX_STOP  = 4'd3;

    assign tx      = tx_reg;
    assign tx_busy = tx_busy_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            tx_clk_cnt <= 0;
            tx_shift   <= 8'h00;
            tx_bit_cnt <= 0;
            tx_reg     <= 1'b1;       // idle HIGH
            tx_busy_reg<= 1'b0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_reg      <= 1'b1;
                    tx_busy_reg <= 1'b0;
                    tx_clk_cnt  <= 0;
                    tx_bit_cnt  <= 0;
                    if (tx_start && !tx_busy_reg) begin
                        tx_shift    <= tx_data;
                        tx_busy_reg <= 1'b1;
                        tx_state    <= TX_START;
                    end
                end

                TX_START: begin
                    tx_reg <= 1'b0;   // start bit
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        tx_state   <= TX_DATA;
                    end else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                end

                TX_DATA: begin
                    tx_reg <= tx_shift[0];
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        tx_shift   <= {1'b0, tx_shift[7:1]};
                        if (tx_bit_cnt == 7) begin
                            tx_bit_cnt <= 0;
                            tx_state   <= TX_STOP;
                        end else
                            tx_bit_cnt <= tx_bit_cnt + 1;
                    end else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                end

                TX_STOP: begin
                    tx_reg <= 1'b1;   // stop bit
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt  <= 0;
                        tx_busy_reg <= 1'b0;
                        tx_state    <= TX_IDLE;
                    end else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // ────────────────────────────────────────────────────────
    //  UART RECEIVER
    // ────────────────────────────────────────────────────────
    reg [3:0]  rx_state;
    reg [12:0] rx_clk_cnt;
    reg [7:0]  rx_shift;
    reg [2:0]  rx_bit_cnt;
    reg [7:0]  rx_data_reg;
    reg        rx_valid_reg;

    localparam RX_IDLE  = 4'd0,
               RX_START = 4'd1,
               RX_DATA  = 4'd2,
               RX_STOP  = 4'd3;

    assign rx_valid = rx_valid_reg;
    assign rx_data  = rx_data_reg;

    // 2-FF synchroniser for RX input (metastability protection)
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end
    wire rx_in = rx_sync2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state    <= RX_IDLE;
            rx_clk_cnt  <= 0;
            rx_shift    <= 8'h00;
            rx_bit_cnt  <= 0;
            rx_data_reg <= 8'h00;
            rx_valid_reg<= 1'b0;
        end else begin
            rx_valid_reg <= 1'b0;   // default: pulse low every cycle

            case (rx_state)
                RX_IDLE: begin
                    rx_clk_cnt <= 0;
                    rx_bit_cnt <= 0;
                    if (rx_in == 1'b0)        // start bit detected
                        rx_state <= RX_START;
                end

                RX_START: begin
                    // sample at middle of start bit
                    if (rx_clk_cnt == (CLKS_PER_BIT/2) - 1) begin
                        if (rx_in == 1'b0) begin  // still low → valid
                            rx_clk_cnt <= 0;
                            rx_state   <= RX_DATA;
                        end else begin             // glitch → back to idle
                            rx_state   <= RX_IDLE;
                        end
                    end else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                end

                RX_DATA: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 0;
                        rx_shift   <= {rx_in, rx_shift[7:1]};
                        if (rx_bit_cnt == 7) begin
                            rx_bit_cnt <= 0;
                            rx_state   <= RX_STOP;
                        end else
                            rx_bit_cnt <= rx_bit_cnt + 1;
                    end else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                end

                RX_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt   <= 0;
                        if (rx_in == 1'b1) begin  // valid stop bit
                            rx_data_reg  <= rx_shift;
                            rx_valid_reg <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else
                        rx_clk_cnt <= rx_clk_cnt + 1;
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule
