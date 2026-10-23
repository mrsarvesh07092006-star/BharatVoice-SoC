# =============================================================================
# Cadence Tempus Static Timing Analysis (STA) Script for BharatVoice SoC
# Adapted for VIT Lab Server 90nm Foundry Setup
# Top Module: bharatvoice_top
# =============================================================================

set design bharatvoice_top
set rep_dir syn/reports

# Locate slow.lib
set slow_candidates [list "./syn/slow.lib" "./slow.lib" "../synthesis/slow.lib" "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib"]
set slow_file [lindex $slow_candidates 0]
foreach f $slow_candidates { if {[file exists $f]} { set slow_file $f; break } }

# Locate netlist
if {[file exists ./syn/netlists/${design}_netlist.v]} {
    set netlist_file ./syn/netlists/${design}_netlist.v
} elseif {[file exists ./netlists/${design}_netlist.v]} {
    set netlist_file ./netlists/${design}_netlist.v
} else {
    set netlist_file ./syn/netlists/${design}_netlist.v
}

# Locate SDC
if {[file exists ./${design}.sdc]} {
    set sdc_file ./${design}.sdc
} elseif {[file exists ./syn/constraints/bharatvoice.sdc]} {
    set sdc_file ./syn/constraints/bharatvoice.sdc
} else {
    set sdc_file ./syn/constraints/bharatvoice.sdc
}

read_lib $slow_file
read_verilog $netlist_file

read_lib -lef {
    /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef
    /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_tech.lef
}

set_top_module $design
read_sdc $sdc_file

save_design -overwrite ${design}_tempus

check_design -type timing -out_file ${rep_dir}/tempus_design.rpt
check_library
check_timing
update_timing -full

report_timing
report_timing -late > ${rep_dir}/setup_tempus.rpt
report_timing -early > ${rep_dir}/hold_tempus.rpt
report_timing -max_slack 0

puts "======================================================================="
puts "  TEMPUS STA COMPLETED FOR $design"
puts "  Setup Report : ${rep_dir}/setup_tempus.rpt"
puts "  Hold Report  : ${rep_dir}/hold_tempus.rpt"
puts "======================================================================="
