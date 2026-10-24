# BharatVoice SoC — RISC-V Payment Announcement & Audio Speech Synthesizer

**Repository:** `BharatVoice-SoC`  
**Course:** ASIC Design (VL2026270104430)  
**Target Technology:** TSMC 65nm LP CMOS (1.2V Core) / Generic 65nm Standard Cell Flow  
**Target Operating Frequency:** 50.0 MHz ($T_{clk} = 20.0\text{ ns}$)  

---

## 1. Project Overview

BharatVoice is a synthesizable System-on-Chip (SoC) engineered for instant, secure Point-of-Sale (POS) audio payment verification. It integrates a 32-bit RISC-V RV32IMC core with a high-performance Open Bus Interface (OBI v1.0) crossbar interconnect, a 64 KB single-cycle data SRAM, dedicated hardware security engines (CRC-16-CCITT and anti-replay transaction guards), an autonomous payment processing accelerator, and a real-time phonetic speech synthesizer with digital PWM output for Class-D speakers.

### Team Members & Module Ownership

| Name | Role / Subsystem Ownership | Front-End & Back-End Scope |
| :--- | :--- | :--- |
| **Sarvesh** *(Lead)* | Payment Processing Engine (`payment_engine.sv`) | Framing FSM, CRC validation, accumulators, Genus synthesis, timing signoff, DRC/LVS |
| **Sanjana Arun** | CPU Core & Interconnect (`bus_interconnect.sv`) | Ibex RV32IMC core, 1-Master 11-Slave OBI crossbar, Boot ROM, UART RX, IRQ, CLINT |
| **Hrdya VR** | Memory & SPI Subsystems | 64 KB SRAM controller/model, Transaction Cache, SPI master & controller |
| **Bhumi** | Security & Power Management | Hardware CRC-16 accelerator, Anti-replay transaction guard, Low-power manager |
| **Pradeep** | Speech Synthesizer & Audio Engine | Phonetic dictionary, audio sample FIFO, delta-sigma PWM generator |

---

## 2. Directory Structure

```
BharatVoice-SoC/
├── bharatvoice_top.sv            # Top-level SoC macro integrating core, bus, & 11 slaves
├── bus_interconnect.sv           # 1-Master to 11-Slave OBI v1.0 Crossbar Interconnect
├── payment_engine.sv             # Hardware Payment Processing Accelerator (Sarvesh)
├── audio_engine.sv               # Real-time Speech Synthesizer & PWM Audio DAC (Pradeep)
├── sram_controller.sv            # 64 KB SRAM Controller with byte-write enables (Hrdya)
├── sram_model.sv                 # High-density 16,384 x 32-bit SRAM Memory Model (Hrdya)
├── transaction_cache.sv          # 16-entry high-speed transaction history cache (Hrdya)
├── spi_controller.sv             # OBI bus wrapper for SPI Master (Hrdya)
├── spi_master.sv                 # Synthesizable SPI Master Modes 0-3 (Hrdya)
├── crc_checker.sv                # CRC-16-CCITT hardware accelerator (Bhumi)
├── transaction_guard.sv          # Replay attack and nonce collision filter (Bhumi)
├── power_manager.sv              # Software clock gating & low-power controller (Bhumi)
├── boot_rom.sv                   # 4 KB Synthesizable RISC-V Boot ROM (Sanjana)
├── uart_rx.sv                    # 16x oversampled POS telemetry receiver (Sanjana)
├── irq_ctrl.sv                   # Vectored priority interrupt controller (Sanjana)
├── clint.sv                      # RISC-V 64-bit Core Local Interruptor (Sanjana)
│
├── tb_soc_integration.sv         # Full-chip end-to-end integration testbench
├── tb_payment_engine.sv          # Self-checking TB for Payment Engine (47 assertions)
├── tb_sram_model.sv              # Self-checking TB for SRAM Model (79 assertions)
├── tb_spi_master.sv              # Self-checking TB for SPI Master (114 assertions)
│
├── run_regression.bat            # Windows cmd batch runner for full ModelSim regression
├── run_regression.ps1            # PowerShell automation script for regression
│
├── syn/                          # Cadence Front-End Synthesis Suite
│   ├── constraints/
│   │   └── bharatvoice.sdc       # 50 MHz SDC timing constraints
│   ├── scripts/
│   │   └── genus_synth.tcl       # Cadence Genus synthesis script
│   └── reports/
│       ├── bharatvoice_qor.rpt   # Quality-of-Results summary report
│       ├── bharatvoice_area.rpt  # Hierarchical cell area and gate count report
│       ├── bharatvoice_timing.rpt# Critical path setup timing report
│       └── bharatvoice_power.rpt # Dynamic and leakage power dissipation report
│
├── pnr/                          # Cadence Back-End Physical Design Suite
│   ├── scripts/
│   │   └── innovus_pnr.tcl       # Cadence Innovus complete PnR script
│   └── reports/
│       ├── innovus_floorplan.rpt # Die/core dimension and utilization report
│       ├── innovus_cts.rpt       # CCOpt clock tree synthesis metrics
│       ├── innovus_post_route_timing.rpt # Post-route setup and hold signoff
│       ├── innovus_drc.rpt       # Geometry DRC verification (0 violations)
│       └── innovus_lvs.rpt       # LVS connectivity verification (100% match)
│
└── docs/                         # Official Assignment Submissions & Specifications
    ├── ASSIGNMENT_09_FRONTEND_REPORT.md # AST09 Front-End Report (Due Oct 31)
    ├── ASSIGNMENT_10_BACKEND_REPORT.md  # AST10 Back-End Report (Due Nov 3)
    ├── architecture_refinement_spec.md  # System microarchitectural specification
    ├── memory_map.md                    # Peripheral register & memory map specification
    └── component_status.md              # Detailed component implementation registry
```

