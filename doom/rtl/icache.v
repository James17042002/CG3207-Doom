`timescale 1ns / 1ps
// Direct-mapped instruction cache for the DDR2 region. 16-byte lines (one memory transaction).
//
// Data array: block RAM read with the NEXT fetch address (addr_next), so the line for 'pc' is at the
// RAM output during Fetch. Tag + valid bit live in distributed RAM, read asynchronously with 'pc';
// after reset they are cleared one line per cycle (only stalls fetches from DDR2 meanwhile).
// Miss: request the line, write it, wait one cycle for the RAM to re-read it, then continue.
module icache #(
    parameter IDX = 12                  // 2**IDX lines of 16 bytes (12 -> 64 KB)
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
    localparam S_IDLE = 2'd0, S_FILL = 2'd1, S_REREAD = 2'd2, S_INIT = 2'd3;

    reg [1:0] state = S_INIT;
    reg [IDX-1:0] init_idx = 0;
    (* ram_style = "distributed" *) reg [TAGW:0] meta [0:(1<<IDX)-1];    // {valid, tag}

    wire [IDX-1:0]  idx = pc[IDX+3:4];
    wire [TAGW-1:0] tag = pc[26:IDX+4];
    wire [TAGW:0]   m   = meta[idx];
    wire hit  = m[TAGW] && (m[TAGW-1:0] == tag);
    wire miss = cached & ~hit;
    assign stall = cached & ((state != S_IDLE) | ~hit);

    wire [127:0] line;
    reg          fill_we = 1'b0;
    sdp_ram #(.AW(IDX), .DW(128)) data_ram(
        .clk(clk), .waddr(idx), .wbe({16{fill_we}}), .wdata(ack_rdata),
        .raddr(addr_next[IDX+3:4]), .rdata(line));

    assign instr = line[32*pc[3:2] +: 32];

    always @(*) fill_we = (state == S_FILL) & ack;

    // metadata: one write port (clear during S_INIT, set on fill)
    wire            meta_we    = (state == S_INIT) | fill_we;
    wire [IDX-1:0]  meta_waddr = (state == S_INIT) ? init_idx : idx;
    wire [TAGW:0]   meta_wdata = (state == S_INIT) ? {(TAGW+1){1'b0}} : {1'b1, tag};
    always @(posedge clk) if (meta_we) meta[meta_waddr] <= meta_wdata;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_INIT; init_idx <= 0; req <= 1'b0;
        end else case (state)
            S_INIT:   begin
                          init_idx <= init_idx + 1;
                          if (&init_idx) state <= S_IDLE;
                      end
            S_IDLE:   if (miss) begin req <= 1'b1; req_addr <= {tag, idx}; state <= S_FILL; end
            S_FILL:   if (ack) begin
                          req <= 1'b0;
                          state <= S_REREAD;
                      end
            default:  state <= S_IDLE;  // S_REREAD: RAM re-reads the new line this cycle
        endcase
    end
endmodule
