// Cadence Conformal LEC - BharatVoice SoC (Dofile mode)

read library -lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

read design -golden -systemverilog -define SYNTHESIS ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv sram_model.sv sram_controller.sv spi_master.sv spi_controller.sv transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv

set root module bharatvoice_top -golden

read design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v
set root module bharatvoice_top -revised

set flatten model -seq_constant
set flatten model -gated_clock

add pin constraints 1 rst_ni -both
add pin constraints 0 jtag_tck_i -both
add pin constraints 0 jtag_tms_i -both
add pin constraints 0 jtag_tdi_i -both

set system mode lec

map key points
report unmapped points -summary
report unmapped points -notmapped > unmapped.rpt
add compared points -all
compare

report verification > verify.rpt
report compare data -class nonequivalent -class abort -class notcompared > noneq.rpt
diagnose -noanalyze
