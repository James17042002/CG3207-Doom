# Program the Nexys 4 DDR over USB with the bitstream from build.tcl:
#   vivado -mode batch -source program.tcl
set here [file normalize [file dirname [info script]]]
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE "$here/out/top_nexys4ddr.bit" $dev
program_hw_devices $dev
puts "Programmed. The bootloader prints 'ready' on the UART (921600 baud)."
close_hw_manager
