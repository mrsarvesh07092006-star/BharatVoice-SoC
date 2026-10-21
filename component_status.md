# BharatVoice SoC — RTL Status and Component Registry
# File   : component_status.md
# Author : Sanjana Arun
# Date   : 2026-10-14

## Overview

This document tracks which RTL modules are production-ready ("Real RTL") and
which are temporary behavioural stubs.  All stubs must be replaced before
synthesis / tape-out.

---

## Component Table

| Module File          | Module Name        | Status      | Owner   | RTL Location           | Stub Location      |
|----------------------|--------------------|-------------|---------|------------------------|--------------------|
| `bharatvoice_top.sv` | `bharatvoice_top`  | **Real**    | Sanjana | `rtl/bharatvoice_top.sv` | —                |
| `bus_interconnect.sv`| `bus_interconnect` | **Real**    | Sanjana | `rtl/bus_interconnect.sv`| —                |
| `stubs.sv`           | `boot_rom`         | **Stub**    | Sanjana | Replace with ROM macro | `rtl/stubs.sv`     |
| `stubs.sv`           | `uart_rx`          | **Stub**    | Sanjana | `rtl/uart_rx.sv` (TBD)| `rtl/stubs.sv`     |
| `stubs.sv`           | `irq_ctrl`         | **Stub**    | Sanjana | `rtl/irq_ctrl.sv` (TBD)| `rtl/stubs.sv`    |
| `stubs.sv`           | `clint`            | **Stub**    | Sanjana | `rtl/clint.sv` (TBD)  | `rtl/stubs.sv`     |
| `payment_engine.sv`  | `payment_engine`   | **Real**    | Sarvesh | `payment_engine.sv`    | —                  |
| `audio_engine.sv`    | `audio_engine`     | **Stub → Real** | Pradeep | Pending delivery | `rtl/stubs.sv`|
| `sram_controller.sv` | `sram_controller`  | **Stub → Real** | Hrdya   | Pending delivery | `rtl/stubs.sv`|
| `transaction_cache.sv`| `transaction_cache`| **Stub → Real** | Hrdya  | Pending delivery | `rtl/stubs.sv`|
| `spi_master.sv`      | `spi_master`       | **Stub → Real** | Hrdya   | Pending delivery | `rtl/stubs.sv`|
| `crc_checker.sv`     | `crc_checker`      | **Stub → Real** | Bhumi   | Pending delivery | `rtl/stubs.sv`|
| `transaction_guard.sv`| `transaction_guard`| **Stub → Real** | Bhumi  | Pending delivery | `rtl/stubs.sv`|
| `power_manager.sv`   | `power_manager`    | **Stub → Real** | Bhumi   | Pending delivery | `rtl/stubs.sv`|

---

## Integration Checklist

When a team member delivers their real RTL:

1. Copy the module file(s) to `rtl/`.
2. Remove the corresponding stub from `rtl/stubs.sv` (or comment it out).
3. Update the instantiation in `bharatvoice_top.sv` if port names changed.
4. Re-run regression: `sim/run_sim.sh`
5. Update this table — change status from "Stub → Real" to "Real".
6. Confirm no new linting warnings in `sim/lint_report.txt`.

---

## Stub Behaviour

All stubs follow a uniform contract:
- OBI requests granted with **zero wait-states** (`gnt_o = req_i`)
- Reads return **`0xA5A5_A5A5`** for diagnostic identification
- All interrupt outputs held **low**
- All data outputs held at **safe defaults** (0 or 1 as appropriate)

---

## Known Limitations (stubs)

| Stub        | Missing Functionality                                |
|-------------|------------------------------------------------------|
| `boot_rom`  | NOP sled only; no real firmware binary               |
| `uart_rx`   | Physical UART not parsed; `rx_valid_o` always 0      |
| `irq_ctrl`  | No priority encoding; no masking                    |
| `clint`     | Counter present; no SW interrupt support            |
| `payment_engine` | No UART frame parsing; amount always 0         |
| `audio_engine`   | No PWM output; no token sequence               |
| `sram_controller`| No ECC; behavioural SRAM model only            |
| `transaction_cache` | No actual caching; reads return stub value  |
| `spi_master`     | No SPI signalling                              |
| `crc_checker`    | No CRC computation                             |
| `transaction_guard` | No duplicate detection                      |
| `power_manager`  | Always active; no sleep/wake logic             |

---

## Revision History

| Rev | Date       | Author  | Notes                                      |
|-----|------------|---------|--------------------------------------------|
| 0.1 | 2026-10-14 | Sanjana | Initial draft — all peripherals are stubs  |
