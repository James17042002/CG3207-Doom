`timescale 1ns / 1ps
// Connects the two caches (CPU clock) to the Xilinx MIG 7-series native user interface (ui_clk).
//
// CPU side: fixed-priority arbiter (data cache first). One 16-byte transaction at a time.
// Clock crossing: request/acknowledge toggles through two-flop synchronisers. The request fields
// are held stable in CPU-domain registers while a request is outstanding, and the read data is
// held stable in a ui_clk-domain register until the next request, so they need no synchronisers
// (constrain them with set_max_delay -datapath_only / false paths; see doom/vivado/doom.xdc).
//
// MIG settings assumed (doom/vivado/mig.prj): DDR2 x16, 4:1 PHY ratio, burst length 8
// -> app_data_width = 128 (16 bytes per transaction), app_addr in 16-bit units, 27 bits.
module mem_bridge (
    // ---------------- CPU clock domain ----------------
    input              clk,
    input              rst,
    // instruction cache (read only)
    input              i_req,
    input      [26:4]  i_addr,
    output             i_ack,
    // data cache
    input              d_req,
    input              d_we,
    input      [26:4]  d_addr,
    input      [127:0] d_wdata,
    input      [15:0]  d_wmask,         // 1 = write this byte
    output             d_ack,
    output     [127:0] rdata,           // valid with i_ack / d_ack
    output             calib_done,      // synchronised init_calib_complete

    // ---------------- MIG user interface (ui_clk domain) ----------------
    input              ui_clk,
    input              ui_rst,
    input              init_calib_complete,
    output reg [26:0]  app_addr = 0,
    output reg [2:0]   app_cmd = 0,
    output reg         app_en = 1'b0,
    input              app_rdy,
    output reg [127:0] app_wdf_data = 0,
    output reg         app_wdf_end = 1'b0,
    output reg [15:0]  app_wdf_mask = 0, // MIG: 1 = do NOT write this byte
    output reg         app_wdf_wren = 1'b0,
    input              app_wdf_rdy,
    input      [127:0] app_rd_data,
    input              app_rd_data_valid
);
    // ================= CPU domain =================
    (* ASYNC_REG = "TRUE" *) reg ack_s1 = 1'b0, ack_s2 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg cal_s1 = 1'b0, cal_s2 = 1'b0;
    reg req_t = 1'b0;           // toggles once per request
    reg ack_seen = 1'b0;
    reg busy = 1'b0, owner = 1'b0;  // owner: 0 = instruction cache, 1 = data cache
    reg          r_we = 1'b0;
    reg [26:4]   r_addr = 0;
    reg [127:0]  r_wdata = 0;
    reg [15:0]   r_wmask = 0;
    reg [127:0]  u_rdata = 0;   // ui domain, stable while not busy

    wire done = busy & (ack_s2 != ack_seen);
    assign i_ack = done & ~owner;
    assign d_ack = done &  owner;
    assign rdata = u_rdata;
    assign calib_done = cal_s2;

    always @(posedge clk) begin
        ack_s1 <= ack_t;  ack_s2 <= ack_s1;
        cal_s1 <= init_calib_complete; cal_s2 <= cal_s1;
        if (rst) begin
            busy <= 1'b0;
            ack_seen <= ack_s2;
        end else if (!busy) begin
            if (d_req) begin
                owner <= 1'b1; r_we <= d_we; r_addr <= d_addr; r_wdata <= d_wdata; r_wmask <= d_wmask;
                req_t <= ~req_t; busy <= 1'b1;
            end else if (i_req) begin
                owner <= 1'b0; r_we <= 1'b0; r_addr <= i_addr; r_wmask <= 16'h0;
                req_t <= ~req_t; busy <= 1'b1;
            end
        end else if (done) begin
            ack_seen <= ~ack_seen;
            busy <= 1'b0;
        end
    end

    // ================= ui_clk domain =================
    (* ASYNC_REG = "TRUE" *) reg req_s1 = 1'b0, req_s2 = 1'b0;
    reg req_seen = 1'b0;
    reg ack_t = 1'b0;
    localparam U_IDLE = 2'd0, U_WR = 2'd1, U_RD = 2'd2, U_RDWAIT = 2'd3;
    reg [1:0] ustate = U_IDLE;
    reg cmd_done = 1'b0, data_done = 1'b0;

    always @(posedge ui_clk) begin
        req_s1 <= req_t; req_s2 <= req_s1;
        if (ui_rst) begin
            ustate <= U_IDLE; app_en <= 1'b0; app_wdf_wren <= 1'b0; app_wdf_end <= 1'b0;
            req_seen <= req_s2;
        end else case (ustate)
            U_IDLE:
                if (init_calib_complete && (req_s2 != req_seen)) begin
                    req_seen <= req_s2;
                    app_addr <= {1'b0, r_addr, 3'b000};
                    app_en <= 1'b1;
                    if (r_we) begin
                        app_cmd <= 3'b000;
                        app_wdf_data <= r_wdata; app_wdf_mask <= ~r_wmask;
                        app_wdf_wren <= 1'b1; app_wdf_end <= 1'b1;
                        cmd_done <= 1'b0; data_done <= 1'b0;
                        ustate <= U_WR;
                    end else begin
                        app_cmd <= 3'b001;
                        ustate <= U_RD;
                    end
                end
            U_WR: begin
                // command and write data are accepted independently
                if (app_en && app_rdy)             begin app_en <= 1'b0; cmd_done <= 1'b1; end
                if (app_wdf_wren && app_wdf_rdy)   begin app_wdf_wren <= 1'b0; app_wdf_end <= 1'b0; data_done <= 1'b1; end
                if ((cmd_done || (app_en && app_rdy)) && (data_done || (app_wdf_wren && app_wdf_rdy))) begin
                    ack_t <= ~ack_t;
                    ustate <= U_IDLE;
                end
            end
            U_RD:
                if (app_rdy) begin app_en <= 1'b0; ustate <= U_RDWAIT; end
            U_RDWAIT:
                if (app_rd_data_valid) begin
                    u_rdata <= app_rd_data;
                    ack_t <= ~ack_t;
                    ustate <= U_IDLE;
                end
        endcase
    end
endmodule
