`default_nettype none
`timescale 1ns/1ps

// ============================================================
// 4-BIT UART TRANSMITTER
// Tiny Tapeout Mini Project
// ============================================================

module uart4_tx (

    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [3:0] tx_data,

    output reg        tx,
    output reg        tx_busy
);

    // ========================================================
    // Parameters
    // ========================================================
    parameter CLKS_PER_BIT = 16;

    // ========================================================
    // Registers
    // ========================================================
    reg [1:0] state;
    reg [3:0] shift_reg;
    reg [4:0] clk_count;
    reg [1:0] bit_index;

    // ========================================================
    // FSM States
    // ========================================================
    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    // ========================================================
    // UART TX Logic
    // ========================================================
    always @(posedge clk or negedge rst_n)
    begin

        if(!rst_n)
        begin
            state      <= IDLE;
            shift_reg  <= 4'b0000;
            clk_count  <= 0;
            bit_index  <= 0;
            tx         <= 1'b1;
            tx_busy    <= 1'b0;
        end

        else
        begin

            case(state)

                // ============================================
                // IDLE STATE
                // ============================================
                IDLE:
                begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;

                    if(tx_start)
                    begin
                        shift_reg <= tx_data;
                        clk_count <= 0;
                        bit_index <= 0;
                        tx_busy <= 1'b1;
                        state <= START;
                    end
                end

                // ============================================
                // START BIT
                // ============================================
                START:
                begin
                    tx <= 1'b0;

                    if(clk_count < CLKS_PER_BIT-1)
                        clk_count <= clk_count + 1;
                    else
                    begin
                        clk_count <= 0;
                        state <= DATA;
                    end
                end

                // ============================================
                // DATA BITS
                // ============================================
                DATA:
                begin
                    tx <= shift_reg[0];

                    if(clk_count < CLKS_PER_BIT-1)
                        clk_count <= clk_count + 1;
                    else
                    begin
                        clk_count <= 0;
                        shift_reg <= shift_reg >> 1;

                        if(bit_index < 3)
                            bit_index <= bit_index + 1;
                        else
                        begin
                            bit_index <= 0;
                            state <= STOP;
                        end
                    end
                end

                // ============================================
                // STOP BIT
                // ============================================
                STOP:
                begin
                    tx <= 1'b1;

                    if(clk_count < CLKS_PER_BIT-1)
                        clk_count <= clk_count + 1;
                    else
                    begin
                        clk_count <= 0;
                        tx_busy <= 1'b0;
                        state <= IDLE;
                    end
                end

            endcase

        end

    end

endmodule
