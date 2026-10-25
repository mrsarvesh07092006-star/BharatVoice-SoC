# =============================================================================
# Cadence Tempus STA Script for BharatVoice SoC
# Tool   : Tempus (tempus -f syn/scripts/tempus_sta.tcl)
# Run from project root: /home/userdata/24bvd0092/asic_proj/BharatVoice-SoC
# Pattern: Matches VIT Lab class Tempus template exactly
# =============================================================================

# 1. Read Slow-Corner Library (Liberty .lib — for setup/late analysis)
read_lib /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib

# 2. Read Synthesized Gate-Level Netlist
read_verilog syn/netlists/bharatvoice_top_netlist.v

# 3. Read Physical LEF Files (technology + standard cell)
read_lib -lef {
    /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef
    /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_tech.lef
}

# 4. Set Top Module
set_top_module bharatvoice_top

# 5. Read SDC Timing Constraints
read_sdc syn/constraints/bharatvoice.sdc

# 6. Save Design Checkpoint
save_design -overwrite syn/reports/bharatvoice_top_tempus

# 7. Design & Library Checks
check_design -type timing -out_file syn/reports/tempus_design.rpt

check_library
check_timing
update_timing -full

# 8. Setup Timing Report (Late / Worst-case)
report_timing

report_timing -late  > syn/reports/bharatvoice_setup_tempus.rpt
report_timing -early > syn/reports/bharatvoice_hold_tempus.rpt
report_timing -max_slack 0

report_timing -early -max_slack 0 -max_path 20
