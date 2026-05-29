/*
 * Copyright (c) 2026 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs: TX parallel data byte
    output wire [7:0] uo_out,   // Dedicated outputs: RX parallel data byte
    input  wire [7:0] uio_in,   // IOs: uio_in[0]=uart_rx, uio_in[1]=tx_start
    output wire [7:0] uio_out,  // IOs: status + uart_tx
    output wire [7:0] uio_oe,   // IOs: enable path, 1=output, 0=input
    input  wire       ena,      // always 1 when design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // active-low reset
);

    // UART baud setting:
    // CLKS_PER_BIT = clock frequency / baud rate
    // For easy simulation this is 16.
    // Example: for 50 MHz and 115200 baud, use 434.
    localparam [15:0] CLKS_PER_BIT = 16'd16;

    // ------------------------------------------------------------
    // Pin mapping
    // ------------------------------------------------------------
    // ui_in[7:0]  = byte to transmit
    // uo_out[7:0] = last received byte
    //
    // uio_in[0]   = UART RX serial input
    // uio_in[1]   = TX start pulse
    //
    // uio_out[2]  = UART TX serial output
    // uio_out[3]  = TX busy
    // uio_out[4]  = TX done pulse
    // uio_out[5]  = RX valid pulse
    // uio_out[6]  = RX busy
    // uio_out[7]  = frame error

    assign uio_oe  = 8'b1111_1100;  // uio[1:0] inputs, uio[7:2] outputs
    assign uo_out  = rx_data;
    assign uio_out = {frame_error, rx_busy, rx_valid, tx_done, tx_busy, uart_tx, 2'b00};

    // ------------------------------------------------------------
    // Input synchronizers
    // ------------------------------------------------------------
    reg uart_rx_meta;
    reg uart_rx_sync;

    reg tx_start_meta;
    reg tx_start_sync;
    reg tx_start_prev;

    wire tx_start_pulse;
    assign tx_start_pulse = tx_start_sync & ~tx_start_prev;

    // ------------------------------------------------------------
    // UART TX FSM
    // ------------------------------------------------------------
    localparam [1:0] TX_IDLE  = 2'd0;
    localparam [1:0] TX_START = 2'd1;
    localparam [1:0] TX_DATA  = 2'd2;
    localparam [1:0] TX_STOP  = 2'd3;

    reg [1:0]  tx_state;
    reg [15:0] tx_clk_count;
    reg [2:0]  tx_bit_index;
    reg [7:0]  tx_shift;

    reg uart_tx;
    reg tx_busy;
    reg tx_done;

    // ------------------------------------------------------------
    // UART RX FSM
    // ------------------------------------------------------------
    localparam [2:0] RX_IDLE  = 3'd0;
    localparam [2:0] RX_START = 3'd1;
    localparam [2:0] RX_DATA  = 3'd2;
    localparam [2:0] RX_STOP  = 3'd3;
    localparam [2:0] RX_CLEAN = 3'd4;

    reg [2:0]  rx_state;
    reg [15:0] rx_clk_count;
    reg [2:0]  rx_bit_index;

    reg [7:0] rx_data;
    reg rx_busy;
    reg rx_valid;
    reg frame_error;

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rx_meta  <= 1'b1;
            uart_rx_sync  <= 1'b1;

            tx_start_meta <= 1'b0;
            tx_start_sync <= 1'b0;
            tx_start_prev <= 1'b0;

            tx_state      <= TX_IDLE;
            tx_clk_count  <= 16'd0;
            tx_bit_index  <= 3'd0;
            tx_shift      <= 8'd0;
            uart_tx       <= 1'b1;
            tx_busy       <= 1'b0;
            tx_done       <= 1'b0;

            rx_state      <= RX_IDLE;
            rx_clk_count  <= 16'd0;
            rx_bit_index  <= 3'd0;
            rx_data       <= 8'd0;
            rx_busy       <= 1'b0;
            rx_valid      <= 1'b0;
            frame_error   <= 1'b0;
        end else begin
            // Synchronize external inputs
            uart_rx_meta  <= uio_in[0];
            uart_rx_sync  <= uart_rx_meta;

            tx_start_meta <= uio_in[1];
            tx_start_sync <= tx_start_meta;
            tx_start_prev <= tx_start_sync;

            // Pulse outputs are cleared every clock
            tx_done  <= 1'b0;
            rx_valid <= 1'b0;

            // ----------------------------------------------------
            // UART TRANSMITTER
            // ----------------------------------------------------
            case (tx_state)
                TX_IDLE: begin
                    uart_tx      <= 1'b1;
                    tx_busy      <= 1'b0;
                    tx_clk_count <= 16'd0;
                    tx_bit_index <= 3'd0;

                    if (tx_start_pulse) begin
                        tx_shift <= ui_in;
                        tx_busy  <= 1'b1;
                        uart_tx  <= 1'b0;     // start bit
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    tx_busy <= 1'b1;

                    if (tx_clk_count == (CLKS_PER_BIT - 16'd1)) begin
                        tx_clk_count <= 16'd0;
                        uart_tx      <= tx_shift[0];
                        tx_state     <= TX_DATA;
                    end else begin
                        tx_clk_count <= tx_clk_count + 16'd1;
                    end
                end

                TX_DATA: begin
                    tx_busy <= 1'b1;

                    if (tx_clk_count == (CLKS_PER_BIT - 16'd1)) begin
                        tx_clk_count <= 16'd0;

                        if (tx_bit_index == 3'd7) begin
                            tx_bit_index <= 3'd0;
                            uart_tx      <= 1'b1;   // stop bit
                            tx_state     <= TX_STOP;
                        end else begin
                            tx_bit_index <= tx_bit_index + 3'd1;
                            uart_tx      <= tx_shift[tx_bit_index + 3'd1];
                        end
                    end else begin
                        tx_clk_count <= tx_clk_count + 16'd1;
                    end
                end

                TX_STOP: begin
                    tx_busy <= 1'b1;

                    if (tx_clk_count == (CLKS_PER_BIT - 16'd1)) begin
                        tx_clk_count <= 16'd0;
                        tx_busy      <= 1'b0;
                        tx_done      <= 1'b1;
                        uart_tx      <= 1'b1;
                        tx_state     <= TX_IDLE;
                    end else begin
                        tx_clk_count <= tx_clk_count + 16'd1;
                    end
                end

                default: begin
                    tx_state <= TX_IDLE;
                end
            endcase

            // ----------------------------------------------------
            // UART RECEIVER
            // ----------------------------------------------------
            case (rx_state)
                RX_IDLE: begin
                    rx_busy      <= 1'b0;
                    rx_clk_count <= 16'd0;
                    rx_bit_index <= 3'd0;

                    // UART start bit detection
                    if (uart_rx_sync == 1'b0) begin
                        rx_busy     <= 1'b1;
                        frame_error <= 1'b0;
                        rx_state    <= RX_START;
                    end
                end

                RX_START: begin
                    rx_busy <= 1'b1;

                    // Sample middle of start bit
                    if (rx_clk_count == ((CLKS_PER_BIT >> 1) - 16'd1)) begin
                        if (uart_rx_sync == 1'b0) begin
                            rx_clk_count <= 16'd0;
                            rx_state     <= RX_DATA;
                        end else begin
                            rx_clk_count <= 16'd0;
                            rx_state     <= RX_IDLE;
                        end
                    end else begin
                        rx_clk_count <= rx_clk_count + 16'd1;
                    end
                end

                RX_DATA: begin
                    rx_busy <= 1'b1;

                    if (rx_clk_count == (CLKS_PER_BIT - 16'd1)) begin
                        rx_clk_count           <= 16'd0;
                        rx_data[rx_bit_index]  <= uart_rx_sync;

                        if (rx_bit_index == 3'd7) begin
                            rx_bit_index <= 3'd0;
                            rx_state     <= RX_STOP;
                        end else begin
                            rx_bit_index <= rx_bit_index + 3'd1;
                        end
                    end else begin
                        rx_clk_count <= rx_clk_count + 16'd1;
                    end
                end

                RX_STOP: begin
                    rx_busy <= 1'b1;

                    if (rx_clk_count == (CLKS_PER_BIT - 16'd1)) begin
                        rx_clk_count <= 16'd0;
                        rx_busy      <= 1'b0;
                        rx_state     <= RX_CLEAN;

                        if (uart_rx_sync == 1'b1) begin
                            rx_valid    <= 1'b1;
                            frame_error <= 1'b0;
                        end else begin
                            frame_error <= 1'b1;
                        end
                    end else begin
                        rx_clk_count <= rx_clk_count + 16'd1;
                    end
                end

                RX_CLEAN: begin
                    rx_state <= RX_IDLE;
                end

                default: begin
                    rx_state <= RX_IDLE;
                end
            endcase
        end
    end

    // Unused inputs to avoid warnings
    wire _unused = &{ena, uio_in[7:2], 1'b0};

endmodule

`default_nettype wirevv
