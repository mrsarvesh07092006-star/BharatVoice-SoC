# =============================================================================
# Cadence Tempus STA Script - BharatVoice SoC
# Adapted from VIT Lab Class Template (alu_demo -> bharatvoice_top)
# Tool   : Cadence Tempus (tempus -f syn/scripts/tempus_sta.tcl)
# =============================================================================

# 1. Read Slow-Corner Library (Liberty .lib for setup/worst-case analysis)
set slow_lib "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib"
if {![file exists $slow_lib]} {
    set slow_lib "./scripts/slow.lib"
}
if {![file exists $slow_lib]} {
    set slow_lib "syn/typical.lib"
}
read_lib $slow_lib

# 2. Read Synthesized Gate-Level Netlist
set netlist "./syn/netlists/bharatvoice_top_netlist.v"
if {![file exists $netlist]} {
    set netlist "./bharatvoice_top_netlist.v"
}
read_verilog $netlist

# 3. Read Physical LEF Files (Technology + Standard Cell LEFs)
read_lib -lef {
    /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef
    /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_tech.lef
}

# 4. Set Top Module
set_top_module bharatvoice_top

# 5. Read SDC Timing Constraints
set sdc_file "./syn/constraints/bharatvoice.sdc"
if {![file exists $sdc_file]} {
    set sdc_file "./bharatvoice.sdc"
}
read_sdc $sdc_file

# 6. Save Design Checkpoint
save_design -overwrite bharatvoice_top_tempus

# 7. Design & Library Checks
check_design -type timing -out_file syn/reports/design.rpt

check_library
check_timing
update_timing -full

# 8. Setup & Hold Timing Reports
report_timing

report_timing -late  > syn/reports/setup_tempus.rpt
report_timing -early > syn/reports/hold_tempus.rpt
report_timing -max_slack 0

report_timing -early -max_slack 0 -max_path 20
