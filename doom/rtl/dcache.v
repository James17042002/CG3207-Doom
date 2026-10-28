`timescale 1ns / 1ps
// Direct-mapped, write-back, write-allocate data cache for the DDR2 region, plus uncached
// accesses to the same memory through an alias region. 16-byte lines (one memory transaction).
//
// Data array: block RAM read with the Execute-stage address (or the Memory-stage address while the
// pipeline is held), so the line is at the RAM output when the access reaches Memory.
// Stores write the RAM in Memory on the cycle the instruction advances; a store immediately
// followed by a load of the same word is handled by a bypass register (the RAM is read-first).
module dcache #(
    parameter IDX = 10                  // 2**IDX lines of 16 bytes (10 -> 16 KB)
)(
    input             clk,
    input             rst,
    input             hold,             // pipeline frozen this cycle
    input      [31:0] addr_e,
    input      [31:0] addr_m,
    input             cached_m,         // Memory-stage access is to the cached DDR region
    input             uncached_m,       // Memory-stage access is to the uncached DDR alias
    input             re_m,
    input      [3:0]  be_m,             // store byte enables (0 = not a store)
    input      [31:0] wdata_m,          // store data (replicated across lanes by the core)
    output     [31:0] rdata_m,
    output            stall,
    // memory port
    output reg        req = 1'b0,
    output reg        req_we = 1'b0,
    output reg [26:4] req_addr = 0,
    output reg [127:0] req_wdata = 0,
    output reg [15:0] req_wmask = 0,    // 1 = write this byte
    input             ack,
    input     [127:0] ack_rdata
);
    localparam TAGW = 27 - 4 - IDX;
    localparam S_IDLE = 3'd0, S_VICTIM = 3'd1, S_WB = 3'd2, S_FILL = 3'd3, S_REREAD = 3'd4, S_UNC = 3'd5;

    reg [2:0] state = S_IDLE;
    reg [TAGW-1:0] tags [0:(1<<IDX)-1];
    reg [(1<<IDX)-1:0] valid = 0, dirty = 0;

    wire we_m   = |be_m;
    wire access = re_m | we_m;
    wire [IDX-1:0]  idx = addr_m[IDX+3:4];
    wire [TAGW-1:0] tag = addr_m[26:IDX+4];
    wire [1:0]      wsel = addr_m[3:2];
    wire hit  = valid[idx] && (tags[idx] == tag);
    wire miss = cached_m & access & ~hit;

    // Uncached access: done once, result held until the instruction leaves Memory
    reg        unc_done = 1'b0;
    reg [31:0] unc_rdata = 0;
    wire unc_pending = uncached_m & access & ~unc_done;

    assign stall = (state != S_IDLE) | miss | unc_pending;

    // ---------------- Data array ----------------
    wire [127:0] line;
    reg  [15:0]  ram_wbe;
    reg  [127:0] ram_wdata;
    wire [IDX-1:0] raddr = hold ? idx : addr_e[IDX+3:4];
    sdp_ram #(.AW(IDX), .DW(128)) data_ram(
        .clk(clk), .waddr(idx), .wbe(ram_wbe), .wdata(ram_wdata), .raddr(raddr), .rdata(line));

    wire store_hit = (state == S_IDLE) & cached_m & we_m & hit & ~hold;
    always @(*) begin
        if (state == S_FILL && ack) begin
            ram_wbe = 16'hFFFF; ram_wdata = ack_rdata;
        end else if (store_hit) begin
            ram_wbe = {12'd0, be_m} << (4*wsel); ram_wdata = {4{wdata_m}};
        end else begin
            ram_wbe = 16'd0; ram_wdata = {4{wdata_m}};
        end
    end

    // Store -> load bypass (RAM read-first on the cycle of the write)
    reg        byp_valid = 1'b0;
    reg [29:0] byp_addr = 0;
    reg [3:0]  byp_be = 0;
    reg [31:0] byp_data = 0;
    wire [31:0] raw_word = line[32*wsel +: 32];
    wire byp_hit = byp_valid && (byp_addr == addr_m[31:2]);
    wire [31:0] cached_word = {byp_hit & byp_be[3] ? byp_data[31:24] : raw_word[31:24],
                               byp_hit & byp_be[2] ? byp_data[23:16] : raw_word[23:16],
                               byp_hit & byp_be[1] ? byp_data[15:8]  : raw_word[15:8],
                               byp_hit & byp_be[0] ? byp_data[7:0]   : raw_word[7:0]};
    assign rdata_m = uncached_m ? unc_rdata : cached_word;

    // ---------------- Control ----------------
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; req <= 1'b0; valid <= 0; dirty <= 0; unc_done <= 1'b0; byp_valid <= 1'b0;
        end else begin
            if (~hold) unc_done <= 1'b0;    // the instruction leaves Memory

            if (store_hit) begin
                dirty[idx] <= 1'b1;
                byp_valid <= 1'b1; byp_addr <= addr_m[31:2]; byp_be <= be_m; byp_data <= wdata_m;
            end

            case (state)
                S_IDLE:
                    if (miss) state <= S_VICTIM;    // RAM now reads the line at idx (hold = 1)
                    else if (unc_pending) begin
                        req <= 1'b1; req_we <= we_m; req_addr <= addr_m[26:4];
                        req_wdata <= {4{wdata_m}};
                        req_wmask <= {12'd0, be_m} << (4*wsel);
                        state <= S_UNC;
                    end
                S_VICTIM: begin
                    req <= 1'b1;
                    if (valid[idx] & dirty[idx]) begin
                        req_we <= 1'b1; req_addr <= {tags[idx], idx}; req_wdata <= line; req_wmask <= 16'hFFFF;
                        state <= S_WB;
                    end else begin
                        req_we <= 1'b0; req_addr <= {tag, idx};
                        state <= S_FILL;
                    end
                end
                S_WB:
                    if (ack) begin req_we <= 1'b0; req_addr <= {tag, idx}; state <= S_FILL; end
                S_FILL:
                    if (ack) begin
                        req <= 1'b0;
                        tags[idx] <= tag; valid[idx] <= 1'b1; dirty[idx] <= 1'b0;
                        byp_valid <= 1'b0;
                        state <= S_REREAD;
                    end
                S_REREAD:
                    state <= S_IDLE;
                S_UNC:
                    if (ack) begin
                        req <= 1'b0; unc_done <= 1'b1;
                        unc_rdata <= ack_rdata[32*wsel +: 32];
                        state <= S_IDLE;
                    end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
