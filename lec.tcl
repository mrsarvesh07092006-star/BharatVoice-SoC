# =============================================================================
# Cadence Conformal LEC Script for BharatVoice SoC
# Pattern: Matches VIT Lab LEC Class Template exactly
# Usage  : lec -nogui -dofile lec.tcl
# =============================================================================

# 1. Read Foundry Technology Library with -lib flag (Liberty format)
read_library -lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

# 2. Read Golden Design (All 17 SystemVerilog RTL files)
read_design -golden -systemverilog \
    ibex_core.sv \
    boot_rom.sv \
    uart_rx.sv \
    irq_ctrl.sv \
    clint.sv \
    crc_checker.sv \
    transaction_guard.sv \
    power_manager.sv \
    payment_engine.sv \
    audio_engine.sv \
    sram_model.sv \
    sram_controller.sv \
    spi_master.sv \
    spi_controller.sv \
    transaction_cache.sv \
    bus_interconnect.sv \
    bharatvoice_top.sv

set_root_module bharatvoice_top -golden

# 3. Read Revised Design (Synthesized Netlist from Genus)
read_design -revised -verilog ./syn/netlists/bharatvoice_top_netlist.v

set_root_module bharatvoice_top -revised

# 4. Set System Mode to LEC
set_system_mode lec

# 5. Add Compare Points & Compare
add_compared_points -all

compare

# 6. Report Verification
report_verification
report_compare_data -class nonequivalent -class abort -class notcompared
