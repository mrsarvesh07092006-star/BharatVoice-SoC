// =============================================================================
// Cadence Conformal Logic Equivalence Checking (LEC) Dofile
// Design : BharatVoice SoC (bharatvoice_top)
// Flow   : [3/5] Golden RTL vs. Synthesized Gate-Level Netlist
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Load Standard Cell Library (Both Golden and Revised)
// -----------------------------------------------------------------------------
read library -statename typical /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/typical.lib -both

// -----------------------------------------------------------------------------
// 2. Read Golden Design (SystemVerilog RTL Sources)
// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
// 3. Read Revised Design (Synthesized Gate-Level Netlist)
// -----------------------------------------------------------------------------
read design -revised -verilog syn/netlists/bharatvoice_top_netlist.v

set root module bharatvoice_top -revised

// -----------------------------------------------------------------------------
// 4. Enter LEC Comparison Mode
// -----------------------------------------------------------------------------
set system mode lec

// -----------------------------------------------------------------------------
// 5. Map & Compare Key Points (Flip-Flops, Latches, Primary Outputs)
// -----------------------------------------------------------------------------
add compared points -all

compare

// -----------------------------------------------------------------------------
// 6. Generate Verification Report
// -----------------------------------------------------------------------------
report compare data -class nonequivalent -class abort -class notcompared
report verification -verbose > lec/lec_verification.rpt

// Exit with status code (0 if equivalent, 1 if differences found)
exit -force
