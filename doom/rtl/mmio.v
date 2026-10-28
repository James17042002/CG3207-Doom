`timescale 1ns / 1ps
// Memory-mapped peripherals at 0xFFFF0000 (offsets as in Wrapper.v, plus new ones).
//
//  0x00 UART_RX_VALID  RO  1 if a received byte is waiting (RX FIFO not empty)
//  0x04 UART_RX        RO  next received byte (reading removes it from the FIFO)
//  0x08 UART_TX_READY  RO  bit 0: a byte can be written to UART_TX (TX FIFO not full)
//                          bit 1: everything has been sent (FIFO empty, transmitter idle)
//  0x0C UART_TX        WO  byte to send
//  0x20 OLED_COL       WO  \
//  0x24 OLED_ROW       WO   | same behaviour as Wrapper.v
//  0x28 OLED_DATA      WO   |
//  0x2C OLED_CTRL      WO  /
//  0x40 ACCEL_DATA     RO  (not connected, reads 0)
//  0x44 ACCEL_DREADY   RO  (reads 0)
//  0x60 LED            WO  LED[15:0]
//  0x64 DIP            RO  switches[15:0]
//  0x68 PB             RO  buttons {BTND, BTNU, BTNR, BTNC, BTNL} = bits [4:0]
//  0x80 SEVENSEG       WO  8 hex digits
//  0xA0 CYCLECOUNT     RO  clock cycles since reset (32-bit, wraps)
//  0xA4 TIMER_MS       RO  milliseconds since reset
//  0xA8 TIMER_US       RO  microseconds since reset (wraps every ~71 minutes)
//  0xAC DDR_READY      RO  1 once the DDR2 controller has finished calibration
//  0xFC SIM_EXIT       WO  simulation only: ends the testbench (value = exit code)
//
// Writes and FIFO pops take effect only on the cycle the Memory-stage instruction advances.
module mmio #(
    parameter CLK_FREQ_HZ = 50000000,
    parameter BAUD        = 921600
)(
    input             clk,
    input             rst,
    input             hold,
    input             sel,          // access in Memory targets the MMIO region
    input      [7:0]  addr,         // offset within the MMIO page
    input             re,
    input      [3:0]  be,
    input      [31:0] wdata,
    output reg [31:0] rdata,
    input             calib_done,   // DDR2 controller ready

    input      [15:0] dip,
    input      [4:0]  pb,
    output reg [15:0] led = 16'h0,
    output reg [31:0] sevenseg = 32'h0,
    input             uart_rxd,
    output            uart_txd,
    output reg        oled_write = 1'b0,
    output reg [6:0]  oled_col = 7'd0,
    output reg [5:0]  oled_row = 6'd0,
    output reg [23:0] oled_data = 24'd0,
    output reg        sim_exit = 1'b0,
    output reg [31:0] sim_exit_code = 32'd0
);
    localparam CLKS_PER_BIT = CLK_FREQ_HZ / BAUD;

    wire wr  = sel & (|be) & ~hold;     // performed exactly once
    wire rd  = sel & re & ~hold;
    wire wr0 = sel & be[0] & ~hold;     // byte-0 writes (as in Wrapper.v)
    wire [7:0] a = {addr[7:2], 2'b00};

    // ---------------- Timers ----------------
    reg [31:0] cycle_count = 0, ms = 0, us = 0;
    reg [31:0] us_div = 0, ms_div = 0;
    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0; ms <= 0; us <= 0; us_div <= 0; ms_div <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (us_div == CLK_FREQ_HZ/1000000 - 1) begin us_div <= 0; us <= us + 1; end
            else us_div <= us_div + 1;
            if (ms_div == CLK_FREQ_HZ/1000 - 1) begin ms_div <= 0; ms <= ms + 1; end
            else ms_div <= ms_div + 1;
        end
    end

    // ---------------- UART with FIFOs ----------------
    wire [7:0] rx_byte; wire rx_valid;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx(.clk(clk), .rst(rst), .rx(uart_rxd), .data(rx_byte), .valid(rx_valid));

    reg [7:0] rxq [0:255];
    reg [7:0] rx_wp = 0, rx_rp = 0;
    wire rx_empty = (rx_wp == rx_rp);
    wire rx_full  = (rx_wp + 8'd1 == rx_rp);
    wire rx_pop   = rd & (a == 8'h04) & ~rx_empty;
    always @(posedge clk) begin
        if (rst) begin rx_wp <= 0; rx_rp <= 0; end
        else begin
            if (rx_valid & ~rx_full) begin rxq[rx_wp] <= rx_byte; rx_wp <= rx_wp + 1; end
            if (rx_pop) rx_rp <= rx_rp + 1;
        end
    end

    reg [7:0] txq [0:255];
    reg [7:0] tx_wp = 0, tx_rp = 0;
    wire tx_empty = (tx_wp == tx_rp);
    wire tx_full  = (tx_wp + 8'd1 == tx_rp);
    wire tx_ready;
    wire tx_start = ~tx_empty & tx_ready;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx(.clk(clk), .rst(rst), .data(txq[tx_rp]), .valid(tx_start),
                                                .ready(tx_ready), .tx(uart_txd));
    always @(posedge clk) begin
        if (rst) begin tx_wp <= 0; tx_rp <= 0; end
        else begin
            if (wr0 & (a == 8'h0C) & ~tx_full) begin txq[tx_wp] <= wdata[7:0]; tx_wp <= tx_wp + 1; end
            if (tx_start) tx_rp <= tx_rp + 1;
        end
    end

    // ---------------- Read mux ----------------
    always @(*) begin
        case (a)
            8'h00: rdata = {31'd0, ~rx_empty};
            8'h04: rdata = {24'd0, rxq[rx_rp]};
            8'h08: rdata = {30'd0, tx_empty & tx_ready, ~tx_full};
            8'h64: rdata = {16'd0, dip};
            8'h68: rdata = {27'd0, pb};
            8'hA0: rdata = cycle_count;
            8'hA4: rdata = ms;
            8'hA8: rdata = us;
            8'hAC: rdata = {31'd0, calib_done};
            default: rdata = 32'd0;
        endcase
    end

    // ---------------- LEDs, 7-segment, sim exit ----------------
    integer j;
    always @(posedge clk) begin
        sim_exit <= 1'b0;
        if (rst) begin
            led <= 0; sevenseg <= 0;
        end else begin
            if (wr & (a == 8'h60)) begin
                if (be[0]) led[7:0]  <= wdata[7:0];
                if (be[1]) led[15:8] <= wdata[15:8];
            end
            if (wr & (a == 8'h80))
                for (j = 0; j < 4; j = j + 1)
                    if (be[j]) sevenseg[j*8 +: 8] <= wdata[j*8 +: 8];
            if (wr & (a == 8'hFC)) begin sim_exit <= 1'b1; sim_exit_code <= wdata; end
        end
    end

    // ---------------- OLED (same behaviour as Wrapper.v) ----------------
    // OLED_CTRL[3:0]: 0000 vary pixel data, 0001 vary col, 0010 vary row,
    //                 0100 auto-advance col (row major), 0101 auto-advance row (column major)
    // OLED_CTRL[7:4]: 0000 8-bit colour, 0001 16-bit colour (RGB565), 0010 24-bit colour
    wire dec_col  = (a == 8'h20), dec_row = (a == 8'h24), dec_data = (a == 8'h28), dec_ctrl = (a == 8'h2C);
    reg [7:0] oled_ctrl = 8'd0;
    reg autoadvance_row = 1'b0, autoadvance_col = 1'b0;
    always @(posedge clk) begin
        oled_write <= 1'b0;
        case (oled_ctrl[3:0])
            4'b0001: if (wr0 & dec_col) begin oled_write <= 1'b1; autoadvance_row <= 1'b0; autoadvance_col <= 1'b0; end
            4'b0010: if (wr0 & dec_row) begin oled_write <= 1'b1; autoadvance_row <= 1'b0; autoadvance_col <= 1'b0; end
            4'b0100: if (wr0 & dec_data) begin
                         oled_write <= 1'b1; autoadvance_row <= 1'b0; autoadvance_col <= 1'b1;
                         if (autoadvance_col) begin
                             if (oled_col >= 95) begin
                                 oled_col <= 7'd0;
                                 oled_row <= (oled_row == 63) ? 6'd0 : oled_row + 1;
                             end else oled_col <= oled_col + 1;
                         end
                     end
            4'b0101: if (wr0 & dec_data) begin
                         oled_write <= 1'b1; autoadvance_row <= 1'b1; autoadvance_col <= 1'b0;
                         if (autoadvance_row) begin
                             if (oled_row == 63) begin
                                 oled_row <= 6'd0;
                                 oled_col <= (oled_col >= 95) ? 7'd0 : oled_col + 1;
                             end else oled_row <= oled_row + 1;
                         end
                     end
            default: if (wr & dec_data) begin oled_write <= 1'b1; autoadvance_row <= 1'b0; autoadvance_col <= 1'b0; end
        endcase

        case (oled_ctrl[7:4])
            4'b0001: if (wr & be[1] & be[0] & dec_data)
                         oled_data <= {wdata[15:11], 3'd0, wdata[10:5], 2'd0, wdata[4:0], 3'd0};
            4'b0010: begin
                         if (wr & be[2] & dec_data) oled_data[23:16] <= wdata[23:16];
                         if (wr & be[1] & dec_data) oled_data[15:8]  <= wdata[15:8];
                         if (wr0 & dec_data)        oled_data[7:0]   <= wdata[7:0];
                     end
            default: if (wr0 & dec_data)
                         oled_data <= {wdata[7:5], 5'd0, wdata[4:2], 5'd0, wdata[1:0], 6'd0};
        endcase

        if (wr0 & dec_ctrl) oled_ctrl <= wdata[7:0];
        if (wr0 & dec_row)  oled_row  <= wdata[5:0];
        if (wr0 & dec_col)  oled_col  <= wdata[6:0];
    end
endmodule
