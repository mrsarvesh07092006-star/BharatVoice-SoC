# =============================================================================
# Cadence Innovus Master ASIC Implementation Script — BharatVoice SoC (90nm)
# Fully Automated Flow: Init -> Floorplan -> PDN -> Placement -> CTS -> 
#                       Routing -> Post-Route ECO & Timing -> DRC/LVS/Antenna Signoff -> GDSII
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Design Initialization & MMMC Setup
# -----------------------------------------------------------------------------
proc init_design_flow {} {
    global init_lef_file
    global init_verilog
    global init_top_cell

    # Physical Libraries (90nm Foundry LEF)
    set init_lef_file {
        /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_translated.lef
        /home/cadence/install/FOUNDRY/digital/90nm/dig/lef/gsclib090_tech.lef
    }

    set init_verilog ./syn/netlists/bharatvoice_top_netlist.v
    set init_top_cell bharatvoice_top

    set ::init_pwr_net {VDD}
    set ::init_gnd_net {VSS}

    # Timing Libraries (Slow, Typical, Fast)
    create_library_set -name slow_lib \
        -timing [list /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/slow.lib]

    create_library_set -name typical_lib \
        -timing [list /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib]

    create_library_set -name fast_lib \
        -timing [list /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/fast.lib]

    # SDC Timing Constraints
    set sdc_file ./syn/constraints/bharatvoice.sdc
    if {![file exists $sdc_file]} {
        set sdc_file ./bharatvoice_top.sdc
    }
    create_constraint_mode -name func_mode \
        -sdc_files [list $sdc_file]

    # Delay Corners
    create_delay_corner -name slow_corner    -library_set slow_lib
    create_delay_corner -name typical_corner -library_set typical_lib
    create_delay_corner -name fast_corner    -library_set fast_lib

    # Analysis Views (Setup on Slow corner, Hold on Fast corner)
    create_analysis_view -name slow_view    -constraint_mode func_mode -delay_corner slow_corner
    create_analysis_view -name typical_view -constraint_mode func_mode -delay_corner typical_corner
    create_analysis_view -name fast_view    -constraint_mode func_mode -delay_corner fast_corner

    # Initialize Design Database
    init_design -setup slow_view -hold fast_view
    set_analysis_view -setup {slow_view} -hold {fast_view}

    # Asynchronous reset false path protection
    catch { set_false_path -from [get_pins rst_ff2_reg/Q] }
    catch { set_false_path -from [get_pins -hier *rst_ff2*/Q] }

    checkDesign -all
    saveDesign 01_init
}

