# BharatVoice SoC — Architecture Document

**Project:** BharatVoice Payment Announcement SoC  
**Owner:** Sanjana Arun (RISC-V Core & SoC Integration)  
**Revision:** 0.1 — Draft  
**Date:** 2026-10-14  

---

## 1. Overview

BharatVoice is a custom ASIC SoC designed to receive payment transactions over a serial interface, validate the transaction, announce the payment amount over audio, and log records into on-chip SRAM. The system is controlled by an embedded RISC-V processor (Ibex core) and communicates with the external world through SPI and UART.

---

## 2. Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                       BharatVoice SoC                               │
│                                                                     │
│  ┌─────────────┐      ┌──────────────────────────────────────────┐  │
│  │             │      │            OBI Bus Interconnect           │  │
│  │  Ibex Core  │◄────►│  (32-bit address, 32-bit data, 4-byte)   │  │
│  │  (RV32IMC)  │      │                                          │  │
│  └─────────────┘      └──────────┬───────────────────────────────┘  │
│                                  │                                  │
│         ┌────────────────────────┼──────────────────────────┐       │
│         │              │         │          │                │       │
│         ▼              ▼         ▼          ▼                ▼       │
│  ┌────────────┐ ┌──────────┐ ┌──────┐ ┌────────┐ ┌──────────────┐  │
│  │Boot ROM    │ │Data SRAM │ │Paym. │ │Audio   │ │Security &    │  │
│  │(4 KB)      │ │(64 KB)   │ │Engine│ │Engine  │ │Power Manager │  │
│  └────────────┘ └──────────┘ └──────┘ └────────┘ └──────────────┘  │
│                                                                     │
│         ┌────────────────────────────────────┐                      │
│         │              │         │            │                      │
│         ▼              ▼         ▼            ▼                      │
│  ┌────────────┐ ┌──────────┐ ┌──────┐ ┌─────────────┐              │
│  │SPI Master  │ │Trans.    │ │UART  │ │Interrupt    │              │
│  │Controller  │ │Cache     │ │RX    │ │Controller   │              │
│  └────────────┘ └──────────┘ └──────┘ └─────────────┘              │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              GPIO / Clock / Reset Block                     │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Ibex Core Integration

### 3.1 Core Selection

| Property        | Value                               |
|-----------------|-------------------------------------|
| Core            | ibex (lowRISC)                      |
| ISA             | RV32IMC (base + multiply + compressed) |
| License         | Apache 2.0                          |
| Pipeline        | 2-stage (IF, ID/EX)                 |
| Bus Interface   | OBI (Open Bus Interface) v1.0       |
| Multiplier      | Single-cycle fast multiplier        |
| Debug           | JTAG / RISC-V Debug Spec 0.13       |

### 3.2 OBI Bus Interface Signals

Ibex presents two OBI master ports: one for instruction fetch (I-port) and one for data access (D-port).

#### Instruction OBI Port (Master → Slave)
| Signal              | Width | Direction | Description                     |
|---------------------|-------|-----------|---------------------------------|
| `instr_req_o`       | 1     | OUT       | Request valid                   |
| `instr_gnt_i`       | 1     | IN        | Grant from interconnect         |
| `instr_addr_o`      | 32    | OUT       | Fetch address (word-aligned)    |
| `instr_rdata_i`     | 32    | IN        | Instruction data                |
| `instr_rvalid_i`    | 1     | IN        | Read data valid                 |
| `instr_err_i`       | 1     | IN        | Bus error                       |

#### Data OBI Port (Master → Slave)
| Signal              | Width | Direction | Description                     |
|---------------------|-------|-----------|---------------------------------|
| `data_req_o`        | 1     | OUT       | Request valid                   |
| `data_gnt_i`        | 1     | IN        | Grant from interconnect         |
| `data_addr_o`       | 32    | OUT       | Read/write address              |
| `data_we_o`         | 1     | OUT       | Write enable                    |
| `data_be_o`         | 4     | OUT       | Byte enables                    |
| `data_wdata_o`      | 32    | OUT       | Write data                      |
| `data_rdata_i`      | 32    | IN        | Read data                       |
| `data_rvalid_i`     | 1     | IN        | Read data valid                 |
| `data_err_i`        | 1     | IN        | Bus error                       |

### 3.3 Clock and Reset

| Signal         | Description                                           |
|----------------|-------------------------------------------------------|
| `clk_i`        | System clock (target: 50 MHz for first tape-out)      |
| `rst_ni`       | Active-low asynchronous reset (power-on reset)        |
| `fetch_enable_i` | Enables instruction fetch after reset de-assertion  |

### 3.4 Interrupt Interface

