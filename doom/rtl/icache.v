`timescale 1ns / 1ps
// Direct-mapped instruction cache for the DDR2 region. 16-byte lines (one memory transaction).
//
// Data array: block RAM read with the NEXT fetch address (addr_next), so the line for 'pc' is at the
// RAM output during Fetch. Tags/valid bits are read asynchronously with 'pc'.
// Miss: request the line, write it, wait one cycle for the RAM to re-read it, then continue.
module icache #(
    parameter IDX = 10                  // 2**IDX lines of 16 bytes (10 -> 16 KB)
)(
    input             clk,
    input             rst,
    input      [31:0] addr_next,
    input      [31:0] pc,
    input             cached,           // pc is in the cached DDR region
    output     [31:0] instr,
    output            stall,
    // memory port (read only)
    output reg        req = 1'b0,
    output reg [26:4] req_addr = 0,
    input             ack,
    input     [127:0] ack_rdata
);
    localparam TAGW = 27 - 4 - IDX;
    localparam S_IDLE = 2'd0, S_FILL = 2'd1, S_REREAD = 2'd2;

    reg [1:0] state = S_IDLE;
    reg [TAGW-1:0] tags [0:(1<<IDX)-1];
    reg [(1<<IDX)-1:0] valid = 0;

    wire [IDX-1:0]  idx = pc[IDX+3:4];
    wire [TAGW-1:0] tag = pc[26:IDX+4];
    wire hit  = valid[idx] && (tags[idx] == tag);
    wire miss = cached & ~hit;
    assign stall = (state != S_IDLE) | miss;

    wire [127:0] line;
    reg          fill_we = 1'b0;
    sdp_ram #(.AW(IDX), .DW(128)) data_ram(
        .clk(clk), .waddr(idx), .wbe({16{fill_we}}), .wdata(ack_rdata),
        .raddr(addr_next[IDX+3:4]), .rdata(line));

    assign instr = line[32*pc[3:2] +: 32];

    always @(*) fill_we = (state == S_FILL) & ack;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; req <= 1'b0; valid <= 0;
        end else case (state)
            S_IDLE:   if (miss) begin req <= 1'b1; req_addr <= {tag, idx}; state <= S_FILL; end
            S_FILL:   if (ack) begin
                          req <= 1'b0;
                          tags[idx] <= tag; valid[idx] <= 1'b1;
                          state <= S_REREAD;
                      end
            default:  state <= S_IDLE;  // S_REREAD: RAM re-reads the new line this cycle
        endcase
    end
endmodule