# -----------------------------------------------------------------------------
# 2. Floorplanning & Pin Placement
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# 3. Power Distribution Network (PDN)
# -----------------------------------------------------------------------------
proc power_plan {} {
    globalNetConnect VDD -type pgpin -pin VDD -all
    globalNetConnect VSS -type pgpin -pin VSS -all

    # Core Rings on Metal3 & Metal4
    addRing -nets {VDD VSS} -type core_rings -follow core \
        -layer {top Metal3 bottom Metal3 left Metal4 right Metal4} \
        -width {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -spacing {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -offset {top 1.8 bottom 1.8 left 1.8 right 1.8} \
        -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid None

    # Horizontal Power Stripes on Metal3
    addStripe -nets {VDD VSS} -layer Metal3 -direction horizontal -width 1.8 -spacing 1.8 \
        -set_to_set_distance 20 -start_from bottom -start_offset 10 -switch_layer_over_obs false \
        -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit Metal7 -block_ring_top_layer_limit Metal7 \
        -block_ring_bottom_layer_limit Metal1 -use_wire_group 0 -snap_wire_center_to_grid None

    # Vertical Power Stripes on Metal4
    addStripe -nets {VDD VSS} -layer Metal4 -direction vertical -width 1.8 -spacing 1.8 \
        -set_to_set_distance 20 -start_from left -start_offset 10 -switch_layer_over_obs false \
        -max_same_layer_jog_length 2 -padcore_ring_top_layer_limit Metal7 -block_ring_top_layer_limit Metal7 \
        -block_ring_bottom_layer_limit Metal1 -use_wire_group 0 -snap_wire_center_to_grid None

    # Special Route (Standard Cell Rails connection to Stripes & Rings)
    setSrouteMode -viaConnectToShape { noshape }
    sroute -connect { blockPin padPin padRing corePin floatingStripe } \
        -layerChangeRange { Metal1(1) Metal7(7) } \
        -blockPinTarget { nearestTarget } \
        -padPinPortConnect { allPort oneGeom } \
        -padPinTarget { nearestTarget } \
        -corePinTarget { firstAfterRowEnd } \
        -floatingStripeTarget { blockring padring ring stripe ringpin blockpin followpin } \
        -allowJogging 1 \
        -crossoverViaLayerRange { Metal1(1) Metal7(7) } \
        -nets { VDD VSS } \
        -allowLayerChange 1 \
        -blockPin useLef \
        -targetViaLayerRange { Metal1(1) Metal7(7) }

    saveDesign 03_power
}

# -----------------------------------------------------------------------------
# 4. Standard Cell Placement & Pre-CTS Timing Optimization
# -----------------------------------------------------------------------------
proc placement {} {
    place_design
    optDesign -preCTS
    saveDesign 04_placement
}

# -----------------------------------------------------------------------------
# 5. Clock Tree Synthesis (CCOpt) & Post-CTS Optimization
# -----------------------------------------------------------------------------
proc cts {} {
    set_ccopt_property target_max_trans 0.5
    set_ccopt_property buffer_cells {CLKBUFX2 CLKBUFX20 CLKBUFX3 CLKBUFX4 CLKBUFX6 CLKBUFX8 CLKBUFX12 CLKBUFX16}
    set_ccopt_property inverter_cells {CLKINVX1 CLKINVX12 CLKINVX16 CLKINVX2 CLKINV20 CLKINVX3 CLKINVX4 CLKINVX6 CLKINVX8}

    ccopt_design -cts

    # Optimize Post-CTS Timing
    optDesign -postCTS
    optDesign -postCTS -hold

    report_ccopt_clock_trees -file ./pnr/reports/cts_clock_trees.rpt
    report_ccopt_skew_groups -file ./pnr/reports/cts_skew_groups.rpt
    saveDesign 05_cts
}

# -----------------------------------------------------------------------------
# 6. Detail Routing (NanoRoute) with Antenna & DRC Awareness
# -----------------------------------------------------------------------------
proc routing {} {
    setNanoRouteMode -quiet -routeWithTimingDriven 1
    setNanoRouteMode -quiet -routeTdrEffort 1
    setNanoRouteMode -quiet -routeTopRoutingLayer 7
    setNanoRouteMode -quiet -routeBottomRoutingLayer 1
    setNanoRouteMode -quiet -drouteEndIteration default
    setNanoRouteMode -quiet -drouteFixDRC true
    setNanoRouteMode -quiet -drouteFixAntenna true
    setNanoRouteMode -quiet -routeWithTimingDriven true
    setNanoRouteMode -quiet -routeWithSiDriven false

    routeDesign -globalDetail
    setAnalysisMode -analysisType onChipVariation -cppr both
    routeDesign -trackopt
    routeDesign -antenna
    saveDesign 06_route
}

# -----------------------------------------------------------------------------
# 7. Post-Route Timing Closure & Automatic DRC/ECO Fixes
# -----------------------------------------------------------------------------
proc post_route_opt {} {
    # Treat reset synchronizer as false path for signoff timing
    catch { set_false_path -from [get_pins rst_ff2_reg/Q] }
    catch { set_false_path -from [get_pins -hier *rst_ff2*/Q] }

    # Setup & Hold Timing Closure
    optDesign -postRoute
    optDesign -postRoute -hold

    # ECO routing to wire all remaining nets, resolve DRCs and antenna
    setNanoRouteMode -quiet -drouteFixAntenna true
    setNanoRouteMode -quiet -drouteFixDRC true
    ecoRoute -fix_drc
    catch { routeDesign -antenna }

    saveDesign 07_post_route_opt
}

# -----------------------------------------------------------------------------
# 8. Physical Verification, Signoff Reports & GDSII Tapeout
# -----------------------------------------------------------------------------
proc signoff {} {
    file mkdir ./output
    file mkdir ./pnr/reports
    file mkdir ./pnr/reports/postroute

    # 1. DRC Verification
    verify_drc -report ./pnr/reports/bharatvoice_top.drc.rpt -limit 1000

    # 2. Connectivity / LVS Verification
    verifyConnectivity -type all -report ./pnr/reports/bharatvoice_top.conn.rpt

    # 3. Process Antenna Verification
    verifyProcessAntenna -report ./pnr/reports/bharatvoice_top.antenna.rpt -error 1000

    # 4. Signoff Timing Reports
    timeDesign -postRoute -outDir ./pnr/reports/postroute
    timeDesign -postRoute -hold -outDir ./pnr/reports/postroute

    # 5. Routing and Clock Summary
    report_route -summary > ./pnr/reports/route_summary.rpt
    report_ccopt_clock_trees -file ./pnr/reports/cts_clock_trees.rpt

    # 6. StreamOut GDSII Export
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
    puts "  INNOVUS FULL ASIC FLOW COMPLETED FOR bharatvoice_top"
    puts "  GDSII   : ./output/bharatvoice_top.gds"
    puts "  DRC     : ./pnr/reports/bharatvoice_top.drc.rpt"
    puts "  LVS     : ./pnr/reports/bharatvoice_top.conn.rpt"
    puts "  Antenna : ./pnr/reports/bharatvoice_top.antenna.rpt"
    puts "  Timing  : ./pnr/reports/postroute"
    puts "======================================================================="
}

# -----------------------------------------------------------------------------
# Quick Helper: View Layout in GUI
# -----------------------------------------------------------------------------
proc view_layout {} {
    if {[file exists 07_post_route_opt.dat]} {
        restoreDesign 07_post_route_opt.dat bharatvoice_top
    } elseif {[file exists 06_route.dat]} {
        restoreDesign 06_route.dat bharatvoice_top
    }
    catch { gui_show }
    fit
}

# -----------------------------------------------------------------------------
# Main Execution Pipeline (Runs Entire Flow Hands-Free!)
# -----------------------------------------------------------------------------
init_design_flow
floorplan
power_plan
placement
cts
routing
post_route_opt
signoff

# Automatically open GUI and fit full chip to screen
catch { gui_show }
fit
