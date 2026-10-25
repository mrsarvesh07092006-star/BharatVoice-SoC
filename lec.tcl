# =============================================================================
# Cadence Conformal LEC Script for BharatVoice SoC
# Tool   : Conformal 21.1 (lec -nogui -dofile lec.tcl)
# Run from project root: /home/userdata/24bvd0092/asic_proj/BharatVoice-SoC
# =============================================================================

# 1. Load Standard Cell Verilog Behavioral Model (NOT the .lib Liberty file)
#    Conformal needs Verilog models, not Liberty timing models.
#    Try common 90nm GSClib Verilog paths on your server:

set lib_candidates {
    /home/cadence/install/FOUNDRY/digital/90nm/dig/verilog/gsclib090_allvt.v
    /home/cadence/install/FOUNDRY/digital/90nm/dig/verilog/gsclib090.v
    /home/cadence/install/FOUNDRY/digital/90nm/dig/verilog/typical.v
    /home/cadence/install/FOUNDRY/digital/90nm/verilog/gsclib090_allvt.v
    /home/cadence/install/FOUNDRY/digital/90nm/verilog/gsclib090.v
}

set lib_file ""
foreach f $lib_candidates {
    if {[file exists $f]} {
        set lib_file $f
        break
    }
}

if {$lib_file ne ""} {
    puts "// [INFO] Using standard cell Verilog library: $lib_file"
    read_library $lib_file -both
} else {
    puts "// [WARNING] No Verilog std-cell library found. Proceeding without library."
    puts "// [WARNING] Set_undriven may be needed for some outputs."
}

# 2. Read Golden Design — all 17 SystemVerilog RTL files
read_design -golden -sv \
    ibex_core.sv \
    boot_rom.sv \
    uart_rx.sv \
    irq_ctrl.sv \
    clint.sv \
    crc_checker.sv \
    transaction_guard.sv \
    power_manager.sv \
    payment_engine.sv \
    audio_engine.sv \
    sram_model.sv \
    sram_controller.sv \
    spi_master.sv \
    spi_controller.sv \
    transaction_cache.sv \
    bus_interconnect.sv \
    bharatvoice_top.sv

set_root_module bharatvoice_top -golden

# 3. Read Revised Design — synthesized gate-level netlist from Genus
read_design -revised -verilog syn/netlists/bharatvoice_top_netlist.v

set_root_module bharatvoice_top -revised

# 4. Switch to LEC comparison mode
set_system_mode lec

# 5. Add all comparison points and run
add_compared_points -all

compare

# 6. Print verification report
report_verification -verbose
report_compare_data -class nonequivalent -class abort -class notcompared
