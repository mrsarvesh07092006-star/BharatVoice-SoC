@echo off
echo ===================================================================
echo BharatVoice SoC -- Intel Quartus Prime Synthesis Runner
echo Tool: Intel Quartus Prime Lite Edition 20.1
echo ===================================================================

set QUARTUS_BIN=C:\intelFPGA_lite\20.1\quartus\bin64

if not exist "%QUARTUS_BIN%\quartus_sh.exe" (
    echo [ERROR] Quartus not found at %QUARTUS_BIN%
    exit /b 1
)

cd /d "%~dp0"

echo.
echo [1/2] Running Quartus Analysis and Synthesis...
"%QUARTUS_BIN%\quartus_sh.exe" -t synth_quartus.tcl

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Quartus synthesis failed. Check quartus_map.rpt for details.
    exit /b 1
)

echo.
echo [2/2] Copying Generated Gate-Level Netlist...
if not exist "..\syn\netlists" mkdir "..\syn\netlists"
if exist "simulation\modelsim\bharatvoice_top.vo" (
    copy /Y "simulation\modelsim\bharatvoice_top.vo" "..\syn\netlists\bharatvoice_top_quartus_netlist.v" > nul
    echo [SUCCESS] Netlist exported to: syn\netlists\bharatvoice_top_quartus_netlist.v
)

echo.
echo ===================================================================
echo Quartus Synthesis ^& Gate Netlist Generation Complete!
echo ===================================================================
