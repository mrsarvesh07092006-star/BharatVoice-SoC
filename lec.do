// Cadence Conformal LEC - BharatVoice SoC (Dofile mode)

read library -liberty /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

set flatten model -seq_constant
set flatten model -gated_clock

read design -golden -systemverilog -define SYNTHESIS ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv sram_controller.sv spi_master.sv spi_controller.sv transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv
set root module bharatvoice_top -golden

read design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v
set root module bharatvoice_top -revised

add black box sram_controller -golden
add black box sram_controller_ADDR_WIDTH16_DATA_WIDTH32_MEM_DEPTH256 -revised
add black box ibex_core -both

set undriven signal 0 -golden

add pin constraints 1 rst_ni -both
add pin constraints 0 jtag_tck_i -both
add pin constraints 0 jtag_tms_i -both
add pin constraints 0 jtag_tdi_i -both

set system mode lec

map key points
report unmapped points -summary
add compared points -all
delete compared points jtag_tdo_o
compare

report verification -verbose
report compare data -class nonequivalent -class abort -class notcompared