Ibex accepts a 256-bit fast interrupt vector (`irq_fast_i[14:0]`) plus standard RISC-V MIP bits. We map peripherals as fast interrupts for minimal latency.

| IRQ Line   | Peripheral Source          | Priority |
|------------|----------------------------|----------|
| `irq_fast[0]` | Payment Engine — TXN done | High     |
| `irq_fast[1]` | Audio Engine — playback done | Medium |
| `irq_fast[2]` | UART RX — data available   | High     |
| `irq_fast[3]` | SPI Master — transfer done | Medium   |
| `irq_fast[4]` | Security — CRC fail        | High     |
| `irq_fast[5]` | Power Manager — wake-up    | High     |
| `irq_timer`   | Machine Timer (CLINT)      | —        |
| `irq_external`| External (PLIC stub)       | —        |

---

## 4. Bus Architecture

### 4.1 Bus Topology

The BharatVoice SoC uses a **shared OBI bus** with a lightweight address decoder / multiplexer implemented in `bus_interconnect.sv`. The Ibex data port is the single master. All peripherals are slaves.

- Instruction fetches go directly to Boot ROM and Data SRAM via a separate path (I-port).
- Data accesses are arbitrated by the interconnect using address-range decoding.
- No burst transfers in first version; all transfers are single-beat.

### 4.2 Bus Parameters

| Parameter       | Value          |
|-----------------|----------------|
| Address width   | 32 bits        |
| Data width      | 32 bits        |
| Byte enables    | 4 bits         |
| Max masters     | 1 (Ibex D-port) |
| Max slaves      | 8              |
| Transfer type   | Single-beat OBI |

---

## 5. Peripheral Overview

| Peripheral           | Owner   | Status     | RTL File               |
|----------------------|---------|------------|------------------------|
| Boot ROM             | Sanjana | Stub (ROM model) | `boot_rom.sv`    |
| Data SRAM            | Hrdya   | Stub → Real | `sram_model.sv`  |
| Payment Engine       | Sarvesh | Real RTL   | `payment_engine.sv`    |
| Audio Engine         | Pradeep | Real RTL   | `audio_engine.sv`      |
| SRAM Controller      | Hrdya   | Real RTL   | `sram_controller.sv`   |
| Transaction Cache    | Hrdya   | Real RTL   | `transaction_cache.sv` |
| SPI Master           | Hrdya   | Real RTL   | `spi_master.sv`        |
| CRC Checker          | Bhumi   | Real RTL   | `crc_checker.sv`       |
| Transaction Guard    | Bhumi   | Real RTL   | `transaction_guard.sv` |
| Power Manager        | Bhumi   | Real RTL   | `power_manager.sv`     |
| UART RX              | Sanjana | Stub       | `uart_rx.sv`           |
| Interrupt Controller | Sanjana | Stub       | `irq_ctrl.sv`          |
| CLINT (Timer)        | Sanjana | Stub       | `clint.sv`             |

---

## 6. Clock and Reset Architecture

```
External Pin
  clk_in ──► [Clock Buffer] ──► clk_sys (50 MHz) ──► all synchronous logic
  rst_n  ──► [Reset Sync]   ──► rst_sys_n (sync deassert, async assert)
                                   │
                                   ├──► ibex_core
                                   ├──► bus_interconnect
                                   └──► all peripherals
```

- All flops use `clk_sys` (single clock domain for first version)
- Reset is synchronously released (deasserted) to avoid metastability
- Power Manager controls an optional clock-gate cell for sleep mode

---

## 7. Interface Contracts (Pending)

The following interfaces must be frozen before final wiring:

| Interface               | Between                | Status  |
|-------------------------|------------------------|---------|
| Transaction format      | Sarvesh ↔ Bhumi        | Pending |
| Amount → token encoding | Sarvesh → Pradeep      | Pending |
| Sample memory protocol  | Pradeep ↔ Hrdya        | Pending |
| Register/bus spec       | All → Sanjana          | Pending |

---

## 8. Design Guidelines

1. All RTL must be synthesizable (no `#delay`, no `initial` blocks in RTL).
2. Use synchronous active-low reset convention: `always_ff @(posedge clk_i or negedge rst_ni)`.
3. No latches; always use full case/default in FSMs.
4. Parameterize all widths and depths.
5. Use `logic` type throughout (avoid `wire`/`reg` mix).
6. All OBI transfers must complete within 1 cycle (zero wait-state in first version).

---

## 9. Revision History

| Rev | Date       | Author  | Notes                         |
|-----|------------|---------|-------------------------------|
| 0.1 | 2026-10-14 | Sanjana | Initial draft, placeholder architecture |
