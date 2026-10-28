`timescale 1ns / 1ps
// Testbench for soc.v with the MIG model. Works with Icarus Verilog and Verilator (--timing).
//
// Files (in the current directory): boot.mem (boot RAM image), ddr.mem (optional DDR2 image).
// Plusargs:
//   +cycles=N        stop after N CPU cycles (default 2,000,000; 0 = no limit)
//   +uart_in=FILE    bytes sent to the board's UART RX (after +uart_delay=N cycles, default 1000)
//   +frames=PREFIX   dump every completed OLED frame as PREFIX_NNNN.ppm
//   +max_frames=N    stop after N OLED frames
//   +dip=HEX +pb=HEX switch / button values
//   +quiet           do not log LED / 7-segment changes
//   +mmio_trace      log every peripheral write (address, data)
//   +pc_every=N      print the PC every N cycles (crude profiler)
//   +trace_from=N    print pipeline state every cycle from cycle N
// The program ends the simulation by writing its exit code to 0xFFFF00FC (0 = pass).
module tb_soc;
    parameter CLK_FREQ_HZ = 50000000;
    parameter BAUD        = 3125000;        // fast UART in simulation (16 clocks per bit)
    parameter LINE_BITS   = 23;             // DDR model size: 2**LINE_BITS x 16 bytes (23 = 128 MB; use -D LINE_BITS=16 with Icarus)
    parameter ICACHE_IDX  = 10;
    parameter DCACHE_IDX  = 10;

    reg clk = 1'b0, ui_clk = 1'b0;
    always #10    clk    = ~clk;            // 50 MHz CPU clock
    always #6.154 ui_clk = ~ui_clk;         // 81.25 MHz MIG ui_clk (DDR2 at 325 MHz, 4:1)

    reg rst = 1'b1;
    reg [15:0] dip = 0;
    reg [4:0]  pb = 0;
    wire [15:0] led;
    wire [31:0] sevenseg;
    reg  uart_rxd = 1'b1;
    wire uart_txd;
    wire oled_write;
    wire [6:0] oled_col;
    wire [5:0] oled_row;
    wire [23:0] oled_data;
    wire sim_exit;
    wire [31:0] sim_exit_code;

    wire ui_rst, init_calib_complete, app_en, app_rdy, app_wdf_end, app_wdf_wren, app_wdf_rdy;
    wire app_rd_data_valid, app_rd_data_end;
    wire [26:0] app_addr;
    wire [2:0] app_cmd;
    wire [127:0] app_wdf_data, app_rd_data;
    wire [15:0] app_wdf_mask;

    soc #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD(BAUD), .BOOT_INIT("boot.mem"),
          .ICACHE_IDX(ICACHE_IDX), .DCACHE_IDX(DCACHE_IDX)) dut(
        .clk(clk), .rst(rst), .dip(dip), .pb(pb), .led(led), .sevenseg(sevenseg),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .oled_write(oled_write), .oled_col(oled_col), .oled_row(oled_row), .oled_data(oled_data),
        .sim_exit(sim_exit), .sim_exit_code(sim_exit_code),
        .ui_clk(ui_clk), .ui_rst(ui_rst), .init_calib_complete(init_calib_complete),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_end(app_wdf_end), .app_wdf_mask(app_wdf_mask),
        .app_wdf_wren(app_wdf_wren), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid));

    mig_model #(.LINE_BITS(LINE_BITS), .INIT("ddr.mem")) mig(
        .ui_clk(ui_clk), .ui_rst(ui_rst), .init_calib_complete(init_calib_complete),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_end(app_wdf_end), .app_wdf_mask(app_wdf_mask),
        .app_wdf_wren(app_wdf_wren), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid), .app_rd_data_end(app_rd_data_end));

    localparam CPB = CLK_FREQ_HZ / BAUD;    // clocks per UART bit

    integer max_cycles, cycle = 0, max_frames, frames = 0;
    reg quiet;
    reg [1023:0] frame_prefix;
    reg have_frames;
    reg [15:0] last_led = 0;
    reg [31:0] last_7seg = 0;

    initial begin
        if (!$value$plusargs("cycles=%d", max_cycles)) max_cycles = 2000000;
        if (!$value$plusargs("max_frames=%d", max_frames)) max_frames = 0;
        have_frames = $value$plusargs("frames=%s", frame_prefix);
        if ($value$plusargs("dip=%h", dip)) ;
        if ($value$plusargs("pb=%h", pb)) ;
        quiet = $test$plusargs("quiet");
        repeat (5) @(posedge clk);
        rst = 1'b0;
    end

    // ---------------- cycle limit and exit ----------------
    always @(posedge clk) begin
        if (!rst) begin
            cycle = cycle + 1;
            if (sim_exit) begin
                $display("");
                if (sim_exit_code == 0) $display("SIM PASS after %0d cycles", cycle);
                else $display("SIM FAIL: exit code %0d (0x%08h) after %0d cycles", sim_exit_code, sim_exit_code, cycle);
                $finish;
            end
            if (max_cycles != 0 && cycle >= max_cycles) begin
                $display("");
                $display("SIM TIMEOUT after %0d cycles (PC=%08h)", cycle, dut.pc);
                $finish;
            end
            if (!quiet && led !== last_led) begin $display("[%0d] LED = %04h", cycle, led); last_led = led; end
            if (!quiet && sevenseg !== last_7seg) begin $display("[%0d] 7SEG = %08h", cycle, sevenseg); last_7seg = sevenseg; end
        end
    end

    // ---------------- optional pipeline trace (+trace_from=CYCLE) ----------------
    integer trace_from;
    initial if (!$value$plusargs("trace_from=%d", trace_from)) trace_from = -1;
    always @(posedge clk)
        if (trace_from >= 0 && cycle >= trace_from && !rst)
            $display("[%0d] F=%08h D=%08h(%08h) E=%08h M=%08h hold=%b is=%b ds=%b | rdE=%0d rdM=%0d rdW=%0d WE=%b WD=%08h fA=%b fB=%b",
                cycle, dut.pc, dut.core.PCD, dut.core.InstrD, dut.core.PCE, dut.addr_m, dut.hold, dut.imem_stall, dut.dmem_stall,
                dut.core.rdE, dut.core.rdM, dut.core.rdW, dut.core.WE, dut.core.WD, dut.core.ForwardAE, dut.core.ForwardBE);

    // ---------------- optional PC sampling (+pc_every=N): where is the program spending time? ----------------
    integer pc_every;
    initial if (!$value$plusargs("pc_every=%d", pc_every)) pc_every = 0;
    always @(posedge clk)
        if (pc_every > 0 && !rst && (cycle % pc_every) == 0)
            $display("[%0d] PC sample %08h", cycle, dut.pc);

    // ---------------- stall statistics, printed with each OLED frame ----------------
    integer st_i = 0, st_d = 0, st_mc = 0, st_lw = 0, st_br = 0, st_cyc = 0;
    always @(posedge clk) if (!rst) begin
        st_cyc = st_cyc + 1;
        if (dut.imem_stall) st_i = st_i + 1;
        else if (dut.dmem_stall) st_d = st_d + 1;
        else if (dut.core.MCycleBusy) st_mc = st_mc + 1;
        else if (dut.core.lwStall) st_lw = st_lw + 1;
        else if (dut.core.BranchTakenE) st_br = st_br + 1;
    end

    // ---------------- optional MMIO write trace ----------------
    reg mmio_trace;
    initial mmio_trace = $test$plusargs("mmio_trace");
    always @(posedge clk)
        if (mmio_trace && !rst && dut.m_mmio && (|dut.be_m) && !dut.hold)
            $display("[%0d] MMIO write %08h <= %08h (be %b)", cycle, dut.addr_m, dut.wdata_m, dut.be_m);

    // ---------------- UART TX decoder (board -> PC) ----------------
    integer tb_i;
    reg [7:0] tx_byte;
    initial begin
        forever begin
            @(negedge uart_txd);
            repeat (CPB/2) @(posedge clk);
            for (tb_i = 0; tb_i < 8; tb_i = tb_i + 1) begin
                repeat (CPB) @(posedge clk);
                tx_byte[tb_i] = uart_txd;
            end
            repeat (CPB) @(posedge clk);      // stop bit
            $write("%c", tx_byte);
            $fflush;
        end
    end

    // ---------------- UART RX driver (PC -> board) ----------------
    reg [1023:0] uart_in;
    integer fd, ch, uart_delay, rb;
    initial begin
        if ($value$plusargs("uart_in=%s", uart_in)) begin
            if (!$value$plusargs("uart_delay=%d", uart_delay)) uart_delay = 1000;
            fd = $fopen(uart_in, "rb");
            if (fd == 0) begin $display("tb_soc: cannot open %0s", uart_in); $finish; end
            repeat (uart_delay) @(posedge clk);
            ch = $fgetc(fd);
            while (ch != -1) begin
                uart_rxd = 1'b0; repeat (CPB) @(posedge clk);
                for (rb = 0; rb < 8; rb = rb + 1) begin uart_rxd = ch[rb]; repeat (CPB) @(posedge clk); end
                uart_rxd = 1'b1; repeat (CPB) @(posedge clk);
                ch = $fgetc(fd);
            end
            $fclose(fd);
        end
    end

    // ---------------- OLED frame capture ----------------
    reg [23:0] fb [0:96*64-1];
    integer px, ffd;
    reg [1023:0] fname;
    always @(posedge clk) begin
        if (oled_write) begin
            fb[oled_row*96 + oled_col] = oled_data;
            if (oled_col == 95 && oled_row == 63) begin
                frames = frames + 1;
                if (have_frames) begin
                    $sformat(fname, "%0s_%04d.ppm", frame_prefix, frames);
                    ffd = $fopen(fname, "wb");
                    $fwrite(ffd, "P6\n96 64\n255\n");
                    for (px = 0; px < 96*64; px = px + 1)
                        $fwrite(ffd, "%c%c%c", fb[px][23:16], fb[px][15:8], fb[px][7:0]);
                    $fclose(ffd);
                end
                $display("[%0d] OLED frame %0d complete  (since last: %0d cycles; I-miss %0d%%, D-miss %0d%%, mul/div %0d%%, load-use %0d%%, taken branch %0d%%)",
                         cycle, frames, st_cyc, st_i*100/st_cyc, st_d*100/st_cyc, st_mc*100/st_cyc, st_lw*100/st_cyc, st_br*100/st_cyc);
                st_i = 0; st_d = 0; st_mc = 0; st_lw = 0; st_br = 0; st_cyc = 0;
                if (max_frames != 0 && frames >= max_frames) begin
                    $display("SIM STOP after %0d frames", frames);
                    $finish;
                end
            end
        end
    end
endmodule
