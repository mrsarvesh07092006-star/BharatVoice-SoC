# =============================================================================
# BharatVoice SoC — PowerShell RTL Regression Runner
# Runs SRAM, SPI, Payment Engine, and Full End-to-End SoC Integration
# under ModelSim ASE 10.5b
# =============================================================================

$vlog = "C:\intelFPGA\18.1\modelsim_ase\win32aloem\vlog.exe"
$vsim = "C:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe"
$vlib = "C:\intelFPGA\18.1\modelsim_ase\win32aloem\vlib.exe"

Write-Host "===================================================================" -ForegroundColor Cyan
Write-Host "BharatVoice SoC -- Complete Local RTL Regression Suite" -ForegroundColor Cyan
Write-Host "Simulator: ModelSim ASE 10.5b" -ForegroundColor Cyan
Write-Host "===================================================================" -ForegroundColor Cyan

if (-not (Test-Path "work_ms")) {
    & $vlib work_ms | Out-Null
}

$allRTL = @(
    "bus_interconnect.sv", "payment_engine.sv", "spi_master.sv", "sram_model.sv",
    "uart_rx.sv", "audio_engine.sv", "crc_checker.sv", "transaction_guard.sv",
    "power_manager.sv", "sram_controller.sv", "transaction_cache.sv", "irq_ctrl.sv",
    "clint.sv", "boot_rom.sv"
)

$tests = @(
    @{ Name = "SRAM Model"; Files = @("sram_model.sv", "tb_sram_model.sv"); Top = "work_ms.tb_sram_model" },
    @{ Name = "SPI Master"; Files = @("spi_master.sv", "tb_spi_master.sv"); Top = "work_ms.tb_spi_master" },
    @{ Name = "Payment Processing Engine"; Files = @("payment_engine.sv", "tb_payment_engine.sv"); Top = "work_ms.tb_payment_engine" },
    @{ Name = "Full SoC End-to-End Integration"; Files = ($allRTL + @("tb_soc_integration.sv")); Top = "work_ms.tb_soc_integration" }
)

$allPassed = $true

foreach ($t in $tests) {
    Write-Host "`n--> Compiling & Running $($t.Name)..." -ForegroundColor Yellow
    & $vlog -sv -work work_ms $t.Files | Out-Null
    $output = & $vsim -c -do "run -all; quit" $t.Top
    
    $passLine = $output | Where-Object { $_ -match "REGRESSION.*PASS" }
    $summaryLines = $output | Where-Object { $_ -match "Checks|REGRESSION RESULT|INTEGRATION REGRESSION" }
    
    foreach ($line in $summaryLines) {
        if ($line -match "PASS") {
            Write-Host "    $line" -ForegroundColor Green
        } else {
            Write-Host "    $line" -ForegroundColor Red
        }
    }
    
    if (-not $passLine) {
        $allPassed = $false
    }
}

Write-Host "`n===================================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host ">>> ALL 4 REGRESSION SUITES PASSED CLEANLY (100% SUCCESS) <<<" -ForegroundColor Green
} else {
    Write-Host ">>> SOME REGRESSION SUITES FAILED <<<" -ForegroundColor Red
}
Write-Host "===================================================================" -ForegroundColor Cyan
