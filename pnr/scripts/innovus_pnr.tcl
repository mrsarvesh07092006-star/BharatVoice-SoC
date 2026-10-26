# =============================================================================
# Cadence Innovus Physical Design (PnR) Script for BharatVoice SoC
# Adapted for VIT Lab 90nm Flow (Top Module: bharatvoice_top)
# =============================================================================

# 1. Initialization & MMMC Setup
proc init_design_flow {} {
    global init_lef_file
    global init_verilog
    global init_top_cell

    # Read physical libraries (90nm LEF files)
    set init_lef_file {
        /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef
        /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_tech.lef
    }

    set init_verilog ./syn/netlists/bharatvoice_top_netlist.v
    set init_top_cell bharatvoice_top

    set ::init_pwr_net {VDD}
    set ::init_gnd_net {VSS}

    # Timing libraries (Slow, Typical, Fast)
    create_library_set -name slow_lib \
        -timing [list /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib]

    create_library_set -name typical_lib \
        -timing [list /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib]

    create_library_set -name fast_lib \
        -timing [list /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/fast.lib]

    # Constraint mode (SDC)
    set sdc_file ./syn/constraints/bharatvoice.sdc
    if {![file exists $sdc_file]} {
        set sdc_file ./bharatvoice_top.sdc
    }
    create_constraint_mode -name func_mode \
        -sdc_files [list $sdc_file]

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

# 2. Floorplanning & Pin Placement
proc floorplan {} {
    floorPlan -site gsclib090site -r 1.0 0.70 10.15 10.15 10.15 10.15

    # Clock & Reset -> TOP
    editPin -pinWidth 0.12 -pinDepth 0.585 -fixOverlap 1 -spreadDirection clockwise -side Top -layer 1 -spreadType side \
        -pin {clk_i rst_ni}

    # PWM Audio & GPIOs -> BOTTOM
    editPin -fixOverlap 1 -spreadDirection clockwise -side Bottom -layer 1 -spreadType side \
        -pin {pwm_audio_o {gpio_o[0]} {gpio_o[1]} {gpio_o[2]} {gpio_o[3]}}

    # UART & JTAG -> LEFT
    editPin -fixOverlap 1 -spreadDirection clockwise -side Left -layer 2 -spreadType side \
        -pin {uart_rx_i jtag_tck_i jtag_tms_i jtag_tdi_i jtag_tdo_o}

    # SPI Interface -> RIGHT
    editPin -fixOverlap 1 -spreadDirection clockwise -side Right -layer 2 -spreadType side \
        -pin {spi_sclk_o spi_cs_n_o spi_mosi_o spi_miso_i}

    saveDesign 02_floorplan
}

# 3. Power Distribution Network (PDN)
proc power_plan {} {
    globalNetConnect VDD -type pgpin -pin VDD -all
    globalNetConnect VSS -type pgpin -pin VSS -all

    addRing -nets {VDD VSS} -type core_rings -follow core \
        -layer {top Metal3 bottom Metal3 left Metal4 right Metal4} \
        -width {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -spacing {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -offset {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None

    addStripe -nets {VDD VSS} -layer Metal3 -direction horizontal -width 1.8 -spacing 1.8 \
        -set_to_set_distance 20 -start_from bottom -start_offset 10 -switch_layer_over_obs false \
        -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit Metal9 -padcore_ring_bottom_layer_limit Metal1 \
        -block_ring_top_layer_limit Metal9 -block_ring_bottom_layer_limit Metal1 -use_wire_group 0 -snap_wire_center_to_grid None

    addStripe -nets {VDD VSS} -layer Metal4 -direction vertical -width 1.8 -spacing 1.8 \
        -set_to_set_distance 20 -start_from left -start_offset 10 -switch_layer_over_obs false \
        -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit Metal9 -padcore_ring_bottom_layer_limit Metal1 \
        -block_ring_top_layer_limit Metal9 -block_ring_bottom_layer_limit Metal1 -use_wire_group 0 -snap_wire_center_to_grid None

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

    saveDesign 03_power
}

# 4. Standard Cell Placement
proc placement {} {
    place_design
    saveDesign 04_placement
}

# 5. Clock Tree Synthesis (CCOpt)
proc cts {} {
    set_ccopt_property target_max_trans 0.5
    set_ccopt_property buffer_cells {CLKBUFX2 CLKBUFX20 CLKBUFX3 CLKBUFX4 CLKBUFX6 CLKBUFX8 CLKBUFX12 CLKBUFX16}
    set_ccopt_property inverter_cells {CLKINVX1 CLKINVX12 CLKINVX16 CLKINVX2 CLKINV20 CLKINVX3 CLKINVX4 CLKINVX6 CLKINVX8}

    ccopt_design -cts
    report_ccopt_clock_trees -file cts_clock_trees.rpt
    report_ccopt_skew_groups -file cts_skew_groups.rpt
    timeDesign -postCTS -outDir ./postCTS
    saveDesign 05_cts
}

# 6. Detail Routing (NanoRoute)
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

# 7. Physical Verification & Signoff (DRC, LVS, GDSII)
proc signoff {} {
    file mkdir ./output
    file mkdir ./pnr/reports

    verify_drc -report ./pnr/reports/innovus_drc.rpt -limit 1000
    verify_connectivity -type all -report ./pnr/reports/innovus_lvs.rpt

    set gds_merge "/home/cadence/install/FOUNDRY/digital/90nm/dig/gds/gsclib090.gds"
    if {[file exists $gds_merge]} {
        streamOut ./output/bharatvoice_top.gds \
            -libName bharatvoice_top \
            -merge $gds_merge \
            -units 1000 \
            -mode ALL
    } else {
        streamOut ./output/bharatvoice_top.gds \
            -libName bharatvoice_top \
            -units 1000 \
            -mode ALL
    }

    puts "======================================================================="
    puts "  INNOVUS PHYSICAL DESIGN COMPLETED FOR bharatvoice_top"
    puts "  GDSII   : ./output/bharatvoice_top.gds"
    puts "  Reports : ./pnr/reports"
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

# Automatically show GUI and fit layout on screen
catch { gui_show }
catch { fit }
