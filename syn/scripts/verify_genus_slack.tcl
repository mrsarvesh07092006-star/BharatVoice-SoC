# =============================================================================
# Cadence Genus Slack Verification Script
# Design: BharatVoice SoC (bharatvoice_top)
# Tool  : Genus Synthesis Solution (genus -f syn/scripts/verify_genus_slack.tcl)
# =============================================================================

set design bharatvoice_top

# Disable interactive paging
catch {set_attribute ui_pager none /}
catch {set_db ui_pager none}

# 1. Read technology library
set lib_candidates [list \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib" \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/gsclib090_typical.lib" \
    "typical.lib" \
    "syn/typical.lib" \
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

puts "\[INFO\] Reading timing library: $target_lib"
read_libs $target_lib

# 2. Read synthesized netlist
set netlist "syn/netlists/bharatvoice_top_netlist.v"
if {![file exists $netlist]} {
    set netlist "syn/netlists/${design}_netlist.v"
}
puts "\[INFO\] Reading synthesized gate-level netlist: $netlist"
read_netlist $netlist -top $design

# 3. Read timing constraints
set sdc_file "syn/constraints/bharatvoice.sdc"
if {![file exists $sdc_file]} {
    set sdc_file "${design}.sdc"
}
puts "\[INFO\] Reading SDC timing constraints: $sdc_file"
read_sdc $sdc_file

# 4. Verify Timing and Slack
puts "======================================================================="
puts "           CADENCE GENUS TIMING & SLACK VERIFICATION                   "
puts "======================================================================="

check_timing_intent
report_timing -summary
report_timing -max_paths 10 > syn/reports/verified_genus_timing.rpt
report_qor > syn/reports/verified_genus_qor.rpt

catch {
    set wns [get_db [get_db cost_groups *] .worst_slack]
    puts "\[INFO\] Worst Slack across all cost groups: $wns"
}

puts "======================================================================="
puts "  GENUS SLACK VERIFICATION COMPLETED"
puts "  Reports: syn/reports/verified_genus_timing.rpt"
puts "           syn/reports/verified_genus_qor.rpt"
puts "======================================================================="
exit
