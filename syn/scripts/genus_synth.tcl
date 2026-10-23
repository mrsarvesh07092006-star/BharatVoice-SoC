# =============================================================================
# Cadence Genus Synthesis Script for BharatVoice SoC
# Top Module: bharatvoice_top
# =============================================================================

set design bharatvoice_top

# -----------------------------------------------------------------------------
# 0. Automatically Locate Project Root Directory
# -----------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set cwd        [pwd]

set candidate_roots [list \
    $cwd \
    [file join $cwd ".."] \
    [file join $cwd "../.."] \
    [file join $cwd "../../.."] \
    $script_dir \
    [file join $script_dir ".."] \
    [file join $script_dir "../.."] \
    "$::env(HOME)/BharatVoice-SoC" \
]

set prj_root ""
foreach c $candidate_roots {
    set test_file [file normalize [file join $c "bharatvoice_top.sv"]]
    if {[file exists $test_file]} {
        set prj_root [file dirname $test_file]
        break
    }
}

if {$prj_root == ""} {
    set prj_root $cwd
}

puts "====================================================================="
puts "\[INFO\] Found BharatVoice Project Root : $prj_root"
puts "\[INFO\] Current Working Directory     : $cwd"
puts "====================================================================="

set rep_dir [file join $prj_root "syn/reports"]
set net_dir [file join $prj_root "syn/netlists"]

file mkdir $rep_dir
file mkdir $net_dir

# -----------------------------------------------------------------------------
# 1. Locate Technology Timing Library
# -----------------------------------------------------------------------------
set lib_candidates [list \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/gsclib090_typical.lib" \
    [file join $prj_root "typical.lib"] \
    [file join $prj_root "syn/typical.lib"] \
    "typical.lib" \
    "../synthesis/typical.lib" \
]

set target_lib ""
foreach l $lib_candidates {
    if {[file exists $l]} {
        set target_lib $l
        break
    }
}

if {$target_lib == ""} {
    set target_lib "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib"
}

puts "\[INFO\] Using timing library: $target_lib"
read_libs $target_lib

# -----------------------------------------------------------------------------
# 2. Read All SystemVerilog Source Files with Absolute Paths
# -----------------------------------------------------------------------------
set hdl_files [list \
    [file normalize [file join $prj_root "ibex_core.sv"]] \
    [file normalize [file join $prj_root "boot_rom.sv"]] \
    [file normalize [file join $prj_root "uart_rx.sv"]] \
    [file normalize [file join $prj_root "irq_ctrl.sv"]] \
    [file normalize [file join $prj_root "clint.sv"]] \
    [file normalize [file join $prj_root "crc_checker.sv"]] \
    [file normalize [file join $prj_root "transaction_guard.sv"]] \
    [file normalize [file join $prj_root "power_manager.sv"]] \
    [file normalize [file join $prj_root "payment_engine.sv"]] \
    [file normalize [file join $prj_root "audio_engine.sv"]] \
    [file normalize [file join $prj_root "sram_model.sv"]] \
    [file normalize [file join $prj_root "sram_controller.sv"]] \
    [file normalize [file join $prj_root "spi_master.sv"]] \
    [file normalize [file join $prj_root "spi_controller.sv"]] \
    [file normalize [file join $prj_root "transaction_cache.sv"]] \
    [file normalize [file join $prj_root "bus_interconnect.sv"]] \
    [file normalize [file join $prj_root "bharatvoice_top.sv"]] \
]

puts "\[INFO\] Reading SystemVerilog files..."
read_hdl -language sv $hdl_files

# -----------------------------------------------------------------------------
# 3. Elaboration
# -----------------------------------------------------------------------------
puts "\[INFO\] Elaborating top design: $design..."
elaborate $design
current_design $design

# -----------------------------------------------------------------------------
# 4. Timing Constraints (SDC)
# -----------------------------------------------------------------------------
create_clock -name clk_i -period 20.0 [get_ports clk_i]
set_input_delay 3.0 [remove_from_collection [all_inputs] [get_ports clk_i]] -clock [get_clocks clk_i]
set_output_delay 3.0 [all_outputs] -clock [get_clocks clk_i]

set_max_fanout 16.0 [current_design]
set_max_transition 0.5 [current_design]

set_db syn_generic_effort medium
set_db syn_opt_effort medium
set_db syn_map_effort medium

# -----------------------------------------------------------------------------
# 5. Synthesis & Optimization Stages
# -----------------------------------------------------------------------------
puts "\[INFO\] Running syn_generic..."
syn_generic
write_hdl > [file join $net_dir "${design}_ti_netlist.v"]

puts "\[INFO\] Running syn_map..."
syn_map
write_hdl > [file join $net_dir "${design}_tm_netlist.v"]

puts "\[INFO\] Running syn_opt..."
syn_opt
write_hdl > [file join $net_dir "${design}_netlist.v"]

# Export post-synthesis SDC
write_sdc > [file join $prj_root "${design}.sdc"]
write_sdc > [file join $prj_root "syn/constraints/${design}.sdc"]

# -----------------------------------------------------------------------------
# 6. Generate Synthesis QoR Reports
# -----------------------------------------------------------------------------
report_area > [file join $rep_dir "${design}_area.rpt"]
report_power > [file join $rep_dir "${design}_power.rpt"]
report_timing > [file join $rep_dir "${design}_timing.rpt"]
report_qor > [file join $rep_dir "${design}_qor.rpt"]

puts "======================================================================="
puts "  GENUS SYNTHESIS COMPLETED FOR $design"
puts "  Netlist : [file join $net_dir "${design}_netlist.v"]"
puts "  SDC     : [file join $prj_root "${design}.sdc"]"
puts "  Reports : $rep_dir"
puts "======================================================================="
