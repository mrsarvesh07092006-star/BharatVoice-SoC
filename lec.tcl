# Cadence Conformal LEC - BharatVoice SoC
# VIT Lab - 90nm ASIC Verification Flow

# 1. Read technology library
read_library -lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

# 2. Read Golden RTL (single line to avoid line-continuation errors)
read_design -golden -systemverilog -define SYNTHESIS ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv sram_model.sv sram_controller.sv spi_master.sv spi_controller.sv transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv

set_root_module bharatvoice_top -golden

# 3. Read Revised netlist
read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v
set_root_module bharatvoice_top -revised

# 4. Sequential Flattening and Constant Propagation
set_flatten_model -seq_constant
set_flatten_model -seq_constant_x_to_zero
set_flatten_model -gated_clock

# 5. Pin Constraints
add_pin_constraints 1 rst_ni -both
add_pin_constraints 0 jtag_tck_i -both
add_pin_constraints 0 jtag_tms_i -both
add_pin_constraints 0 jtag_tdi_i -both

# Internal synchronizer signals as constant 1
catch { set_constant 1 rst_ff2 -both }
catch { set_constant 1 rst_sync_n -both }
catch { add_pin_constraints 1 rst_ff2 -both }
catch { add_pin_constraints 1 rst_sync_n -both }

# 6. Enter LEC Verification Mode
set_system_mode lec

# 7. Exclude synchronizer FFs from compare points
catch { delete_compared_points rst_ff1 -golden }
catch { delete_compared_points rst_ff2 -golden }

# 8. Map and Compare
map_key_points
add_compared_points -all
compare

# 9. Reports
report_verification
report_compare_data -class nonequivalent -class abort -class notcompared
