# =============================================================================
# Cadence Conformal LEC Script - BharatVoice SoC (90nm, VIT Lab)
# =============================================================================

# 1. Read Standard Cell Liberty Library
read_library -liberty /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

# 2. Pre-read and Flattening Options
set_flatten_model -seq_constant
set_flatten_model -gated_clock

# 3. Read Golden RTL (16 synthesizable modules; sram_model excluded as it is a TB model)
read_design -golden -systemverilog -define SYNTHESIS ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv sram_controller.sv spi_master.sv spi_controller.sv transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv
set_root_module bharatvoice_top -golden

# 4. Read Revised Netlist (Genus 90nm synthesized netlist)
read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v
set_root_module bharatvoice_top -revised

# 5. Black-box Memory / Macro blocks that cannot be mapped 1:1 at gate level
# In Golden RTL, module is sram_controller; in Genus netlist it is elaborated
# as sram_controller_ADDR_WIDTH16_DATA_WIDTH32_MEM_DEPTH256 (contains 8,192 DFFs).
catch { add_black_box sram_controller -golden }
catch { add_black_box sram_controller_ADDR_WIDTH16_DATA_WIDTH32_MEM_DEPTH256 -revised }
catch { add_black_box ibex_core -both }

# 6. Operating Pin Constraints
add_pin_constraints 1 rst_ni -both
add_pin_constraints 0 jtag_tck_i -both
add_pin_constraints 0 jtag_tms_i -both
add_pin_constraints 0 jtag_tdi_i -both

# 7. Enter LEC Mode
set_system_mode lec

# 8. Map Key Points & Compare
map_key_points
report_unmapped_points -summary
add_compared_points -all
compare

# 9. Reports
report_verification -verbose
report_compare_data -class nonequivalent -class abort -class notcompared
