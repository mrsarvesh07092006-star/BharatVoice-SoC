# Cadence Conformal LEC - BharatVoice SoC
# VIT Lab - 90nm ASIC Verification Flow

# 1. Read technology library
read_library -lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

# 2. Read Golden RTL
read_design -golden -systemverilog -define SYNTHESIS ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv sram_model.sv sram_controller.sv spi_master.sv spi_controller.sv transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv

set_root_module bharatvoice_top -golden

# 3. Read Revised netlist (Genus synthesized netlist)
read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v
set_root_module bharatvoice_top -revised

# 4. Sequential Flattening and Clock Gating
set_flatten_model -seq_constant
set_flatten_model -gated_clock

# 5. Pin Constraints
add_pin_constraints 1 rst_ni -both
add_pin_constraints 0 jtag_tck_i -both
add_pin_constraints 0 jtag_tms_i -both
add_pin_constraints 0 jtag_tdi_i -both

# 6. Enter LEC Verification Mode
set_system_mode lec

# 7. Map and Compare
map_key_points
report_unmapped_points -summary
report_unmapped_points -notmapped > unmapped.rpt
add_compared_points -all
compare

# 8. Reports
report_verification > verify.rpt
report_compare_data -class nonequivalent -class abort -class notcompared > noneq.rpt
diagnose -noanalyze
