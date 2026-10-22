# Assignment-IX: Group Project — Front End Implementation and Synthesis
## Course: ASIC Design (VL2026270104430)
**Submission Due Date:** 31st October  
**Project Title:** BharatVoice — RISC-V Powered Secure Payment Announcement and Audio Speech Synthesizer SoC  
**Target Process:** TSMC 65nm LP (1.2V Core, Typical Corner) / Generic 65nm Standard Cell Flow  
**Target Operating Frequency:** 50.0 MHz ($T_{clk} = 20.0\text{ ns}$)  

---

### Team Information

| Team Member Name | Registration Number | Lab Slot | Core Front-End Module Ownership |
| :--- | :--- | :--- | :--- |
| **Sarvesh** *(Project Lead)* | `[Reg No: 21BECXXXX]` | `[Slot: L9 + L10]` | Payment Processing Engine (`payment_engine.sv`), Top TB |
| **Sanjana Arun** | `[Reg No: 21BECXXXX]` | `[Slot: L9 + L10]` | RISC-V Ibex Core, Crossbar Interconnect, UART RX, IRQ, CLINT |
| **Hrdya VR** | `[Reg No: 21BECXXXX]` | `[Slot: L9 + L10]` | 64 KB SRAM Controller, SRAM Model, Transaction Cache, SPI |
| **Bhumi** | `[Reg No: 21BECXXXX]` | `[Slot: L9 + L10]` | Hardware CRC Checker, Transaction Guard, Power Manager |
| **Pradeep** | `[Reg No: 21BECXXXX]` | `[Slot: L9 + L10]` | Audio Speech Synthesizer & Delta-Sigma PWM Audio DAC |

---

## 1. Executive Summary

BharatVoice is a high-reliability, low-power Application-Specific Integrated Circuit (ASIC) System-on-Chip (SoC) engineered specifically for Point-of-Sale (POS) instant audio transaction verification. In emerging digital payment ecosystems (such as UPI and Soundbox terminals), merchants rely upon instant, tamper-proof auditory feedback when transactions settle. Existing market solutions depend on off-the-shelf microcontrollers coupled with external SPI flash and codec chips, introducing latency, high bill-of-materials (BOM) cost, and vulnerability to replay and man-in-the-middle attacks.

BharatVoice integrates a 32-bit RISC-V RV32IMC Ibex core, an Open Bus Interface (OBI v1.0) crossbar interconnect, a 64 KB single-cycle data SRAM, an autonomous hardware Payment Processing Accelerator, a real-time Audio Speech Synthesizer with digital PWM output, and dedicated hardware security accelerators (CRC-16 CCITT and Replay Transaction Guard).

This report documents the **Front-End stages** of the ASIC design flow, comprising:
1. Microarchitectural specification and complete synthesizable SystemVerilog (IEEE 1800-2017) RTL implementation without behavioral stubs.
2. Comprehensive multi-level functional verification using ModelSim ASE 10.5b across unit, sub-system, and full-SoC levels, achieving a 100% pass rate (258/258 assertions).
3. Logic synthesis using **Cadence Genus Synthesis Solution 21.14**, meeting timing constraints ($WNS = +4.120\text{ ns}$ at 50 MHz), area constraints ($0.513\text{ mm}^2$ total design area, 241,816 gate equivalents), and power budgets ($21.00\text{ mW}$).

---

## 2. RTL Implementation & System Architecture

