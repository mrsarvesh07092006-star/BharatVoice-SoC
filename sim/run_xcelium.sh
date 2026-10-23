#!/usr/bin/env bash
# =============================================================================
# Cadence Xcelium Logic Simulation Runner for BharatVoice SoC
# Flow Stage: [1/5] XCELIUM RTL Functional Verification
# =============================================================================

set -e

PRJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PRJ_ROOT"

mkdir -p sim/logs sim/waves

echo "======================================================================="
echo " [CADENCE XCELIUM] Starting BharatVoice SoC Regression Suite"
echo "======================================================================="

# List of all synthesizable RTL files
RTL_FILES="
    ibex_core.sv
    boot_rom.sv
    uart_rx.sv
    irq_ctrl.sv
    clint.sv
    crc_checker.sv
    transaction_guard.sv
    power_manager.sv
    payment_engine.sv
    audio_engine.sv
    sram_model.sv
    sram_controller.sv
    spi_master.sv
    spi_controller.sv
    transaction_cache.sv
    bus_interconnect.sv
    bharatvoice_top.sv
"

# 1. Run Unit Testbenches
echo ">>> [1/4] Running SRAM Model Verification (tb_sram_model)..."
xrun -64bit -sv -timescale 1ns/1ps -l sim/logs/xrun_sram.log sram_model.sv tb_sram_model.sv -top tb_sram_model -access +rwc

echo ">>> [2/4] Running SPI Master Verification (tb_spi_master)..."
xrun -64bit -sv -timescale 1ns/1ps -l sim/logs/xrun_spi.log spi_master.sv tb_spi_master.sv -top tb_spi_master -access +rwc

echo ">>> [3/4] Running Payment Engine Verification (tb_payment_engine)..."
xrun -64bit -sv -timescale 1ns/1ps -l sim/logs/xrun_payment.log payment_engine.sv tb_payment_engine.sv -top tb_payment_engine -access +rwc

# 2. Run Full SoC Integration Testbench
echo ">>> [4/4] Running Full SoC Integration (tb_soc_integration)..."
xrun -64bit -sv -timescale 1ns/1ps -l sim/logs/xrun_soc.log $RTL_FILES tb_soc_integration.sv -top tb_soc_integration -access +rwc

echo "======================================================================="
echo " [CADENCE XCELIUM] All 4 Test Suites PASSED Successfully!"
echo " Logs saved in: sim/logs/"
echo "======================================================================="
