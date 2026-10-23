# =============================================================================
# Cadence Tempus Static Timing Analysis (STA) Script for BharatVoice SoC
# Adapted for VIT Lab Server 90nm Foundry Setup
# Top Module: bharatvoice_top
# =============================================================================

set design bharatvoice_top
set script_dir [file dirname [file normalize [info script]]]
set cwd        [pwd]

# Locate prj_root
set candidate_roots [list $cwd [file join $cwd ".."] [file join $cwd "../.."] $script_dir [file join $script_dir "../.."] "$::env(HOME)/BharatVoice-SoC"]
set prj_root ""
foreach c $candidate_roots {
    if {[file exists [file join $c "bharatvoice_top.sv"]]} {
        set prj_root [file normalize $c]
        break
    }
}
if {$prj_root == ""} { set prj_root $cwd }

set rep_dir [file join $prj_root "syn/reports"]
file mkdir $rep_dir

# Locate slow.lib
set slow_candidates [list \
    "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib" \
    [file join $prj_root "syn/slow.lib"] \
    [file join $prj_root "slow.lib"] \
    "../synthesis/slow.lib" \
]
set slow_file [lindex $slow_candidates 0]
foreach f $slow_candidates { if {[file exists $f]} { set slow_file $f; break } }

# Locate netlist
set netlist_candidates [list \
    [file join $prj_root "syn/netlists/${design}_netlist.v"] \
    [file join $prj_root "netlists/${design}_netlist.v"] \
    "./syn/netlists/${design}_netlist.v" \
]
set netlist_file [lindex $netlist_candidates 0]
foreach n $netlist_candidates { if {[file exists $n]} { set netlist_file $n; break } }

# Locate SDC
set sdc_candidates [list \
    [file join $prj_root "${design}.sdc"] \
    [file join $prj_root "syn/constraints/bharatvoice.sdc"] \
    "./${design}.sdc" \
]
set sdc_file [lindex $sdc_candidates 0]
foreach s $sdc_candidates { if {[file exists $s]} { set sdc_file $s; break } }

puts "\[INFO\] Reading Timing Lib : $slow_file"
read_lib $slow_file

puts "\[INFO\] Reading Netlist    : $netlist_file"
read_verilog $netlist_file

read_lib -lef {
    /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef
    /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_tech.lef
}

set_top_module $design
read_sdc $sdc_file

save_design -overwrite [file join $rep_dir "${design}_tempus"]

check_design -type timing -out_file [file join $rep_dir "tempus_design.rpt"]
check_library
check_timing
update_timing -full

report_timing
report_timing -late > [file join $rep_dir "setup_tempus.rpt"]
report_timing -early > [file join $rep_dir "hold_tempus.rpt"]
report_timing -max_slack 0

puts "======================================================================="
puts "  TEMPUS STA COMPLETED FOR $design"
puts "  Setup Report : [file join $rep_dir "setup_tempus.rpt"]"
puts "  Hold Report  : [file join $rep_dir "hold_tempus.rpt"]"
puts "======================================================================="
