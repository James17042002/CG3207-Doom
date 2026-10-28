`timescale 1ns / 1ps
// Simple dual-port RAM: one write port with byte enables, one synchronous read port.
// Read-during-write to the same address returns the OLD data (read-first); callers bypass.
// Infers block RAM in Vivado.
module sdp_ram #(
    parameter AW   = 10,            // address bits (depth = 2**AW)
    parameter DW   = 32,            // data width, multiple of 8
    parameter INIT = ""             // optional $readmemh file
)(
    input                 clk,
    input  [AW-1:0]       waddr,
    input  [DW/8-1:0]     wbe,
    input  [DW-1:0]       wdata,
    input  [AW-1:0]       raddr,
    output reg [DW-1:0]   rdata
);
    (* ram_style = "block" *) reg [DW-1:0] mem [0:(1<<AW)-1];

    integer k;
    initial begin
        for (k = 0; k < (1<<AW); k = k + 1) mem[k] = {DW{1'b0}};
        if (INIT != "") $readmemh(INIT, mem);
    end

    genvar b;
    generate
        for (b = 0; b < DW/8; b = b + 1) begin : g_byte
            always @(posedge clk)
                if (wbe[b]) mem[waddr][b*8 +: 8] <= wdata[b*8 +: 8];
        end
    endgenerate

    always @(posedge clk)
        rdata <= mem[raddr];
endmodule
