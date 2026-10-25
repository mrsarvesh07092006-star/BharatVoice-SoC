# Cadence Conformal LEC - BharatVoice SoC

# 1. Read technology library
read_library -lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

# 2. Read Golden RTL
read_design -golden -systemverilog ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv sram_model.sv sram_controller.sv spi_master.sv spi_controller.sv transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv

# 3. Set Golden top module
set_root_module bharatvoice_top -golden

# 4. Read Revised synthesized netlist
read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v

# 5. Set Revised top module
set_root_module bharatvoice_top -revised

# 6. Enter LEC mode
set_system_mode lec

# 7. Compare designs
add_compared_points -all
compare

# 8. Reports
report_verification
report_compare_data -class nonequivalent -class abort -class notcompared
