# =============================================================================
# Cadence Innovus Physical Design (PnR) Script for BharatVoice SoC
# Adapted for VIT Lab Server 90nm Foundry Setup
# Top Module: bharatvoice_top
# =============================================================================

# -----------------------------------------------------------------------------
# 0. Automatically Determine Project Root Directory
# -----------------------------------------------------------------------------
set script_path [file normalize [info script]]
set script_dir  [file dirname $script_path]

if {[file exists [file join $script_dir "../../bharatvoice_top.sv"]]} {
    set prj_root [file normalize [file join $script_dir "../.."]]
} elseif {[file exists [file join $script_dir "../bharatvoice_top.sv"]]} {
    set prj_root [file normalize [file join $script_dir ".."]]
} elseif {[file exists "./bharatvoice_top.sv"]} {
    set prj_root [file normalize "."]
} else {
    set prj_root [pwd]
}

puts "\[INFO\] Project root directory identified as: $prj_root"

# -----------------------------------------------------------------------------
# 1. Design Initialization & MMMC Setup
# -----------------------------------------------------------------------------
proc init_design_flow {} {
    global init_lef_file
    global init_verilog
    global init_top_cell
    global prj_root

    # Read physical libraries (90nm Foundry LEF files)
    set init_lef_file {
        /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef
        /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_tech.lef
    }

    # Locate synthesized gate-level netlist
    set netlist_candidates [list \
        [file join $prj_root "syn/netlists/bharatvoice_top_netlist.v"] \
        [file join $prj_root "netlists/bharatvoice_top_netlist.v"] \
        "./syn/netlists/bharatvoice_top_netlist.v" \
        "./netlists/bharatvoice_top_netlist.v" \
        "../synthesis/netlists/bharatvoice_top_netlist.v" \
    ]

    set init_verilog [lindex $netlist_candidates 0]
    foreach n $netlist_candidates {
        if {[file exists $n]} { set init_verilog $n; break }
    }

    set init_top_cell bharatvoice_top

    set ::init_pwr_net {VDD}
    set ::init_gnd_net {VSS}

    # Locate timing libraries (.lib)
    set slow_candidates [list \
        "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib" \
        [file join $prj_root "syn/slow.lib"] \
        [file join $prj_root "slow.lib"] \
        "../synthesis/slow.lib" \
    ]
    set typ_candidates [list \
        "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib" \
        [file join $prj_root "syn/typical.lib"] \
        [file join $prj_root "typical.lib"] \
        "../synthesis/typical.lib" \
    ]
    set fast_candidates [list \
        "/home/cadence/install/FOUNDRY/digital/90nm/dig/lib/fast.lib" \
        [file join $prj_root "syn/fast.lib"] \
        [file join $prj_root "fast.lib"] \
        "../synthesis/fast.lib" \
    ]

    set slow_file [lindex $slow_candidates 0]
    foreach f $slow_candidates { if {[file exists $f]} { set slow_file $f; break } }

    set typ_file [lindex $typ_candidates 0]
    foreach f $typ_candidates { if {[file exists $f]} { set typ_file $f; break } }

    set fast_file [lindex $fast_candidates 0]
    foreach f $fast_candidates { if {[file exists $f]} { set fast_file $f; break } }

    # Locate SDC constraints
    set sdc_candidates [list \
        [file join $prj_root "bharatvoice_top.sdc"] \
        [file join $prj_root "syn/constraints/bharatvoice.sdc"] \
        "./bharatvoice_top.sdc" \
        "../synthesis/bharatvoice_top.sdc" \
    ]
    set sdc_file [lindex $sdc_candidates 0]
    foreach s $sdc_candidates { if {[file exists $s]} { set sdc_file $s; break } }

    puts "\[INFO\] Using Netlist : $init_verilog"
    puts "\[INFO\] Using SDC     : $sdc_file"
    puts "\[INFO\] Using Slow Lib: $slow_file"

    # Timing libraries
    create_library_set -name slow_lib    -timing [list $slow_file]
    create_library_set -name typical_lib -timing [list $typ_file]
    create_library_set -name fast_lib    -timing [list $fast_file]

    # Constraint modes
    create_constraint_mode -name func_mode -sdc_files [list $sdc_file]

    # Delay corners
    create_delay_corner -name slow_corner    -library_set slow_lib
    create_delay_corner -name typical_corner -library_set typical_lib
    create_delay_corner -name fast_corner    -library_set fast_lib

    # Analysis views
    create_analysis_view -name slow_view    -constraint_mode func_mode -delay_corner slow_corner
    create_analysis_view -name typical_view -constraint_mode func_mode -delay_corner typical_corner
    create_analysis_view -name fast_view    -constraint_mode func_mode -delay_corner fast_corner

    # Initialize design
    init_design -setup slow_view -hold fast_view

    # Set active views
    set_analysis_view -setup {slow_view} -hold {fast_view}

    # Basic checks
    checkDesign -all

    # Save checkpoint
    saveDesign 01_init
}