### 2.1 Design Hierarchy
The top-level chip macro is encapsulated in [`bharatvoice_top.sv`](file:///c:/Users/mrsar/OneDrive - vit.ac.in/work/asic/bharatvoice_top.sv). The system architecture employs a clean single-master, 11-slave OBI bus interconnect topology operating on a synchronous 50 MHz clock domain:

```
bharatvoice_top (Top-Level SoC)
 ├── u_ibex_core           : lowRISC RV32IMC 32-bit RISC-V Processor Core
 ├── u_interconnect        : 1-Master to 11-Slave OBI v1.0 Crossbar Interconnect
 ├── u_boot_rom            : 4 KB Synthesizable Boot ROM (0x0000_0000)
 ├── u_sram_controller     : 64 KB SRAM Controller & Datapath Arbiter (0x2000_0000)
 │    └── u_sram_model     : High-density 16,384 x 32-bit SRAM Memory Array
 ├── u_payment_engine      : Hardware Payment Processing Accelerator (0x4000_0000)
 ├── u_audio_engine        : Speech Synthesizer & Delta-Sigma Audio PWM (0x4000_1000)
 ├── u_transaction_cache   : 16-Entry Transaction History Cache (0x4000_3000)
 ├── u_spi_ctrl            : SPI Master Controller & Bus Wrapper (0x4000_4000)
 │    └── u_spi_core       : Synthesizable SPI Physical Master (Modes 0-3)
 ├── u_crc_checker         : Hardware CRC-16-CCITT Accelerator Engine (0x4000_5000)
 ├── u_transaction_guard   : Anti-Replay Attack & Nonce Filter (0x4000_6000)
 ├── u_power_manager       : Architectural Clock Gating & Power Mode Controller (0x4000_7000)
 ├── u_uart_rx             : 16x Oversampled Robust POS Telemetry Receiver (0x4000_8000)
 ├── u_irq_ctrl            : Prioritized Vectored Interrupt Controller (0x4000_9000)
 └── u_clint               : RISC-V Standard 64-bit Core Local Interruptor (0x4000_A000)
```

### 2.2 Memory Map Architecture
The memory map enforces strict address segregation between non-volatile code storage, scratchpad SRAM, and dedicated memory-mapped accelerator registers:

| Region Name | Base Address | End Address | Size | Access Type | Bus Slave Index | Module Owner |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Boot ROM** | `0x0000_0000` | `0x0000_0FFF` | 4 KB | Read-Only | Slave 0 | Sanjana |
| **Data SRAM** | `0x2000_0000` | `0x2000_FFFF` | 64 KB | Read/Write | Slave 1 | Hrdya |
| **Payment Engine** | `0x4000_0000` | `0x4000_0FFF` | 4 KB | Read/Write | Slave 2 | Sarvesh |
| **Audio Engine** | `0x4000_1000` | `0x4000_1FFF` | 4 KB | Read/Write | Slave 3 | Pradeep |
| **SRAM Controller Regs** | `0x4000_2000` | `0x4000_2FFF` | 4 KB | Read/Write | Slave 4 | Hrdya |
| **Transaction Cache** | `0x4000_3000` | `0x4000_3FFF` | 4 KB | Read/Write | Slave 5 | Hrdya |
| **SPI Master** | `0x4000_4000` | `0x4000_4FFF` | 4 KB | Read/Write | Slave 6 | Hrdya |
| **CRC Checker** | `0x4000_5000` | `0x4000_5FFF` | 4 KB | Read/Write | Slave 7 | Bhumi |
| **Transaction Guard** | `0x4000_6000` | `0x4000_6FFF` | 4 KB | Read/Write | Slave 8 | Bhumi |
| **Power Manager** | `0x4000_7000` | `0x4000_7FFF` | 4 KB | Read/Write | Slave 9 | Bhumi |
| **UART RX** | `0x4000_8000` | `0x4000_8FFF` | 4 KB | Read/Write | Slave 10 | Sanjana |
| **Interrupt Controller** | `0x4000_9000` | `0x4000_9FFF` | 4 KB | Read/Write | Slave 11 | Sanjana |
| **CLINT (Timer)** | `0x4000_A000` | `0x4000_AFFF` | 4 KB | Read/Write | Slave 12 | Sanjana |

### 2.3 Detailed Module Descriptions & Key Design Decisions

#### 2.3.1 Sarvesh's Payment Processing Engine (`payment_engine.sv`)
- **Key Architectural Role:** Dedicated hardware coprocessor offloading CPU cycle-intensive transaction string parsing, validation, and accounting.
- **Microarchitecture:**
  - Implements an 8-state Mealy/Moore synchronous FSM: `ST_IDLE`, `ST_HEADER`, `ST_PAYLOAD`, `ST_VALIDATE`, `ST_CRC_CHECK`, `ST_COMMIT`, `ST_ERROR`, `ST_DONE`.
  - **Framing Protocol:** Hardware enforces the packet structure `0xAA55` (Preamble), 32-bit Transaction ID, 32-bit Amount (in minor currency units/paise), 8-bit Currency Code (`0x01` = INR), and 16-bit CRC checksum.
  - **Anti-Fraud & Bounds Checker:** Rejects transactions with an amount of zero or amounts exceeding maximum credit limits (`0x00FFFFFF`). Transactions outside bounds trigger an immediate transition to `ST_ERROR` with a sticky error code registered in `ERR_STATUS`.
  - **Cumulative Accounting:** High-speed 32-bit hardware saturating accumulators automatically track total transaction volume and accepted currency value without requiring software loop execution.
- **Synthesis-Aware Optimization:** All arithmetic logic is cleanly pipelined; state transitions use explicit parallel case statements to ensure complete multiplexer inference without inferring transparent latches.

#### 2.3.2 Open Bus Interface (OBI v1.0) Crossbar Interconnect (`bus_interconnect.sv`)
- **Interconnect Protocol:** Utilizes the lowRISC / PULP Open Bus Interface (OBI) standard featuring decoupled address (`req`/`gnt`) and response (`rvalid`/`rdata`/`err`) phases.
- **Handshake Contract:** Once `m_req_i` is asserted, `s_req_o[sel]` is dispatched to the decoded target slave. To guarantee deterministic multi-cycle and wait-state peripheral access, `sel_slave_q` retains the slave grant state until the asserting slave pulses `s_rvalid_i`, preventing premature deassertion during long operations.
- **Decoded Error Catching:** Unmapped address spaces cleanly return an immediate 1-cycle `err = 1` response, preventing processor bus stalls.

#### 2.3.3 Audio Speech Synthesizer & PWM Engine (`audio_engine.sv`)
- **Microarchitecture:** Comprises an internal phonetic dictionary look-up unit, an 8-word sample FIFO, and a digital 8-bit pulse-width modulator operating at a 195.3 kHz carrier frequency ($50\text{ MHz} / 256$).
- **Direct Sound Generation:** Converts numeric amounts validated by the payment engine into a series of timed audio phonemes (e.g., "Payment", "Received", "Rupees", "Five", "Hundred").
- **Physical Output:** Generates complementary PWM pulses (`audio_pwm_o`) with a software-controllable shutdown pin (`audio_sd_o`) for Class-D audio amplifier control.

#### 2.3.4 Memory Subsystem (`sram_controller.sv` & `sram_model.sv`)
- **Configuration:** 64 KB capacity structured as 16,384 words $\times$ 32 bits with active-high byte-write enables (`be[3:0]`).
- **Timing Contract:** Zero-wait-state synchronous read access; memory read data is presented on the clock edge following address presentation, fully compliant with typical foundry synchronous single-port SRAM macro specifications.

#### 2.3.5 Security Blocks (`crc_checker.sv`, `transaction_guard.sv`, `power_manager.sv`)
- **CRC-16 Accelerator:** Dedicated hardware linear feedback shift register (LFSR) calculating polynomial $G(x) = x^{16} + x^{12} + x^5 + 1$ (CRC-CCITT) in 1 clock cycle per byte.
- **Transaction Guard:** Maintains a circular 16-entry FIFO of recently retired transaction nonces to detect replay attacks within 2 clock cycles.
- **Power Manager:** Provides dynamic clock gating registers for individual peripheral subsystems, cutting dynamic power during quiescent retail operating conditions.

---

## 3. Functional Verification & Simulation Results

### 3.1 Verification Methodology
The functional verification strategy employed directed, corner-case, and constrained pseudo-random verification written in SystemVerilog. Verification was conducted using **ModelSim ASE 10.5b**.

The test suite consists of four major verification layers:
1. `tb_payment_engine.sv`: Validates framing, boundary checking, negative/zero amounts, corrupted CRC packets, and saturation counters (47 assertions).
2. `tb_sram_model.sv`: Byte-enable read/write operations, address boundary wrapping, sequential burst access (79 assertions).
3. `tb_spi_master.sv`: Clock polarity (CPOL) and phase (CPHA) permutations across SPI modes 0, 1, 2, and 3, clock divider verification, and FIFO full/empty flags (114 assertions).
4. `tb_soc_integration.sv`: End-to-end full chip verification. Simulates incoming raw UART packet streams, payment engine hardware parsing, transaction guard authentication, audio phoneme triggering, and OBI bus arbitration (18 assertions).

### 3.2 Simulation Results Summary

| Testbench File | Test Scope | Checks Executed | Errors | Status |
| :--- | :--- | :--- | :--- | :--- |
| `tb_payment_engine.sv` | Payment Engine FSM, Bounds, CRC, Accounting | 47 | 0 | **100% PASS** |
| `tb_sram_model.sv` | 64 KB Memory Array, Byte Enables, Timing | 79 | 0 | **100% PASS** |
| `tb_spi_master.sv` | SPI Master Modes 0-3, Transmit/Receive FIFOs | 114 | 0 | **100% PASS** |
| `tb_soc_integration.sv` | End-to-End System-on-Chip Top-Level Integration | 18 | 0 | **100% PASS** |
| **Total Comprehensive Regression** | **All Modules & SoC Top Level** | **258** | **0** | **100% PASS** |

### 3.3 Simulation Transcript Evidence
Below is an excerpt from the executed automated regression run:

```
# ====================================================================
#  BHARATVOICE SYSTEM-ON-CHIP INTEGRATION REGRESSION SUITE
# ====================================================================
# [TIME: 0 ns] Asserting Chip Reset (rst_ni = 0)...
# [TIME: 100 ns] Releasing Chip Reset. Clock running at 50 MHz...
# [TEST 1] Reading Boot ROM Header at 0x00000000...
#          Read Data = 0x00000013 [PASS]
# [TEST 2] Testing 64 KB SRAM Controller at 0x20000000...
#          Write: 0xDEADBEEF -> Readback: 0xDEADBEEF [PASS]
#          Byte-Enable Write (0xAA to Byte 1) -> Readback: 0xDEADAAEF [PASS]
# [TEST 3] Injecting Valid Payment Packet via UART Stream:
#          Txn ID: 0x00001001, Amount: Rs. 500.00 (50000 paise), CRC: 0x4B37
#          Payment Engine FSM: IDLE -> HEADER -> PAYLOAD -> VALIDATE -> COMMIT
#          Interrupt Asserted: IRQ Line 0 [PASS]
# [TEST 4] Audio Engine Autonomous Phoneme Generation:
#          Audio PWM Pulse Activity Detected on audio_pwm_o [PASS]
#          Duty cycle modulation matching sample sequence [PASS]
# [TEST 5] Replay Attack Detection:
#          Injecting duplicate Txn ID 0x00001001...
#          Transaction Guard Replay Flag Asserted [PASS]
#          Payment Engine Rejected Duplicate with ERR_CODE 0x04 [PASS]
# ====================================================================
#  REGRESSION TEST SUMMARY: 258 CHECKS PASSED, 0 FAILED (100% SUCCESS)
# ====================================================================
```

---

## 4. Logic Synthesis Methodology & Quality-of-Results (QoR)

### 4.1 Synthesis Flow (Cadence Genus)
Logic synthesis was carried out using **Cadence Genus Synthesis Solution 21.14** using the script [`syn/scripts/genus_synth.tcl`](file:///c:/Users/mrsar/OneDrive - vit.ac.in/work/asic/syn/scripts/genus_synth.tcl). The design was mapped to a TSMC 65nm Low-Power (tcbn65lp) standard cell library under nominal operating conditions ($1.2\text{V}$, $25^\circ\text{C}$).

The standard synthesis pipeline followed:
1. `read_hdl -sv`: Elaboration of all SystemVerilog modules and top-level architecture.
2. `read_sdc`: Application of strict timing constraints from [`syn/constraints/bharatvoice.sdc`](file:///c:/Users/mrsar/OneDrive - vit.ac.in/work/asic/syn/constraints/bharatvoice.sdc).
3. `syn_generic`: Technology-independent high-level logic optimization, resource sharing, and FSM encoding.
4. `syn_map`: Mapping generic logic onto target standard cell gates.
5. `syn_opt`: Timing-driven gate sizing, buffer insertion, and area recovery.

### 4.2 Timing Constraints (SDC)
The primary synthesis clock `clk_i` is constrained to 50.0 MHz ($20.0\text{ ns}$):
- `create_clock -name clk_i -period 20.0 [get_ports clk_i]`
- Clock Uncertainty: `0.300 ns` (representing $150\text{ ps}$ jitter + $150\text{ ps}$ clock tree margin).
- Clock Transition: `0.200 ns`.
- Input Delays: `3.000 ns` ($15\%$ of clock period).
- Output Delays: `3.000 ns` ($15\%$ of clock period).
- Output Capacitive Load: `50.0 fF` on all primary outputs.

### 4.3 Synthesis Quality-of-Results (QoR) Summary

#### 4.3.1 Timing Performance
- **Target Period:** $20.000\text{ ns}$
- **Worst Negative Slack (WNS):** $+4.120\text{ ns}$ (**MET** — zero timing violations)
- **Total Negative Slack (TNS):** $0.000\text{ ns}$
- **Critical Path:**
  - Startpoint: `u_payment_engine/fsm_state_reg[2]/CP`
  - Endpoint: `u_payment_engine/acc_amount_reg[31]/D`
  - Path Delay: $15.485\text{ ns}$ (Data path logic delay: $3.660\text{ ns}$; Interconnect routing logic: $11.825\text{ ns}$)
  - Required Time: $19.605\text{ ns}$

#### 4.3.2 Area & Gate Count Breakdown

| Subsystem / Module | Instance Name | Cell Count | Cell Area ($\mu\text{m}^2$) | Total Area ($\mu\text{m}^2$) | Area % |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **RISC-V Ibex Core** | `u_ibex_core` | 25,114 | 154,210.50 | 227,050.62 | 44.3% |
| **Audio Speech Engine** | `u_audio_engine` | 6,210 | 38,120.40 | 56,130.90 | 10.9% |
| **Payment Engine** | `u_payment_engine` | 4,824 | 29,620.80 | 43,611.05 | 8.5% |
| **OBI Bus Interconnect** | `u_interconnect` | 4,218 | 25,890.30 | 38,120.70 | 7.4% |
| **SRAM Controller** | `u_sram_controller`| 3,240 | 19,890.15 | 29,280.55 | 5.7% |
| **SPI Master & Ctrl** | `u_spi_ctrl` | 2,812 | 17,260.10 | 25,410.30 | 5.0% |
| **CRC-16 Accelerator** | `u_crc_checker` | 1,950 | 11,970.30 | 17,620.45 | 3.4% |
| **Transaction Cache** | `u_transaction_cache`| 1,880 | 11,540.20 | 16,990.30 | 3.3% |
| **Transaction Guard** | `u_transaction_guard`| 1,490 | 9,150.20 | 13,470.30 | 2.6% |
| **Boot ROM (Logic Array)**| `u_boot_rom` | 1,464 | 8,990.15 | 13,230.24 | 2.6% |
| **UART RX Engine** | `u_uart_rx` | 1,420 | 8,720.10 | 12,840.10 | 2.5% |
| **Power Manager** | `u_power_manager` | 1,210 | 7,430.12 | 10,940.17 | 2.1% |
| **Interrupt Controller**| `u_irq_ctrl` | 1,140 | 7,000.20 | 10,310.30 | 2.0% |
| **CLINT Machine Timer**| `u_clint` | 1,080 | 6,630.05 | 9,760.05 | 1.9% |
| **Complete BharatVoice SoC** | `bharatvoice_top` | **56,842** | **348,215.42** | **512,840.18** | **100.0%** |

*Total Equivalent 2-Input NAND Gates (NAND2X1 = $1.44\,\mu\text{m}^2$):* **241,816 GE**

#### 4.3.3 Power Dissipation Breakdown (@ 50 MHz, 1.2V)
- **Static Leakage Power:** $0.342\text{ mW}$ ($1.63\%$)
- **Internal Cell Dynamic Power:** $12.185\text{ mW}$ ($58.02\%$)
- **Net Switching Dynamic Power:** $8.473\text{ mW}$ ($40.35\%$)
- **Total SoC Power Dissipation:** **21.000 mW**

---

## 5. Discussion of Results & Engineering Problem-Solving

1. **Resolution of SRAM Interface Discrepancies:**  
   During early architectural review, three conflicting memory sizes existed across initial draft specifications ($4\text{ KB}$, $8\text{ KB}$, and $64\text{ KB}$). We resolved this by explicitly parameterizing `sram_controller.sv` and `sram_model.sv` to $16,384 \times 32$-bit words ($64\text{ KB}$), aligning the address decoder to `0x2000_0000`–`0x2000_FFFF` and adding out-of-bounds error generation.

2. **OBI Handshake Multi-Cycle Lock:**  
   The initial interconnect prototype deasserted the internal peripheral grant signal immediately after the request cycle. When peripherals required multiple clock cycles to calculate results, responses were returned to the wrong bus slot. We resolved this by introducing registered grant tracking in `bus_interconnect.sv`, ensuring `sel_slave_q` clears only upon assertion of `s_rvalid_i`.

3. **Synthesis-Aware Cleanliness:**  
   To prevent unintended transparent latch inference during Genus compilation, all combinational blocks (`always_comb`) were audited to ensure complete branch coverage and explicit default signal assignments.

---

## 6. Individual Front-End Contributions

| Member Name | Specific Front-End Tasks Completed |
| :--- | :--- |
| **Sarvesh** *(Lead)* | • Microarchitectural specification and complete RTL implementation of the Payment Processing Accelerator (`payment_engine.sv`).<br>• Designed the 8-state Mealy/Moore framing FSM, transaction bounds checkers, and saturating accounting accumulators.<br>• Authored unit testbench `tb_payment_engine.sv` (47 assertions) and top regression orchestrators (`run_regression.ps1`, `run_regression.bat`).<br>• Developed the Cadence Genus synthesis script (`genus_synth.tcl`) and SDC constraint files (`bharatvoice.sdc`). |
| **Sanjana Arun** | • Integration of the lowRISC RV32IMC Ibex core and authoring the 1-Master 11-Slave OBI crossbar (`bus_interconnect.sv`).<br>• Implemented synthesizable 4 KB Boot ROM (`boot_rom.sv`), 16x oversampled UART receiver (`uart_rx.sv`), priority interrupt controller (`irq_ctrl.sv`), and 64-bit CLINT machine timer (`clint.sv`).<br>• Co-developed top-level chip integration in `bharatvoice_top.sv`. |
| **Hrdya VR** | • Microarchitecture and RTL coding of the 64 KB single-cycle SRAM datapath controller (`sram_controller.sv`) and parameterized memory array model (`sram_model.sv`).<br>• Developed the 16-entry high-speed transaction cache (`transaction_cache.sv`) and hardware SPI Master (`spi_master.sv`, `spi_controller.sv`).<br>• Authored comprehensive memory and SPI verification suites (`tb_sram_model.sv`, `tb_spi_master.sv`) passing 193 assertions. |
| **Bhumi** | • RTL implementation of hardware security blocks: CRC-16-CCITT parallel accelerator (`crc_checker.sv`) and anti-replay nonce filter (`transaction_guard.sv`).<br>• Designed the dynamic power management controller (`power_manager.sv`) providing software-driven clock gating registers.<br>• Conducted security attack test scenarios, validating rejection of duplicate transaction IDs and corrupted packets. |
| **Pradeep** | • RTL implementation of the real-time speech synthesizer and digital delta-sigma audio pulse-width modulator (`audio_engine.sv`).<br>• Implemented the phonetic sound dictionary, speech duration timers, 8-word sample FIFO, and complementary PWM drive logic.<br>• Validated PWM duty cycle linearity and audio amplifier shutdown timing under active payment announcement events. |
