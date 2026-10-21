@echo off
echo ===================================================================
echo BharatVoice SoC -- Complete Local RTL Regression Suite
echo Tool: ModelSim - Intel FPGA Starter Edition 10.5b
echo ===================================================================

set VLOG="C:\intelFPGA\18.1\modelsim_ase\win32aloem\vlog.exe"
set VSIM="C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe"
set VLIB="C:\intelFPGA\18.1\modelsim_ase\win32aloem\vlib.exe"

if not exist work_ms (
    %VLIB% work_ms
)

echo.
echo -------------------------------------------------------------------
echo [1/3] Running SRAM Model Verification (tb_sram_model)...
echo -------------------------------------------------------------------
%VLOG% -sv -work work_ms sram_model.sv tb_sram_model.sv > nul 2>&1
%VSIM% -c -do "run -all; quit" work_ms.tb_sram_model

echo.
echo -------------------------------------------------------------------
echo [2/3] Running SPI Master Verification (tb_spi_master)...
echo -------------------------------------------------------------------
%VLOG% -sv -work work_ms spi_master.sv tb_spi_master.sv > nul 2>&1
%VSIM% -c -do "run -all; quit" work_ms.tb_spi_master

echo.
echo -------------------------------------------------------------------
echo [3/3] Running Sarvesh's Payment Engine Verification (tb_payment_engine)...
echo -------------------------------------------------------------------
%VLOG% -sv -work work_ms payment_engine.sv tb_payment_engine.sv > nul 2>&1
%VSIM% -c -do "run -all; quit" work_ms.tb_payment_engine

echo.
echo ===================================================================
echo Full Regression Run Complete!
echo ===================================================================
