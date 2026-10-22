# BharatVoice SoC — RTL Status and Component Registry
# File   : component_status.md
# Revision : 1.0 (All Real Production RTL Integrated)
# Date   : 2026-10-22

## Overview

This document tracks all RTL modules in the BharatVoice SoC. All peripheral
modules and interconnects have been implemented as production-ready synthesizable
SystemVerilog RTL and verified with automated testbenches.

---

## Component Table

| Module File           | Module Name        | Status   | Owner   | RTL Location            | Description |
|-----------------------|--------------------|----------|---------|-------------------------|-------------|
| `bharatvoice_top.sv`  | `bharatvoice_top`  | **Real** | Sanjana | `bharatvoice_top.sv`    | Top-level SoC integration |
| `bus_interconnect.sv` | `bus_interconnect` | **Real** | Sanjana | `bus_interconnect.sv`   | 1-Master 11-Slave OBI crossbar |
| `boot_rom.sv`         | `boot_rom`         | **Real** | Sanjana | `boot_rom.sv`           | 4 KB synthesizable RISC-V ROM |
| `uart_rx.sv`          | `uart_rx`          | **Real** | Sanjana | `uart_rx.sv`            | 16x oversampled UART receiver |
| `irq_ctrl.sv`         | `irq_ctrl`         | **Real** | Sanjana | `irq_ctrl.sv`           | Priority interrupt controller |
| `clint.sv`            | `clint`            | **Real** | Sanjana | `clint.sv`              | RISC-V 64-bit machine timer |
| `payment_engine.sv`   | `payment_engine`   | **Real** | Sarvesh | `payment_engine.sv`     | Payment accelerator & CRC |
| `audio_engine.sv`     | `audio_engine`     | **Real** | Pradeep | `audio_engine.sv`       | Speech synthesizer & PWM output |
| `sram_controller.sv`  | `sram_controller`  | **Real** | Hrdya   | `sram_controller.sv`    | 64 KB SRAM datapath & controller |
| `sram_model.sv`       | `sram_model`       | **Real** | Hrdya   | `sram_model.sv`         | Parameterized behavioral SRAM |
| `transaction_cache.sv`| `transaction_cache`| **Real** | Hrdya   | `transaction_cache.sv`  | 16-entry fast transaction cache |
| `spi_master.sv`       | `spi_master`       | **Real** | Hrdya   | `spi_master.sv`         | SPI master (modes 0-3) |
| `crc_checker.sv`      | `crc_checker`      | **Real** | Bhumi   | `crc_checker.sv`        | Hardware CRC accelerator |
| `transaction_guard.sv`| `transaction_guard`| **Real** | Bhumi   | `transaction_guard.sv`  | Replay attack & duplicate guard |
| `power_manager.sv`    | `power_manager`    | **Real** | Bhumi   | `power_manager.sv`      | Low-power clock gating manager |

---

## Integration Status: 100% Complete

All stubs have been graduated to Real RTL. Every module features:
1. Strict Open Bus Interface (OBI v1.0) compliance with zero-wait-state grant.
2. Synchronous active-low reset release (`rst_ni`).
3. Fully defined and address-decoded memory map.
4. Dedicated hardware interrupts and status registers.
