`timescale 1ns / 1ps
// System-on-chip for the doom branch: rv_core + boot RAM + caches + DDR2 bridge + peripherals.
//
// Memory map
//   0x0000_0000 - 0x0000_3FFF  Boot RAM (16 KB, block RAM, holds the bootloader; code + data + stack)
//   0x8000_0000 - 0x87FF_FFFF  DDR2, 128 MB, cached (instructions and data)
//   0xC000_0000 - 0xC7FF_FFFF  DDR2, same memory, uncached (data only; used by the loader)
//   0xFFFF_0000 - 0xFFFF_00FF  Peripherals (mmio.v)
// Anything else: instruction fetch returns NOP, loads return 0, stores are ignored.
// The cached and uncached views are NOT kept coherent: write code/data through the uncached
// alias only before the cached view of those lines is first used.
module soc #(
    parameter CLK_FREQ_HZ = 50000000,
    parameter BAUD        = 921600,
    parameter BOOT_INIT   = "boot.mem",     // $readmemh image for the boot RAM (32-bit words)
    parameter BOOT_AW     = 12,             // boot RAM words = 2**BOOT_AW (12 -> 16 KB)
    parameter ICACHE_IDX  = 12,             // 2**IDX lines of 16 B (12 -> 64 KB)
    parameter DCACHE_IDX  = 12
)(
    input              clk,
    input              rst,
    // board I/O
    input      [15:0]  dip,
    input      [4:0]   pb,
    output     [15:0]  led,
    output     [31:0]  sevenseg,
    input              uart_rxd,
    output             uart_txd,
    output             oled_write,
    output     [6:0]   oled_col,
    output     [5:0]   oled_row,
    output     [23:0]  oled_data,
    output             sim_exit,
    output     [31:0]  sim_exit_code,
    // MIG native user interface
    input              ui_clk,
    input              ui_rst,
    input              init_calib_complete,
    output     [26:0]  app_addr,
    output     [2:0]   app_cmd,
    output             app_en,
    input              app_rdy,
    output     [127:0] app_wdf_data,
    output             app_wdf_end,
    output     [15:0]  app_wdf_mask,
    output             app_wdf_wren,
    input              app_wdf_rdy,
    input      [127:0] app_rd_data,
    input              app_rd_data_valid
);
    // ---------------- Core ----------------
    wire [31:0] imem_addr, pc, instr;
    wire        imem_stall, dmem_stall, hold;
    wire [31:0] addr_e, addr_m, wdata_m, rdata_m;
    wire        re_m;
    wire [3:0]  be_m;

    rv_core #(.PC_INIT(32'h0000_0000)) core(
        .CLK(clk), .RESET(rst),
        .imem_addr(imem_addr), .PC(pc), .imem_rdata(instr), .imem_stall(imem_stall),
        .dmem_addr_e(addr_e), .ALUResult(addr_m), .MemRead(re_m), .MemWrite_out(be_m),
        .WriteData_out(wdata_m), .ReadData_in(rdata_m), .dmem_stall(dmem_stall), .hold(hold));

    // ---------------- Region decode ----------------
    wire pc_boot   = (pc[31:16] == 16'h0000);
    wire pc_ddr    = (pc[31:27] == 5'b1000_0);
    wire m_boot    = (addr_m[31:16] == 16'h0000);
    wire m_ddr     = (addr_m[31:27] == 5'b1000_0);
    wire m_unc     = (addr_m[31:27] == 5'b1100_0);
    wire m_mmio    = (addr_m[31:16] == 16'hFFFF);

    // ---------------- Boot RAM ----------------
    // Two copies with the same contents: one read by instruction fetch, one by loads.
    // Stores write both.
    wire [31:0] boot_instr, boot_rdata;
    wire [3:0]  boot_wbe = (m_boot & ~hold) ? be_m : 4'b0000;
    sdp_ram #(.AW(BOOT_AW), .DW(32), .INIT(BOOT_INIT)) boot_i(
        .clk(clk), .waddr(addr_m[BOOT_AW+1:2]), .wbe(boot_wbe), .wdata(wdata_m),
        .raddr(imem_addr[BOOT_AW+1:2]), .rdata(boot_instr));
    sdp_ram #(.AW(BOOT_AW), .DW(32), .INIT(BOOT_INIT)) boot_d(
        .clk(clk), .waddr(addr_m[BOOT_AW+1:2]), .wbe(boot_wbe), .wdata(wdata_m),
        .raddr(hold ? addr_m[BOOT_AW+1:2] : addr_e[BOOT_AW+1:2]), .rdata(boot_rdata));

    // store -> load bypass for the boot RAM (read-first)
    reg        bb_valid = 1'b0;
    reg [29:0] bb_addr = 0;
    reg [3:0]  bb_be = 0;
    reg [31:0] bb_data = 0;
    always @(posedge clk) begin
        if (rst) bb_valid <= 1'b0;
        else if (|boot_wbe) begin bb_valid <= 1'b1; bb_addr <= addr_m[31:2]; bb_be <= be_m; bb_data <= wdata_m; end
    end
    wire bb_hit = bb_valid && (bb_addr == addr_m[31:2]);
    wire [31:0] boot_word = {bb_hit & bb_be[3] ? bb_data[31:24] : boot_rdata[31:24],
                             bb_hit & bb_be[2] ? bb_data[23:16] : boot_rdata[23:16],
                             bb_hit & bb_be[1] ? bb_data[15:8]  : boot_rdata[15:8],
                             bb_hit & bb_be[0] ? bb_data[7:0]   : boot_rdata[7:0]};

    // ---------------- Caches ----------------
    wire [31:0] ic_instr, dc_rdata;
    wire        ic_req, ic_ack, dc_req, dc_we, dc_ack;
    wire [26:4] ic_addr, dc_addr;
    wire [127:0] dc_wdata, mem_rdata;
    wire [15:0] dc_wmask;

    icache #(.IDX(ICACHE_IDX)) icache(
        .clk(clk), .rst(rst), .addr_next(imem_addr), .pc(pc), .cached(pc_ddr),
        .instr(ic_instr), .stall(imem_stall),
        .req(ic_req), .req_addr(ic_addr), .ack(ic_ack), .ack_rdata(mem_rdata));

    dcache #(.IDX(DCACHE_IDX)) dcache(
        .clk(clk), .rst(rst), .hold(hold), .addr_e(addr_e), .addr_m(addr_m),
        .cached_m(m_ddr), .uncached_m(m_unc), .re_m(re_m), .be_m(be_m), .wdata_m(wdata_m),
        .rdata_m(dc_rdata), .stall(dmem_stall),
        .req(dc_req), .req_we(dc_we), .req_addr(dc_addr), .req_wdata(dc_wdata), .req_wmask(dc_wmask),
        .ack(dc_ack), .ack_rdata(mem_rdata));

    wire calib_done;
    mem_bridge bridge(
        .clk(clk), .rst(rst),
        .i_req(ic_req), .i_addr(ic_addr), .i_ack(ic_ack),
        .d_req(dc_req), .d_we(dc_we), .d_addr(dc_addr), .d_wdata(dc_wdata), .d_wmask(dc_wmask), .d_ack(dc_ack),
        .rdata(mem_rdata), .calib_done(calib_done),
        .ui_clk(ui_clk), .ui_rst(ui_rst), .init_calib_complete(init_calib_complete),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_end(app_wdf_end), .app_wdf_mask(app_wdf_mask),
        .app_wdf_wren(app_wdf_wren), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid));

    // ---------------- Peripherals ----------------
    wire [31:0] mmio_rdata;
    mmio #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD(BAUD)) periph(
        .clk(clk), .rst(rst), .hold(hold),
        .sel(m_mmio), .addr(addr_m[7:0]), .re(re_m), .be(m_mmio ? be_m : 4'b0000), .wdata(wdata_m),
        .rdata(mmio_rdata), .calib_done(calib_done),
        .dip(dip), .pb(pb), .led(led), .sevenseg(sevenseg),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .oled_write(oled_write), .oled_col(oled_col), .oled_row(oled_row), .oled_data(oled_data),
        .sim_exit(sim_exit), .sim_exit_code(sim_exit_code));

    // ---------------- Read multiplexers ----------------
    // Instruction: region of the PC currently in Fetch
    assign instr = pc_boot ? boot_instr : pc_ddr ? ic_instr : 32'h0000_0013;
    // Data: region of the access in Memory
    assign rdata_m = m_boot ? boot_word : (m_ddr | m_unc) ? dc_rdata : m_mmio ? mmio_rdata : 32'd0;
endmodule
