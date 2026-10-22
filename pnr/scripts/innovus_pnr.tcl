# ==============================================================================
# Cadence Innovus Physical Design (PnR) Implementation Script
# Project : BharatVoice Payment Announcement SoC
# Target  : 50 MHz, Multi-Metal Layer Standard Cell Flow
# File    : pnr/scripts/innovus_pnr.tcl
# ==============================================================================

puts "======================================================================"
puts "Starting Cadence Innovus Place & Route Flow for BharatVoice SoC..."
puts "======================================================================"

# Create output directories
file mkdir pnr/reports
file mkdir pnr/outputs

# ------------------------------------------------------------------------------
# 1. Design Import & Initialization
# ------------------------------------------------------------------------------
set init_gnd_net VSS
set init_pwr_net VDD
set init_verilog "syn/outputs/bharatvoice_synth.v"
set init_top_cell "bharatvoice_top"
set init_mmmc_file "pnr/scripts/mmmc.view"

# Initialize design with technology LEF and gate-level netlist
init_design

# Connect global power and ground nets
globalNetConnect VDD -type pgpin -pin VDD -inst *
globalNetConnect VSS -type pgpin -pin VSS -inst *
globalNetConnect VDD -type tiehi -inst *
globalNetConnect VSS -type tielo -inst *

# ------------------------------------------------------------------------------
# 2. Floorplanning & Die Area Budgeting
# ------------------------------------------------------------------------------
puts "--> Step 2: Creating Floorplan..."
# Aspect Ratio = 1.0 (Square Die), Target Utilization = 70% (0.70)
# Core-to-Die Margins = 15 um (Left, Bottom, Right, Top) for Power Rings
floorPlan -r 1.0 0.70 15.0 15.0 15.0 15.0

# Legalize and distribute IO boundary pins
editPin -pin * -spreadType start -edge top -spacing 2.0

# ------------------------------------------------------------------------------
# 3. Power Planning (Power Distribution Network - PDN)
# ------------------------------------------------------------------------------
puts "--> Step 3: Constructing Power Distribution Network (Rings & Stripes)..."

# Add Core Power Rings (M5 / M6)
addRing -nets {VDD VSS} \
        -type core_rings \
        -follow core \
        -layer {top Metal6 bottom Metal6 left Metal5 right Metal5} \
        -width 2.0 \
        -spacing 1.0 \
        -offset 2.0

# Add Vertical and Horizontal Power Stripes (M5) for low IR-drop mesh
addStripe -nets {VDD VSS} \
          -layer Metal5 \
          -direction vertical \
          -width 1.5 \
          -spacing 1.0 \
          -set_to_set_distance 25.0 \
          -start_offset 10.0

# Special Route (sroute) for Standard Cell Follow-Pin Power Rails (M1)
sroute -connect {corePin} \
       -nets {VDD VSS} \
       -layerChangeRange {Metal1 Metal6}

# ------------------------------------------------------------------------------
# 4. Standard Cell Placement & Pre-CTS Optimization
# ------------------------------------------------------------------------------
puts "--> Step 4: Placing Standard Cells..."
setPlaceMode -prerouteAddSlackThreshold 0.1
setPlaceMode -timingDriven true
setPlaceMode -congEffort high

place_opt_design

# Check post-placement timing
timeDesign -preCTS -outDir pnr/reports/preCTS_timing

# ------------------------------------------------------------------------------
# 5. Clock Tree Synthesis (CTS) via CCOpt
# ------------------------------------------------------------------------------
puts "--> Step 5: Synthesizing Clock Tree (CCOpt)..."
create_ccopt_clock_tree_spec -file pnr/outputs/ccopt.spec
source pnr/outputs/ccopt.spec

set_ccopt_property target_skew 0.050
set_ccopt_property target_max_trans 0.150
ccopt_design

# Check post-CTS timing and clock metrics
timeDesign -postCTS -outDir pnr/reports/postCTS_timing
report_ccopt_clock_trees -file pnr/reports/innovus_cts.rpt

# ------------------------------------------------------------------------------
# 6. Detailed Routing (NanoRoute)
# ------------------------------------------------------------------------------
puts "--> Step 6: Detailed Routing with NanoRoute..."
setNanoRouteMode -quiet -routeWithTimingDriven true
setNanoRouteMode -quiet -routeWithSiDriven true
setNanoRouteMode -quiet -drouteFixAntenna true
setNanoRouteMode -quiet -routeInsertAntennaDiode true

routeDesign

# ------------------------------------------------------------------------------
# 7. Post-Route Timing Optimization & Closure
# ------------------------------------------------------------------------------
puts "--> Step 7: Performing Post-Route Timing Optimization..."
optDesign -postRoute
optDesign -postRoute -hold

timeDesign -postRoute -outDir pnr/reports/postRoute_timing
timeDesign -postRoute -hold -outDir pnr/reports/postRoute_hold_timing

# ------------------------------------------------------------------------------
# 8. Physical Verification: Filler Cell Insertion, DRC, and LVS
# ------------------------------------------------------------------------------
puts "--> Step 8: Adding Filler Cells & Running Physical Verification (DRC/LVS)..."
addFiller -cell {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} -prefix FILLER_

# Verify Design Rules (DRC)
verify_drc -report pnr/reports/innovus_drc.rpt -limit 1000

# Verify Connectivity (LVS Netlist Match)
verify_connectivity -report pnr/reports/innovus_lvs.rpt -type all -error 1000

# Verify Metal Density
verify_metal_density -report pnr/reports/innovus_density.rpt

# ------------------------------------------------------------------------------
# 9. GDSII Export & Design Archival
# ------------------------------------------------------------------------------
puts "--> Step 9: Exporting GDSII Stream..."
streamOut pnr/outputs/bharatvoice.gds \
          -mapFile "pnr/scripts/gds2.map" \
          -libName "BharatVoiceLib" \
          -structureName "bharatvoice_top" \
          -stripes 1 \
          -units 1000

saveDesign pnr/outputs/bharatvoice_final.enc

puts "======================================================================"
puts "Cadence Innovus Back-End Implementation Completed Cleanly!"
puts "======================================================================"
