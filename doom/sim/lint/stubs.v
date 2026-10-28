// Black-box stubs of the Xilinx primitives / IP / VHDL used by top_nexys4ddr.v (lint only).
module MMCME2_BASE #(parameter real CLKIN1_PERIOD=10.0, parameter real CLKFBOUT_MULT_F=10.0, parameter DIVCLK_DIVIDE=1,
    parameter real CLKOUT0_DIVIDE_F=20.0, parameter CLKOUT1_DIVIDE=5)
   (input CLKIN1, CLKFBIN, PWRDWN, RST, output CLKFBOUT, CLKFBOUTB, CLKOUT0, CLKOUT0B, CLKOUT1, CLKOUT1B,
    CLKOUT2, CLKOUT2B, CLKOUT3, CLKOUT3B, CLKOUT4, CLKOUT5, CLKOUT6, LOCKED);
endmodule
module BUFG(input I, output O); assign O = I; endmodule
module mig_ddr2(inout [15:0] ddr2_dq, inout [1:0] ddr2_dqs_n, ddr2_dqs_p, output [12:0] ddr2_addr, output [2:0] ddr2_ba,
    output ddr2_ras_n, ddr2_cas_n, ddr2_we_n, output [0:0] ddr2_ck_p, ddr2_ck_n, ddr2_cke, ddr2_cs_n, output [1:0] ddr2_dm,
    output [0:0] ddr2_odt, input sys_clk_i, sys_rst, input [26:0] app_addr, input [2:0] app_cmd, input app_en, output app_rdy,
    input [127:0] app_wdf_data, input app_wdf_end, input [15:0] app_wdf_mask, input app_wdf_wren, output app_wdf_rdy,
    output [127:0] app_rd_data, output app_rd_data_end, app_rd_data_valid, input app_sr_req, app_ref_req, app_zq_req,
    output app_sr_active, app_ref_ack, app_zq_ack, output ui_clk, ui_clk_sync_rst, init_calib_complete);
endmodule
module PmodOLEDrgb_bitmap #(parameter CLK_FREQ_HZ=100000000, BPP=16)(input clk, reset, pix_write, input [6:0] pix_col,
    input [5:0] pix_row, input [BPP-1:0] pix_data_in, output [BPP-1:0] pix_data_out,
    output PMOD_CS, PMOD_MOSI, PMOD_SCK, PMOD_DC, PMOD_RES, PMOD_VCCEN, PMOD_EN);
endmodule
