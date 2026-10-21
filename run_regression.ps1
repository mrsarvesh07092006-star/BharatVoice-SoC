# =============================================================================
# BharatVoice SoC — PowerShell RTL Regression Runner
# Runs SRAM, SPI, and Payment Engine testbenches under ModelSim ASE 10.5b
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

$tests = @(
    @{ Name = "SRAM Model"; RTL = "sram_model.sv"; TB = "tb_sram_model.sv"; Top = "work_ms.tb_sram_model" },
    @{ Name = "SPI Master"; RTL = "spi_master.sv"; TB = "tb_spi_master.sv"; Top = "work_ms.tb_spi_master" },
    @{ Name = "Payment Processing Engine"; RTL = "payment_engine.sv"; TB = "tb_payment_engine.sv"; Top = "work_ms.tb_payment_engine" }
)

$allPassed = $true

foreach ($t in $tests) {
    Write-Host "`n--> Compiling & Running $($t.Name)..." -ForegroundColor Yellow
    & $vlog -sv -work work_ms $t.RTL $t.TB | Out-Null
    $output = & $vsim -c -do "run -all; quit" $t.Top
    
    $passLine = $output | Where-Object { $_ -match "REGRESSION RESULT: PASS" }
    $summaryLines = $output | Where-Object { $_ -match "Checks|REGRESSION RESULT" }
    
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
    Write-Host ">>> ALL REGRESSION SUITES PASSED CLEANLY (100% SUCCESS) <<<" -ForegroundColor Green
} else {
    Write-Host ">>> SOME REGRESSION SUITES FAILED <<<" -ForegroundColor Red
}
Write-Host "===================================================================" -ForegroundColor Cyan
