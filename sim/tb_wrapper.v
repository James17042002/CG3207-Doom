`timescale 1ns / 1ps
// Command-line testbench for Wrapper + RV (Icarus Verilog / Verilator --timing).
//
// Behaviour:
//   - UART TX is always ready; every byte the program sends is printed to stdout.
//   - LED, seven-segment and OLED writes are logged (use +quiet to silence them).
//   - A store to the sim-only address SIM_EXIT_ADDR ends the simulation.
//     The stored value is the exit code: 0 = pass, anything else = fail.
//     On real hardware this address is just an unused MMIO slot (ignored).
//   - Stops after +cycles=N cycles (default 200000) if the program never exits.
//
// Plusargs: +cycles=N  +dip=HEX  +pb=HEX  +quiet  +trace (prints PC every cycle)
module tb_wrapper;
    localparam [31:0] SIM_EXIT_ADDR = 32'hFFFF00FC;

    reg  [15:0] DIP = 16'h0;
    reg  [2:0]  PB  = 3'h0;
    wire [7:0]  LED_OUT;
    wire [6:0]  LED_PC;
    wire [31:0] SEVENSEGHEX;
    wire [7:0]  UART_TX;
    reg         UART_TX_ready = 1'b1;
    wire        UART_TX_valid;
    reg  [7:0]  UART_RX = 8'h0;
    reg         UART_RX_valid = 1'b0;
    wire        UART_RX_ack;
    wire        OLED_Write;
    wire [6:0]  OLED_Col;
    wire [5:0]  OLED_Row;
    wire [23:0] OLED_Data;
    reg  [31:0] ACCEL_Data = 32'h0;
    reg         ACCEL_DReady = 1'b0;
    reg         RESET = 1'b1;
    reg         CLK = 1'b0;

    Wrapper dut(DIP, PB, LED_OUT, LED_PC, SEVENSEGHEX, UART_TX, UART_TX_ready, UART_TX_valid,
                UART_RX, UART_RX_valid, UART_RX_ack, OLED_Write, OLED_Col, OLED_Row, OLED_Data,
                ACCEL_Data, ACCEL_DReady, RESET, CLK);

    always #5 CLK = ~CLK;   // 100 MHz nominal; only cycle counts matter here

    integer max_cycles;
    integer cycle = 0;
    integer oled_writes = 0;
    reg quiet, trace;
    reg [7:0]  last_led = 8'h0;
    reg [31:0] last_7seg = 32'h0;

    initial begin
        if (!$value$plusargs("cycles=%d", max_cycles)) max_cycles = 200000;
        if ($value$plusargs("dip=%h", DIP)) ;
        if ($value$plusargs("pb=%h", PB)) ;
        quiet = $test$plusargs("quiet");
        trace = $test$plusargs("trace");
        repeat (3) @(posedge CLK);
        RESET = 1'b0;
    end

    always @(posedge CLK) begin
        if (!RESET) begin
            cycle = cycle + 1;
            if (trace) $display("[%0d] PC=%08h", cycle, dut.PC);

            // Program-controlled exit
            if (|dut.MemWrite_out && dut.ALUResult == SIM_EXIT_ADDR) begin
                $display("");
                if (dut.WriteData_out == 0)
                    $display("SIM PASS after %0d cycles", cycle);
                else
                    $display("SIM FAIL: exit code %0d (0x%08h) after %0d cycles",
                             dut.WriteData_out, dut.WriteData_out, cycle);
                $finish;
            end

            if (cycle >= max_cycles) begin
                $display("");
                $display("SIM TIMEOUT after %0d cycles (PC=%08h)", cycle, dut.PC);
                $finish;
            end
        end
    end

    // Peripheral logging
    always @(posedge CLK) begin
        if (UART_TX_valid) begin
            $write("%c", UART_TX);
            $fflush;
        end
        if (!quiet && LED_OUT !== last_led) begin
            $display("[%0d] LED = %02h", cycle, LED_OUT);
            last_led = LED_OUT;
        end
        if (!quiet && SEVENSEGHEX !== last_7seg) begin
            $display("[%0d] 7SEG = %08h", cycle, SEVENSEGHEX);
            last_7seg = SEVENSEGHEX;
        end
        if (OLED_Write) oled_writes = oled_writes + 1;
    end

    // UART RX acknowledgement handshake (no input source yet)
    always @(posedge CLK) if (UART_RX_ack) UART_RX_valid <= 1'b0;
endmodule
