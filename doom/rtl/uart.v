`timescale 1ns / 1ps
// 8N1 UART transmitter and receiver. CLKS_PER_BIT = clock frequency / baud rate.

module uart_tx #(parameter CLKS_PER_BIT = 54) (
    input        clk,
    input        rst,
    input  [7:0] data,
    input        valid,         // start sending 'data' (only when ready)
    output       ready,
    output reg   tx = 1'b1
);
    reg [15:0] cnt = 0;
    reg [3:0]  bitn = 0;        // 0 = idle, 1 = start, 2..9 = data, 10 = stop
    reg [7:0]  sh = 0;
    assign ready = (bitn == 0);

    always @(posedge clk) begin
        if (rst) begin
            tx <= 1'b1; bitn <= 0; cnt <= 0;
        end else if (bitn == 0) begin
            if (valid) begin
                sh <= data; bitn <= 1; cnt <= 0; tx <= 1'b0;
            end
        end else if (cnt != CLKS_PER_BIT - 1) begin
            cnt <= cnt + 1;
        end else begin
            cnt <= 0;
            if (bitn == 10) begin
                bitn <= 0;
            end else if (bitn == 9) begin
                tx <= 1'b1; bitn <= 10;
            end else begin
                tx <= sh[0]; sh <= {1'b0, sh[7:1]}; bitn <= bitn + 1;
            end
        end
    end
endmodule

module uart_rx #(parameter CLKS_PER_BIT = 54) (
    input            clk,
    input            rst,
    input            rx,
    output reg [7:0] data = 0,
    output reg       valid = 0  // one-cycle pulse per received byte
);
    reg rx1 = 1'b1, rx2 = 1'b1;  // synchroniser
    reg [15:0] cnt = 0;
    reg [3:0]  bitn = 0;         // 0 = idle, 1 = start, 2..9 = data, 10 = stop
    reg [7:0]  sh = 0;

    always @(posedge clk) begin
        rx1 <= rx; rx2 <= rx1;
        valid <= 1'b0;
        if (rst) begin
            bitn <= 0; cnt <= 0;
        end else if (bitn == 0) begin
            if (!rx2) begin bitn <= 1; cnt <= 0; end
        end else if (bitn == 1) begin
            // sample the middle of the start bit
            if (cnt == CLKS_PER_BIT/2 - 1) begin
                cnt <= 0;
                bitn <= rx2 ? 4'd0 : 4'd2;  // glitch -> back to idle
            end else cnt <= cnt + 1;
        end else if (cnt != CLKS_PER_BIT - 1) begin
            cnt <= cnt + 1;
        end else begin
            cnt <= 0;
            if (bitn == 10) begin
                bitn <= 0;
                if (rx2) begin data <= sh; valid <= 1'b1; end   // good stop bit
            end else begin
                sh <= {rx2, sh[7:1]}; bitn <= bitn + 1;
            end
        end
    end
endmodule
