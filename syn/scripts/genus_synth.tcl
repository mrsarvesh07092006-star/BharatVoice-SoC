# =============================================================================
# Cadence Genus Synthesis Script for BharatVoice SoC
# Adapted for VIT Lab Server 90nm Foundry Setup
# Top Module: bharatvoice_top
# =============================================================================

set design bharatvoice_top
set rep_dir syn/reports
set net_dir syn/netlists

# Create output directories if they don't exist
file mkdir $rep_dir
file mkdir $net_dir

# -----------------------------------------------------------------------------
# 1. Locate Technology Timing Library
# -----------------------------------------------------------------------------
set lib_candidates [list \
    "typical.lib" \
    "./typical.lib" \
    "../synthesis/typical.lib" \
    "syn/typical.lib" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/gsclib090_typical.lib" \
]

set target_lib ""
foreach l $lib_candidates {
    if {[file exists $l]} {
        set target_lib $l
        break
    }
}

if {$target_lib == ""} {
    puts "\[WARNING\] typical.lib not found in standard paths, defaulting to ./typical.lib"
    set target_lib "typical.lib"
}

puts "\[INFO\] Using timing library: $target_lib"
read_libs $target_lib

# -----------------------------------------------------------------------------
# 2. Read All SystemVerilog Source Files
# -----------------------------------------------------------------------------
set hdl_files [list \
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
    bharatvoice_top.sv \
]

read_hdl -language sv $hdl_files

# -----------------------------------------------------------------------------
# 3. Elaboration
# -----------------------------------------------------------------------------
elaborate $design
current_design $design

# -----------------------------------------------------------------------------
# 4. Timing Constraints (SDC)
# -----------------------------------------------------------------------------
# Clock target: 50 MHz (Period = 20.0 ns)
create_clock -name clk_i -period 20.0 [get_ports clk_i]

set_input_delay 3.0 [remove_from_collection [all_inputs] [get_ports clk_i]] -clock [get_clocks clk_i]
set_output_delay 3.0 [all_outputs] -clock [get_clocks clk_i]

set_max_fanout 1.000 [current_design]
set_max_transition 0.5 [current_design]

set_db syn_generic_effort medium
set_db syn_opt_effort medium
set_db syn_map_effort medium

# -----------------------------------------------------------------------------
# 5. Synthesis & Optimization Stages
# -----------------------------------------------------------------------------
puts "\[INFO\] Running syn_generic..."
syn_generic
write_hdl > ./${net_dir}/${design}_ti_netlist.v

puts "\[INFO\] Running syn_map..."
syn_map
write_hdl > ./${net_dir}/${design}_tm_netlist.v

puts "\[INFO\] Running syn_opt..."
syn_opt
write_hdl > ./${net_dir}/${design}_netlist.v

# Export post-synthesis SDC
write_sdc > ./${design}.sdc
write_sdc > syn/constraints/${design}.sdc

# -----------------------------------------------------------------------------
# 6. Generate Synthesis QoR Reports
# -----------------------------------------------------------------------------
report_area > ./${rep_dir}/${design}_area.rpt
report_power > ./${rep_dir}/${design}_power.rpt
report_timing > ./${rep_dir}/${design}_timing.rpt
report_qor > ./${rep_dir}/${design}_qor.rpt

puts "======================================================================="
puts "  GENUS SYNTHESIS COMPLETED FOR $design"
puts "  Netlist : ./${net_dir}/${design}_netlist.v"
puts "  SDC     : ./${design}.sdc"
puts "  Reports : ./${rep_dir}/"
puts "======================================================================="
