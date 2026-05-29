//==============================================================
// Project : Tiny Tapeout UART Baud Generator (4-bit Version)
// Top Module : tt_um_uart_baud_gen
// Description:
// Generates baud tick pulse using 4-bit counter
// Suitable for Tiny Tapeout style mini ASIC project
//==============================================================

module tt_um_uart_baud_gen (
    input  wire clk,        // system clock
    input  wire rst_n,      // active low reset
    output reg  baud_tick   // baud pulse output
);

    // 4-bit counter
    reg [3:0] counter;

    //==========================================================
    // Counter Logic
    //==========================================================
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            counter   <= 4'b0000;
            baud_tick <= 1'b0;
        end
        else
        begin
            // Divide clock by 16
            if (counter == 4'b1111)
            begin
                counter   <= 4'b0000;
                baud_tick <= 1'b1;
            end
            else
            begin
                counter   <= counter + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end

endmodule
