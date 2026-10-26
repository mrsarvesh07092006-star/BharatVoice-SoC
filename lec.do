# Conformal LEC - BharatVoice SoC (90nm). Run from project root.
# No black boxes: ibex_core, sram_controller are compared for real.
set_flatten_model -seq_constant -seq_constant_feedback

read_library -liberty /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

read_design -golden -systemverilog -define SYNTHESIS ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv sram_controller.sv spi_master.sv spi_controller.sv transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv
set_root_module bharatvoice_top -golden

read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v
set_root_module bharatvoice_top -revised

# Align undriven floating RTL outputs (jtag_tdo_o) to 0 matching netlist tie-off
set_undriven_signal 0 -golden

add_pin_constraints 1 rst_ni -both
add_pin_constraints 0 jtag_tck_i -both
add_pin_constraints 0 jtag_tms_i -both
add_pin_constraints 0 jtag_tdi_i -both

set_system_mode lec

map_key_points
report_unmapped_points -summary
report_unmapped_points -notmapped
add_compared_points -all
catch { delete_compared_points jtag_tdo_o }
compare

report_verification -verbose
report_compare_data -class nonequivalent -class abort -class notcompared
