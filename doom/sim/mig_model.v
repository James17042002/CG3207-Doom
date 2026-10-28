`timescale 1ns / 1ps
// Behavioural model of the Xilinx MIG 7-series native user interface (DDR2 x16, 4:1, BL8):
// 128-bit data, app_addr in 16-bit units. Commands are executed in order (strict ordering).
// app_rdy / app_wdf_rdy are randomly deasserted to exercise back-pressure.
// Memory size is 2**LINE_BITS lines of 16 bytes; addresses wrap.
module mig_model #(
    parameter LINE_BITS = 16,           // 16 -> 1 MB
    parameter INIT      = "",           // optional $readmemh file of 128-bit lines (use @line addresses)
    parameter LATENCY   = 14,           // read latency in ui_clk cycles
    parameter CALIB_CYCLES = 200
)(
    input              ui_clk,
    output reg         ui_rst = 1'b1,
    output reg         init_calib_complete = 1'b0,
    input      [26:0]  app_addr,
    input      [2:0]   app_cmd,
    input              app_en,
    output             app_rdy,
    input      [127:0] app_wdf_data,
    input              app_wdf_end,
    input      [15:0]  app_wdf_mask,
    input              app_wdf_wren,
    output             app_wdf_rdy,
    output reg [127:0] app_rd_data = 0,
    output reg         app_rd_data_valid = 1'b0,
    output reg         app_rd_data_end = 1'b0
);
    reg [127:0] mem [0:(1<<LINE_BITS)-1];
    integer k;
    initial begin
        for (k = 0; k < (1<<LINE_BITS); k = k + 1) mem[k] = 128'd0;
        if (INIT != "") $readmemh(INIT, mem);
    end

    // pseudo-random ready signals
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge ui_clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    assign app_rdy     = init_calib_complete & (lfsr[2:0] != 3'b000);
    assign app_wdf_rdy = init_calib_complete & (lfsr[5:3] != 3'b000);

    integer cyc = 0;
    always @(posedge ui_clk) begin
        cyc <= cyc + 1;
        if (cyc == 10) ui_rst <= 1'b0;
        if (cyc == CALIB_CYCLES) init_calib_complete <= 1'b1;
    end

    // command queue (type, line) and write-data queue
    reg        cq_rd   [0:63];
    reg [LINE_BITS-1:0] cq_line [0:63];
    reg [5:0]  cq_wp = 0, cq_rp = 0;
    reg [127:0] wq_data [0:63];
    reg [15:0]  wq_mask [0:63];
    reg [5:0]  wq_wp = 0, wq_rp = 0;
    // read return pipeline
    reg [127:0] rp_data [0:LATENCY];
    reg         rp_v    [0:LATENCY];
    initial for (k = 0; k <= LATENCY; k = k + 1) rp_v[k] = 1'b0;

    integer b;
    reg [127:0] cur;
    always @(posedge ui_clk) begin
        if (app_en && app_rdy) begin
            if (app_cmd != 3'b000 && app_cmd != 3'b001) begin
                $display("mig_model: unsupported app_cmd %b", app_cmd); $finish;
            end
            if (app_addr[2:0] != 3'b000) begin
                $display("mig_model: unaligned app_addr %h", app_addr); $finish;
            end
            if ((app_addr >> (LINE_BITS + 3)) != 0) begin
                $display("mig_model: address %h (byte %h) is beyond the model size; increase LINE_BITS",
                         app_addr, {app_addr, 1'b0}); $finish;
            end
            cq_rd[cq_wp] <= (app_cmd == 3'b001);
            cq_line[cq_wp] <= app_addr[LINE_BITS+2:3];
            cq_wp <= cq_wp + 1;
        end
        if (app_wdf_wren && app_wdf_rdy) begin
            if (!app_wdf_end) begin $display("mig_model: app_wdf_end must be 1 (one beat per burst)"); $finish; end
            wq_data[wq_wp] <= app_wdf_data; wq_mask[wq_wp] <= app_wdf_mask; wq_wp <= wq_wp + 1;
        end

        // shift the read return pipeline
        for (k = LATENCY; k > 0; k = k - 1) begin rp_data[k] <= rp_data[k-1]; rp_v[k] <= rp_v[k-1]; end
        rp_v[0] <= 1'b0;

        // execute the head command, in order
        if (cq_rp != cq_wp) begin
            if (cq_rd[cq_rp]) begin
                rp_data[0] <= mem[cq_line[cq_rp]]; rp_v[0] <= 1'b1;
                cq_rp <= cq_rp + 1;
            end else if (wq_rp != wq_wp) begin
                cur = mem[cq_line[cq_rp]];
                for (b = 0; b < 16; b = b + 1)
                    if (!wq_mask[wq_rp][b]) cur[b*8 +: 8] = wq_data[wq_rp][b*8 +: 8];
                mem[cq_line[cq_rp]] <= cur;
                cq_rp <= cq_rp + 1; wq_rp <= wq_rp + 1;
            end
        end

        app_rd_data_valid <= rp_v[LATENCY];
        app_rd_data_end   <= rp_v[LATENCY];
        app_rd_data       <= rp_data[LATENCY];
    end
endmodule