# -----------------------------------------------------------------------------
# 2. Floorplanning & Pin Placement
# -----------------------------------------------------------------------------
proc floorplan {} {
    # 70% utilization, aspect ratio 1.0 (square die), 10.15 um core margins
    floorPlan -site gsclib090site -r 1.0 0.70 10.15 10.15 10.15 10.15

    # Top Pins: System Clock and Active-Low Reset
    editPin -pinWidth 0.12 -pinDepth 0.585 -fixOverlap 1 -spreadDirection clockwise -side Top -layer 1 -spreadType side \
        -pin {clk_i rst_ni}

    # Bottom Pins: Audio PWM output and Power Manager handshake
    editPin -fixOverlap 1 -spreadDirection clockwise -side Bottom -layer 1 -spreadType side \
        -pin {audio_pwm_o audio_sd_o pwr_sleep_req_o pwr_ack_i}

    # Left Pins: UART Telemetry Receiver and Interrupts
    editPin -fixOverlap 1 -spreadDirection clockwise -side Left -layer 2 -spreadType side \
        -pin {uart_rx_i ext_irq_i timer_irq_o}

    # Right Pins: SPI Master interface (SCK, CS_N, MOSI, MISO)
    editPin -fixOverlap 1 -spreadDirection clockwise -side Right -layer 2 -spreadType side \
        -pin {spi_sck_o spi_cs_n_o spi_mosi_o spi_miso_i}

    saveDesign bharatvoice_top
}

