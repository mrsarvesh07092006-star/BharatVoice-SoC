# ==============================================================================
# Cadence Genus Synthesis Script
# Project : BharatVoice Payment Announcement SoC
# Target  : 50 MHz Clock, ASIC Standard Cell Flow
# File    : syn/scripts/genus_synth.tcl
# ==============================================================================

puts "======================================================================"
puts "Starting Cadence Genus Synthesis for BharatVoice SoC..."
puts "======================================================================"

# ------------------------------------------------------------------------------
# 1. Environment & Multi-Threading Setup
# ------------------------------------------------------------------------------
set_db / .max_print_length 0
set_db / .information_level 7
set_multi_cpu_usage -local_cpu 4

# Create output directories
file mkdir syn/reports
file mkdir syn/outputs

# ------------------------------------------------------------------------------
# 2. Target Library Setup (Configurable for local PDK)
# ------------------------------------------------------------------------------
# Default search path points to standard cell timing & LEF models
set PDK_DIR "/cad/pdk/tsmc65"  ;# Update with local PDK directory (e.g. Nangate45 / SkyWater130 / TSMC65)
set_db init_lib_search_path [list . syn/constraints $PDK_DIR/lib $PDK_DIR/lef]

# Fallback typical standard cell timing model
if {[file exists "$PDK_DIR/lib/tcbn65gpluswc.lib"]} {
    set_db target_library "$PDK_DIR/lib/tcbn65gpluswc.lib"
    set_db link_library   "$PDK_DIR/lib/tcbn65gpluswc.lib"
} else {
    puts "Note: Local PDK standard cell library not specified. Using generic GDK library."
}

# ------------------------------------------------------------------------------
# 3. Read RTL Source Files
# ------------------------------------------------------------------------------
set_db init_hdl_search_path { . }

read_hdl -language sv {
    bus_interconnect.sv
    payment_engine.sv
    spi_master.sv
    spi_controller.sv
    sram_controller.sv
    transaction_cache.sv
    uart_rx.sv
    audio_engine.sv
    crc_checker.sv
    transaction_guard.sv
    power_manager.sv
    irq_ctrl.sv
    clint.sv
    boot_rom.sv
    bharatvoice_top.sv
}

# ------------------------------------------------------------------------------
# 4. Elaboration & Hierarchy Resolution
# ------------------------------------------------------------------------------
puts "--> Elaborating design hierarchy: bharatvoice_top..."
elaborate bharatvoice_top

# Check for unresolved references or latches
check_design -unresolved
check_design -all > syn/reports/bharatvoice_design_check.rpt

# ------------------------------------------------------------------------------
# 5. Apply Timing & Design Constraints
# ------------------------------------------------------------------------------
puts "--> Applying SDC constraints..."
read_sdc syn/constraints/bharatvoice.sdc

# ------------------------------------------------------------------------------
# 6. Generic Synthesis & Logic Optimization (syn_generic)
# ------------------------------------------------------------------------------
puts "--> Running Generic Logic Synthesis..."
set_db syn_generic_effort high
syn_generic

# ------------------------------------------------------------------------------
# 7. Technology Mapping (syn_map)
# ------------------------------------------------------------------------------
puts "--> Mapping design to target standard cells..."
set_db syn_map_effort high
syn_map

# ------------------------------------------------------------------------------
# 8. Post-Mapping Incremental Optimization (syn_opt)
# ------------------------------------------------------------------------------
puts "--> Running Post-Mapping Timing & Area Optimization..."
set_db syn_opt_effort high
syn_opt

# ------------------------------------------------------------------------------
# 9. Generate Synthesis Quality of Results (QoR) Reports
# ------------------------------------------------------------------------------
puts "--> Generating synthesis reports..."
report_qor                        > syn/reports/bharatvoice_qor.rpt
report_area   -depth 2            > syn/reports/bharatvoice_area.rpt
report_timing -max_paths 20       > syn/reports/bharatvoice_timing.rpt
report_power  -hierarchy          > syn/reports/bharatvoice_power.rpt
report_gates  -power              > syn/reports/bharatvoice_gates.rpt
report_clock_gating               > syn/reports/bharatvoice_clock_gating.rpt

# ------------------------------------------------------------------------------
# 10. Write Gate-Level Netlist & Constraints for Back-End Place & Route
# ------------------------------------------------------------------------------
puts "--> Exporting synthesized gate-level netlist and SDC for Cadence Innovus..."
write_hdl -mapped > syn/outputs/bharatvoice_synth.v
write_sdc         > syn/outputs/bharatvoice_synth.sdc

puts "======================================================================"
puts "Cadence Genus Synthesis Completed Successfully!"
puts "======================================================================"
