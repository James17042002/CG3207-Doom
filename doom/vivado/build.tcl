# Build the doom SoC for the Nexys 4 DDR from scratch: project, MIG IP, synthesis, implementation,
# timing report and bitstream.
#
#   cd <repo>/doom/vivado
#   vivado -mode batch -source build.tcl                   (50 MHz CPU clock)
#   vivado -mode batch -source build.tcl -tclargs 16       (CPU_CLK_DIV = 16 -> 62.5 MHz)
#
# Output: doom/vivado/out/top_nexys4ddr.bit, timing_summary.rpt, utilization.rpt
# The Vivado project is left in doom/vivado/proj (open it in the GUI to inspect anything).
# Pass "-tclargs <div> project" to stop after creating the project (no synthesis).

set here [file normalize [file dirname [info script]]]
set root [file normalize "$here/../.."]
set core "$root/project/project.srcs/sources_1/imports"
set cpu_div 20
if {[llength $argv] > 0} { set cpu_div [lindex $argv 0] }
set only_project [expr {[llength $argv] > 1 && [lindex $argv 1] eq "project"}]

file mkdir "$here/out"
create_project doom_soc "$here/proj" -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]

# ---------------- Sources ----------------
add_files -norecurse [list \
    "$root/doom/rtl/top_nexys4ddr.v" "$root/doom/rtl/soc.v" "$root/doom/rtl/rv_core.v" \
    "$root/doom/rtl/sdp_ram.v" "$root/doom/rtl/icache.v" "$root/doom/rtl/dcache.v" \
    "$root/doom/rtl/mem_bridge.v" "$root/doom/rtl/mmio.v" "$root/doom/rtl/uart.v" \
    "$core/Asst_02/ALU.v" "$core/Asst_02/Decoder.v" "$core/Asst_02/Extend.v" "$core/Asst_02/PC_Logic.v" \
    "$core/Asst_02/RegFile.v" "$core/Asst_02/Shifter.v" "$core/Asst_03/MCycle.v" \
    "$core/Asst_02/pmodoledrgb_bitmap.vhd" \
    "$root/doom/sw/boot/boot.mem"]
set_property file_type {Memory Initialization Files} [get_files "$root/doom/sw/boot/boot.mem"]
add_files -fileset constrs_1 -norecurse "$here/doom.xdc"
set_property top top_nexys4ddr [current_fileset]
# boot.mem is found by name because it is added to the project (as the course does with AA_IROM.mem)
set_property generic "CPU_CLK_DIV=$cpu_div" [current_fileset]

# ---------------- MIG (DDR2 controller) from doom/vivado/mig.prj ----------------
create_ip -name mig_7series -vendor xilinx.com -library ip -module_name mig_ddr2
set ip_dir [get_property IP_DIR [get_ips mig_ddr2]]
file copy -force "$here/mig.prj" "$ip_dir/mig_a.prj"
set_property -dict [list \
    CONFIG.XML_INPUT_FILE {mig_a.prj} \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
    CONFIG.BOARD_MIG_PARAM {Custom}] [get_ips mig_ddr2]
generate_target all [get_ips mig_ddr2]
synth_ip [get_ips mig_ddr2]

if {$only_project} { puts "Project created in $here/proj"; return }

# ---------------- Build ----------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed - see $here/proj/doom_soc.runs/synth_1/runme.log" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed - see $here/proj/doom_soc.runs/impl_1/runme.log" }

open_run impl_1
report_timing_summary -max_paths 20 -file "$here/out/timing_summary.rpt"
report_utilization -file "$here/out/utilization.rpt"
file copy -force [glob "$here/proj/doom_soc.runs/impl_1/*.bit"] "$here/out/top_nexys4ddr.bit"

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "=================================================================="
puts " Bitstream: $here/out/top_nexys4ddr.bit"
puts " CPU clock: [expr {1000.0 / $cpu_div}] MHz   worst setup slack (WNS): $wns ns"
if {$wns < 0} { puts " TIMING FAILED - rebuild with a larger CPU_CLK_DIV (slower clock)" }
puts "=================================================================="