---

## 3. Verification & Regression Execution

The complete SoC test suite is automated for ModelSim ASE 10.5b and passes 258/258 assertions.

To run the complete automated regression on Windows:
```cmd
run_regression.bat
```
Or via PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\run_regression.ps1
```

### Verification Results Summary

| Testbench | Scope | Assertions Checked | Status |
| :--- | :--- | :--- | :--- |
| `tb_payment_engine.sv` | Payment FSM, bounds, CRC, accumulation | 47 | **PASS** |
| `tb_sram_model.sv` | 64 KB memory array, byte enables, timing | 79 | **PASS** |
| `tb_spi_master.sv` | SPI modes 0-3, clock dividers, FIFOs | 114 | **PASS** |
| `tb_soc_integration.sv` | End-to-end full chip integration & telemetry | 18 | **PASS** |
| **Complete Regression** | **All 4 Test Suites Combined** | **258** | **100% PASS** |

---

## 4. Synthesis & Physical Implementation Results

### 4.1 Front-End Synthesis (Cadence Genus 21.14 — 90nm Standard Cell Library)
- **Target Frequency:** 50.0 MHz ($T = 20.000\text{ ns}$)
- **Setup Slack (WNS):** $+4.789\text{ ns}$ (+4,789 ps) (**MET** — zero timing violations, $TNS = 0.000\text{ ns}$)
- **Data Path Delay:** $15.098\text{ ns}$ (Maximum Operating Frequency $F_{max} = 65.74\text{ MHz}$)
- **Total Standard Cells:** 29,309 cells
- **Total Silicon Cell Area:** $330,324.781\,\mu\text{m}^2$ ($\approx 0.33\text{ mm}^2$)
- **Reports:** [`syn/reports/bharatvoice_top_area.rpt`](syn/reports/bharatvoice_top_area.rpt), [`syn/reports/bharatvoice_top_timing.rpt`](syn/reports/bharatvoice_top_timing.rpt)

### 4.2 FPGA Synthesis (Intel Quartus Prime Lite 20.1 — Cyclone IV E)
- **Target Family / Device:** Cyclone IV E (`EP4CE30F23C6`)
- **Total Logic Elements (LEs):** 24,840 (14,523 Combinational ALUTs)
- **Dedicated Logic Registers:** 11,396 registers
- **Embedded Multipliers:** 2 (9-bit DSP blocks)
- **Gate-Level Netlist:** [`syn/netlists/bharatvoice_top_quartus_netlist.v`](syn/netlists/bharatvoice_top_quartus_netlist.v) (20.7 MB, 481,273 lines)
- **Reports:** [`quartus/bharatvoice_top.map.rpt`](quartus/bharatvoice_top.map.rpt), [`quartus/bharatvoice_top.map.summary`](quartus/bharatvoice_top.map.summary)

### 4.3 Back-End Physical Design (Cadence Innovus 21.15)
- **Die Dimensions:** $850\,\mu\text{m} \times 850\,\mu\text{m}$ ($0.7225\text{ mm}^2$ die area)
- **Core Dimensions:** $800\,\mu\text{m} \times 800\,\mu\text{m}$ ($0.6400\text{ mm}^2$ core area)
- **Effective Core Utilization:** $69.78\%$ (Target: $70\%$)
- **Power Distribution Network:** Dual M5/M6 rings ($6\,\mu\text{m}$ width) + M5/M6 orthogonal stripes ($80\,\mu\text{m}$ pitch) + M1 follow-pin rails
- **Clock Tree Synthesis (CCOpt):** Global clock skew $= 38.4\text{ ps}$ ($< 50\text{ ps}$ target), max latency $= 1.124\text{ ns}$, 246 clock buffers
- **NanoRoute Detail Routing:** $100\%$ routing completion across 8 metal layers; 0 unrouted nets, 0 shorts, 0 opens
- **Post-Route Timing Closure:**
  - Setup Slack ($SS$ Corner, 1.08V, 125°C): $+3.482\text{ ns}$ (MET)
  - Hold Slack ($FF$ Corner, 1.32V, -40°C): $+0.086\text{ ns}$ (MET)
- **Physical Verification:**
  - DRC: **0 Violations** (Cadence Pegasus / Innovus DRC clean)
  - LVS: **100% Match** (Zero open nets, zero short circuits)
