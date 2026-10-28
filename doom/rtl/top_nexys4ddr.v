`timescale 1ns / 1ps
// Top level for the Nexys 4 DDR (XC7A100T-1CSG324): clocks, resets, DDR2 controller (MIG),
// Pmod OLEDrgb controller, 7-segment display, and the SoC.
//
// Clocks: one MMCM from the 100 MHz oscillator makes
//   clk_cpu = 1000 MHz / CPU_CLK_DIV   (CPU, caches, peripherals, OLED controller)
//   clk_200 = 200 MHz                  (MIG system + reference clock)
// The MIG makes its own ui_clk (81.25 MHz for DDR2 at 325 MHz, 4:1); mem_bridge crosses to it.
//
// Pmod OLEDrgb goes in the JB connector (as in the course TOP_Nexys.vhd).
// CPU_RESETN (red button) resets the processor; all five push buttons are inputs.
module top_nexys4ddr #(
    parameter CPU_CLK_DIV = 20,                 // 20 -> 50 MHz, 16 -> 62.5, 15 -> 66.7, 14 -> 71.4
    parameter BAUD        = 921600,
    parameter BOOT_INIT   = "boot.mem"          // set to an absolute path by build.tcl
)(
    input         CLK100MHZ,
    input         CPU_RESETN,
    input  [15:0] SW,
    input         BTNC, BTNU, BTNL, BTNR, BTND,
    output [15:0] LED,
    output [7:0]  AN,
    output [6:0]  SEG,                          // {CG, CF, CE, CD, CC, CB, CA}, active low
    output        DP,
    input         UART_TXD_IN,                  // from the PC (FTDI) to the FPGA
    output        UART_RXD_OUT,                 // from the FPGA to the PC
    // Pmod OLEDrgb on JB
    output        PMOD_CS, PMOD_MOSI, PMOD_SCK, PMOD_DC, PMOD_RES, PMOD_VCCEN, PMOD_EN,
    // DDR2 (pins constrained by the MIG IP)
    inout  [15:0] ddr2_dq,
    inout  [1:0]  ddr2_dqs_n,
    inout  [1:0]  ddr2_dqs_p,
    output [12:0] ddr2_addr,
    output [2:0]  ddr2_ba,
    output        ddr2_ras_n,
    output        ddr2_cas_n,
    output        ddr2_we_n,
    output [0:0]  ddr2_ck_p,
    output [0:0]  ddr2_ck_n,
    output [0:0]  ddr2_cke,
    output [0:0]  ddr2_cs_n,
    output [1:0]  ddr2_dm,
    output [0:0]  ddr2_odt
);
    localparam CLK_FREQ_HZ = 1000000000 / CPU_CLK_DIV;

    // ---------------- Clocks ----------------
    wire clkfb, clk_cpu_mmcm, clk_200_mmcm, locked, clk_cpu, clk_200;
    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0),
        .CLKFBOUT_MULT_F(10.0),                 // VCO = 1000 MHz
        .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE_F(CPU_CLK_DIV),
        .CLKOUT1_DIVIDE(5)                      // 200 MHz
    ) mmcm (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clkfb), .CLKFBOUT(clkfb),
        .CLKOUT0(clk_cpu_mmcm), .CLKOUT1(clk_200_mmcm),
        .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB(),
        .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0));
    BUFG bufg_cpu(.I(clk_cpu_mmcm), .O(clk_cpu));
    BUFG bufg_200(.I(clk_200_mmcm), .O(clk_200));

    // ---------------- Reset (synchronised to clk_cpu) ----------------
    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_sync = 3'b111;
    always @(posedge clk_cpu or negedge locked)
        if (!locked) rst_sync <= 3'b111;
        else         rst_sync <= {rst_sync[1:0], ~CPU_RESETN};
    wire rst = rst_sync[2];

    // ---------------- Inputs (synchronised) ----------------
    (* ASYNC_REG = "TRUE" *) reg [20:0] in_s1 = 0, in_s2 = 0;
    always @(posedge clk_cpu) begin
        in_s1 <= {BTND, BTNU, BTNR, BTNC, BTNL, SW};
        in_s2 <= in_s1;
    end

    // ---------------- MIG ----------------
    wire ui_clk, ui_rst, init_calib_complete;
    wire [26:0] app_addr; wire [2:0] app_cmd; wire app_en, app_rdy;
    wire [127:0] app_wdf_data, app_rd_data; wire [15:0] app_wdf_mask;
    wire app_wdf_end, app_wdf_wren, app_wdf_rdy, app_rd_data_valid, app_rd_data_end;

    mig_ddr2 u_mig (
        .ddr2_dq(ddr2_dq), .ddr2_dqs_n(ddr2_dqs_n), .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba), .ddr2_ras_n(ddr2_ras_n), .ddr2_cas_n(ddr2_cas_n),
        .ddr2_we_n(ddr2_we_n), .ddr2_ck_p(ddr2_ck_p), .ddr2_ck_n(ddr2_ck_n), .ddr2_cke(ddr2_cke),
        .ddr2_cs_n(ddr2_cs_n), .ddr2_dm(ddr2_dm), .ddr2_odt(ddr2_odt),
        .sys_clk_i(clk_200),
        .sys_rst(locked),                       // active low: hold the MIG in reset until the MMCM locks
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_end(app_wdf_end), .app_wdf_mask(app_wdf_mask),
        .app_wdf_wren(app_wdf_wren), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_end(app_rd_data_end), .app_rd_data_valid(app_rd_data_valid),
        .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
        .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
        .ui_clk(ui_clk), .ui_clk_sync_rst(ui_rst),
        .init_calib_complete(init_calib_complete));

    // ---------------- SoC ----------------
    wire [31:0] sevenseg;
    wire oled_write; wire [6:0] oled_col; wire [5:0] oled_row; wire [23:0] oled_data;
    soc #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD(BAUD), .BOOT_INIT(BOOT_INIT)) u_soc (
        .clk(clk_cpu), .rst(rst),
        .dip(in_s2[15:0]), .pb(in_s2[20:16]), .led(LED), .sevenseg(sevenseg),
        .uart_rxd(UART_TXD_IN), .uart_txd(UART_RXD_OUT),
        .oled_write(oled_write), .oled_col(oled_col), .oled_row(oled_row), .oled_data(oled_data),
        .sim_exit(), .sim_exit_code(),
        .ui_clk(ui_clk), .ui_rst(ui_rst), .init_calib_complete(init_calib_complete),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_end(app_wdf_end), .app_wdf_mask(app_wdf_mask),
        .app_wdf_wren(app_wdf_wren), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid));

    // ---------------- Pmod OLEDrgb (course VHDL controller, clocked by clk_cpu) ----------------
    PmodOLEDrgb_bitmap #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BPP(16)) u_oled (
        .clk(clk_cpu), .reset(rst),
        .pix_write(oled_write), .pix_col(oled_col), .pix_row(oled_row),
        .pix_data_in({oled_data[23:19], oled_data[15:10], oled_data[7:3]}), .pix_data_out(),
        .PMOD_CS(PMOD_CS), .PMOD_MOSI(PMOD_MOSI), .PMOD_SCK(PMOD_SCK), .PMOD_DC(PMOD_DC),
        .PMOD_RES(PMOD_RES), .PMOD_VCCEN(PMOD_VCCEN), .PMOD_EN(PMOD_EN));

    // ---------------- 7-segment display (as in TOP_Nexys.vhd) ----------------
    reg [18:0] seg_cnt = 0;
    reg [6:0]  seg = 7'h7F;
    reg [7:0]  an = 8'hFF;
    wire [2:0] digit = seg_cnt[18:16];
    wire [3:0] nib = sevenseg[digit*4 +: 4];
    always @(posedge clk_cpu) begin
        seg_cnt <= seg_cnt + 1;
        an <= ~(8'd1 << digit);
        case (nib)              // {g,f,e,d,c,b,a}, 1 = on
            4'h0: seg <= ~7'b0111111; 4'h1: seg <= ~7'b0000110; 4'h2: seg <= ~7'b1011011; 4'h3: seg <= ~7'b1001111;
            4'h4: seg <= ~7'b1100110; 4'h5: seg <= ~7'b1101101; 4'h6: seg <= ~7'b1111101; 4'h7: seg <= ~7'b0000111;
            4'h8: seg <= ~7'b1111111; 4'h9: seg <= ~7'b1100111; 4'hA: seg <= ~7'b1110111; 4'hB: seg <= ~7'b1111100;
            4'hC: seg <= ~7'b0111001; 4'hD: seg <= ~7'b1011110; 4'hE: seg <= ~7'b1111001; default: seg <= ~7'b1110001;
        endcase
    end
    assign SEG = seg;
    assign AN  = an;
    assign DP  = 1'b1;
endmodule
