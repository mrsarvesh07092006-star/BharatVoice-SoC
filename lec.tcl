# =============================================================================
# Cadence Conformal LEC Script for BharatVoice SoC
# Top Module: bharatvoice_top
# Target: Full Equivalence PASS (Golden RTL vs Synthesized Netlist)
# =============================================================================

# 1. Read Technology Timing Library
read_library -lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

# 2. Read Golden Design (SystemVerilog RTL)
read_design -golden -systemverilog -define SYNTHESIS \
    ibex_core.sv boot_rom.sv uart_rx.sv irq_ctrl.sv clint.sv crc_checker.sv \
    transaction_guard.sv power_manager.sv payment_engine.sv audio_engine.sv \
    sram_model.sv sram_controller.sv spi_master.sv spi_controller.sv \
    transaction_cache.sv bus_interconnect.sv bharatvoice_top.sv

set_root_module bharatvoice_top -golden

# 3. Read Revised Design (Synthesized Gate-Level Netlist)
read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v

set_root_module bharatvoice_top -revised

# 4. Modeling & Flattening Directives (Crucial for SoC with Reset Synchronizers)
# Propagates sequential constants (e.g. rst_ff1 -> rst_ff2 -> rst_sync_n = 1)
set_flatten_model -seq_constant
set_flatten_model -gated_clock

# 5. Pin Constraints for Normal Functional Operating Mode
add_pin_constraints 1 rst_ni -both
add_pin_constraints 0 jtag_tck_i -both
add_pin_constraints 0 jtag_tms_i -both
add_pin_constraints 0 jtag_tdi_i -both

# 6. Switch to LEC Verification Mode
set_system_mode lec

# 7. Map Key Points & Add to Compare List
map_key_points
add_compared_points -all

# 8. Run Formal Equivalence Comparison
compare

# 9. Verification Reports
report_verification
report_compare_data -class nonequivalent -class abort -class notcompared
