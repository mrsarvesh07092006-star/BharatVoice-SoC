// =============================================================================
// Cadence Conformal LEC Dofile for BharatVoice SoC
// Tool   : Conformal 21.1 (lec -nogui -dofile lec.do)
// Run from project root: /home/userdata/24bvd0092/asic_proj/BharatVoice-SoC
// =============================================================================

// 1. Read Standard Cell Verilog Behavioral Library
read library /home/cadence/install/FOUNDRY/digital/90nm/dig/verilog/gsclib090_allvt.v -both

// 2. Read Golden Design (All 17 SystemVerilog RTL modules)
read design -golden -systemverilog \
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

set root module bharatvoice_top -golden

// 3. Read Revised Design (Synthesized Gate-Level Netlist)
read design -revised -verilog syn/netlists/bharatvoice_top_netlist.v

set root module bharatvoice_top -revised

// 4. Switch to LEC Mode
set system mode lec

// 5. Map and Compare All Key Points
add compared points -all

compare

// 6. Report Verification Results
report verification -verbose

report compare data -class nonequivalent -class abort -class notcompared
