# =============================================================================
# Intel Quartus Prime Synthesis Script for BharatVoice SoC
# Top Module: bharatvoice_top
# Generates: Gate-Level Verilog Netlist, Area Utilization, and SDC
# =============================================================================

load_package flow
load_package report

set prj_name "bharatvoice_top"

# Create new project or overwrite existing
project_new -overwrite $prj_name -family "Cyclone IV E"

# Top level entity
set_global_assignment -name TOP_LEVEL_ENTITY $prj_name

# Compiler settings
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
set_global_assignment -name VERILOG_INPUT_VERSION SYSTEMVERILOG_2005
set_global_assignment -name SDC_FILE ../syn/constraints/bharatvoice.sdc

# Add all 17 SystemVerilog files
set hdl_files [list \
    "../ibex_core.sv" \
    "../boot_rom.sv" \
    "../uart_rx.sv" \
    "../irq_ctrl.sv" \
    "../clint.sv" \
    "../crc_checker.sv" \
    "../transaction_guard.sv" \
    "../power_manager.sv" \
    "../payment_engine.sv" \
    "../audio_engine.sv" \
    "../sram_model.sv" \
    "../sram_controller.sv" \
    "../spi_master.sv" \
    "../spi_controller.sv" \
    "../transaction_cache.sv" \
    "../bus_interconnect.sv" \
    "../bharatvoice_top.sv" \
]

foreach f $hdl_files {
    set_global_assignment -name SYSTEMVERILOG_FILE $f
}

# Netlist generation settings (EDA Netlist Writer for ModelSim/Verilog)
set_global_assignment -name EDA_SIMULATION_TOOL "ModelSim (Verilog)"
set_global_assignment -name EDA_OUTPUT_DATA_FORMAT "VERILOG HDL" -section_id eda_simulation
set_global_assignment -name EDA_TIME_SCALE "1 ps" -section_id eda_simulation
set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST ON -section_id eda_simulation

# Run Analysis & Synthesis (quartus_map)
puts "======================================================================="
puts " \[QUARTUS\] Starting Analysis and Synthesis (quartus_map)..."
puts "======================================================================="
execute_module -tool map

# Run EDA Netlist Writer to produce post-synthesis gate-level netlist
puts "======================================================================="
puts " \[QUARTUS\] Generating Gate-Level Netlist (quartus_eda)..."
puts "======================================================================="
execute_module -tool eda

project_close

puts "======================================================================="
puts " \[QUARTUS\] Synthesis and Gate-Level Netlist Generation Complete!"
puts " Netlist: simulation/modelsim/bharatvoice_top.vo"
puts "======================================================================="
