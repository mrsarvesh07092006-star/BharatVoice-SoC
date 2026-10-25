# Cadence Conformal LEC - BharatVoice SoC

# 1. Read technology library
read_library -lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

# 2. Read Golden RTL
read_design -golden -systemverilog -define SYNTHESIS ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv sram_model.sv sram_controller.sv spi_master.sv spi_controller.sv transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv

# 3. Set Golden top module
set_root_module bharatvoice_top -golden

# 4. Read Revised synthesized netlist
read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v

# 5. Set Revised top module
set_root_module bharatvoice_top -revised

# 6. Crucial Directives: Resolve the rst_ff2 Synchronizer
# As you verified in the netlist line 38493, all registers have: .RN (rst_ff2)
# We must enable sequential constant propagation and constrain rst_ff2=1!
set_flatten_model -seq_constant
set_flatten_model -gated_clock

add_pin_constraints 1 rst_ni -both
catch {add_pin_constraints 1 rst_ff2 -both}
catch {add_pin_constraints 1 rst_ff2/Q -both}
catch {add_pin_constraints 1 rst_sync_n -both}

add_pin_constraints 0 jtag_tck_i -both
add_pin_constraints 0 jtag_tms_i -both
add_pin_constraints 0 jtag_tdi_i -both

# 7. Enter LEC mode
set_system_mode lec

# 8. Compare designs
map_key_points
add_compared_points -all
compare

# 9. Reports
report_verification
report_compare_data -class nonequivalent -class abort -class notcompared