# -----------------------------------------------------------------------------
# 3. Power Distribution Network (PDN)
# -----------------------------------------------------------------------------
proc power_plan {} {
    globalNetConnect VDD -type pgpin -pin VDD -all
    globalNetConnect VSS -type pgpin -pin VSS -all

    # Core Power Rings (M3 Horizontal, M4 Vertical)
    addRing -nets {VDD VSS} -type core_rings -follow core \
        -layer {top Metal3 bottom Metal3 left Metal4 right Metal4} \
        -width {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -spacing {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -offset {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None

    # Horizontal Power Stripes (M3)
    addStripe -nets {VDD VSS} -layer Metal3 -direction horizontal -width 1.8 -spacing 1.8 \
        -set_to_set_distance 20 -start_from bottom -start_offset 10 -switch_layer_over_obs false \
        -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit Metal9 -padcore_ring_bottom_layer_limit Metal1 \
        -block_ring_top_layer_limit Metal9 -block_ring_bottom_layer_limit Metal1 -use_wire_group 0 -snap_wire_center_to_grid None

    # Vertical Power Stripes (M4)
    addStripe -nets {VDD VSS} -layer Metal4 -direction vertical -width 1.8 -spacing 1.8 \
        -set_to_set_distance 20 -start_from left -start_offset 10 -switch_layer_over_obs false \
        -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit Metal9 -padcore_ring_bottom_layer_limit Metal1 \
        -block_ring_top_layer_limit Metal9 -block_ring_bottom_layer_limit Metal1 -use_wire_group 0 -snap_wire_center_to_grid None

    saveDesign bharatvoice_top

    # Special Route (Standard Cell M1 Follow-Pin Rails)
    setSrouteMode -viaConnectToShape { noshape }
    sroute -connect { blockPin padPin padRing corePin floatingStripe } \
        -layerChangeRange { Metal1(1) Metal5(5) } \
        -blockPinTarget { nearestTarget } \
        -padPinPortConnect { allPort oneGeom } \
        -padPinTarget { nearestTarget } \
        -corePinTarget { firstAfterRowEnd } \
        -floatingStripeTarget { blockring padring ring stripe ringpin blockpin followpin } \
        -allowJogging 1 \
        -crossoverViaLayerRange { Metal1(1) Metal9(9) } \
        -nets { VDD VSS } \
        -allowLayerChange 1 \
        -blockPin useLef \
        -targetViaLayerRange { Metal1(1) Metal9(9) }
}

# -----------------------------------------------------------------------------
# 4. Standard Cell Placement
# -----------------------------------------------------------------------------
proc placement {} {
    place_design
    saveDesign bharatvoice_top
}

# -----------------------------------------------------------------------------
# 5. Clock Tree Synthesis (CCOpt)
# -----------------------------------------------------------------------------
proc cts {} {
    set_ccopt_property target_max_trans 0.5
    set_ccopt_property buffer_cells {CLKBUFX2 CLKBUFX20 CLKBUFX3 CLKBUFX4 CLKBUFX6 CLKBUFX8 CLKBUFX12 CLKBUFX16}
    set_ccopt_property inverter_cells {CLKINVX1 CLKINVX12 CLKINVX16 CLKINVX2 CLKINV20 CLKINVX3 CLKINVX4 CLKINVX6 CLKINVX8}

    # Run CCOpt Clock Tree Synthesis
    ccopt_design -cts
    report_ccopt_clock_trees -file cts_clock_trees.rpt
    report_ccopt_skew_groups -file cts_skew_groups.rpt

    timeDesign -postCTS -outDir ./postCTS
    saveDesign 05_cts
}

# -----------------------------------------------------------------------------
# 6. Detail Routing (NanoRoute)
# -----------------------------------------------------------------------------
proc routing {} {
    setNanoRouteMode -quiet -routeWithTimingDriven 1
    setNanoRouteMode -quiet -routeTdrEffort 1
    setNanoRouteMode -quiet -routeTopRoutingLayer 7
    setNanoRouteMode -quiet -routeBottomRoutingLayer 1
    setNanoRouteMode -quiet -drouteEndIteration 1
    setNanoRouteMode -quiet -routeWithTimingDriven true
    setNanoRouteMode -quiet -routeWithSiDriven false
    routeDesign -globalDetail

    setAnalysisMode -analysisType onChipVariation -cppr both
    routeDesign -trackopt
    saveDesign 06_route
}

# -----------------------------------------------------------------------------
# 7. Physical Verification & Signoff (DRC, LVS, GDSII)
# -----------------------------------------------------------------------------
proc signoff {} {
    global prj_root

    set out_dir [file join $prj_root "output"]
    set rep_dir [file join $prj_root "pnr/reports"]
    file mkdir $out_dir
    file mkdir $rep_dir

    # DRC & Connectivity checks
    verify_drc -report [file join $rep_dir "innovus_drc.rpt"] -limit 1000
    verify_connectivity -type all -report [file join $rep_dir "innovus_lvs.rpt"]

    # Stream out final tapeout GDSII
    streamOut [file join $out_dir "bharatvoice_top.gds"] \
        -libName bharatvoice_top \
        -merge /home/cadence/install/FOUNDRY/digital/90nm/dig/gds/gsclib090.gds \
        -units 1000 \
        -mode ALL

    puts "======================================================================="
    puts "  INNOVUS PHYSICAL DESIGN COMPLETED FOR bharatvoice_top"
    puts "  GDSII   : [file join $out_dir "bharatvoice_top.gds"]"
    puts "  Reports : $rep_dir"
    puts "======================================================================="
}

# -----------------------------------------------------------------------------
# Main Execution Pipeline
# -----------------------------------------------------------------------------
init_design_flow
floorplan
power_plan
placement
cts
routing
signoff
