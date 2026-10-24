// =============================================================================
// Cadence Conformal Logic Equivalence Checking (LEC) Dofile
// Design : BharatVoice SoC (bharatvoice_top)
// Flow   : [3/5] Golden RTL vs. Synthesized Gate-Level Netlist
// NOTE   : This file uses $PRJ_ROOT token replaced at runtime by run_conformal.sh
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Load Standard Cell Library (Both Golden and Revised)
// -----------------------------------------------------------------------------
read library -statename typical __LIB_PATH__ -both

// -----------------------------------------------------------------------------
// 2. Read Golden Design (SystemVerilog RTL Sources)
// NOTE: Full paths injected at runtime by run_conformal.sh
// -----------------------------------------------------------------------------
read design -golden -sv __RTL_FILES__

set root module bharatvoice_top -golden

// -----------------------------------------------------------------------------
// 3. Read Revised Design (Synthesized Gate-Level Netlist)
// -----------------------------------------------------------------------------
read design -revised -verilog __NETLIST__

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
report verification -verbose > __RPT__

// Exit with status code (0 if equivalent, 1 if differences found)
exit -force
