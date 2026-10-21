# BharatVoice SoC — Architecture Refinement & Frozen Transaction Protocol Specification

**Author:** Sarvesh (Lead Designer, Payment Processing Engine) & BharatVoice SoC Team  
**Date:** October 16, 2026  
**Document Revision:** 1.0 (Frozen Specification)  
**Target:** 50 MHz TSMC/SkyWater ASIC Flow (RV32IMC Ibex Core + Custom Accelerators)

---

## 1. Executive Summary & Bus Architecture Refinement

### 1.1 Faculty Report Amendment (Technical Justification)
The submitted BharatVoice proposal originally evaluated standard multi-master SoC interconnects (such as AXI4-Lite and AHB-Lite). During our detailed architectural analysis and five-week project scoping, the interconnect strategy was formally refined:

* **Original Proposal:** AXI4-Lite / AHB-Lite bus interconnect.
* **Refined Implementation:** Native Open Bus Interface (OBI v1.0) request/grant/response protocol matching the lowRISC Ibex core specification.
* **Technical Rationale:**
  1. **Zero Translation Overhead:** Ibex presents native OBI master ports for both instruction (`instr_*`) and data (`data_*`). Using OBI eliminates multiple protocol bridges, master wrappers, and slave converters that would otherwise increase critical path latency and logic area.
  2. **Deterministic Verification Contract:** A single-beat OBI crossbar reduces verification complexity compared to AXI4-Lite split channels (AW, W, B, AR, R), allowing our verification schedule to concentrate on transaction security, accelerator correctness, and audio timing.
  3. **Preserved Educational & Functional Objectives:** Memory-mapped peripherals, CPU firmware intervention, memory protection, interrupt aggregation, deterministic validation, and end-to-end ASIC flow (RTL-to-GDSII) remain fully preserved.

> [!IMPORTANT]
> **Faculty Presentation Rule:** Do not describe the interconnect as "AXI/AHB-compliant". Accurately document it as a **Native OBI Interconnect (Single-Master, N-Slave Crossbar)**.

---

## 2. Memory Map & Interconnect Reconciliation

### 2.1 Fixed Memory Capacities
The discrepancies identified between `memory_map.md`, `sram_model.sv`, and `sram_interface_spec.pdf` are officially resolved as follows:

| Region | Address Range | Size | Allocation / Description |
|---|---|---|---|
| **Boot ROM** | `0x0000_0000` – `0x0000_0FFF` | 4 KB | 1024 words × 32-bit (Boot vector, NOP sled, Bring-up firmware) |
| **Data SRAM** | `0x2000_0000` – `0x2000_FFFF` | **64 KB** | **16,384 words × 32-bit (Primary on-chip data & stack memory)** |
| **Peripheral I/O** | `0x4000_0000` – `0x4000_AFFF` | 44 KB | 11 dedicated 4 KB slots (Payment, Audio, SRAM Ctrl, etc.) |
| **Invalid Access** | All other addresses | — | Trapped by Interconnect -> returns `err_o = 1'b1`, `rdata = 32'hDEAD_BEEF` |

### 2.2 Datapath vs Control Register Separation
1. **Direct Data SRAM (`0x2000_0000` – `0x2000_FFFF`):** Direct high-throughput datapath connected to the core's data/instruction interfaces.
2. **SRAM Controller Registers (`0x4000_2000` – `0x4000_2FFF`):** Control and status registers (ECC error counters, fault injection, configuration).

### 2.3 Single-Cycle OBI Bus Contract
All peripheral slaves on the interconnect adhere to a strict synchronous single-cycle response contract:
* **Grant Phase (Cycle $N$):** When `req_i` is asserted by the master and decoded to a slave, the slave asserts `gnt_o = 1'b1` combinationally.
* **Response Phase (Cycle $N+1$):** Exactly one clock cycle after grant, the slave asserts `rvalid_o = 1'b1`, drives `rdata_o`, and asserts `err_o` if the access is invalid.
* **Interconnect Muxing:** The interconnect captures `sel_slave` at Cycle $N$ into `sel_slave_q` and routes the slave response to the CPU in Cycle $N+1$.

---

## 3. Sarvesh's Payment Processing Engine Specification

```
                  ┌───────────────────────────────────────────────┐
                  │          Payment Processing Engine            │
                  │                   (Sarvesh)                   │
                  └───────────────────────┬───────────────────────┘
                                          │
       UART Byte Stream                   ▼                     Audio Engine
  ─────────────────────────► ┌─────────────────────────┐ ──────────────────────►
  (rx_data_i, rx_valid_i)    │   Frame Parser & FSM    │ (amount_o, txn_valid_o)
                             └────────────┬────────────┘
                                          │
                                          ▼
                             ┌─────────────────────────┐
                             │  CRC-16-CCITT Checker   │
                             └────────────┬────────────┘
                                          │
                                          ▼
                             ┌─────────────────────────┐
                             │  Validation & Anti-Dup  │
                             └────────────┬────────────┘
                                          │
       Ibex OBI Bus                       ▼                     Interrupts
  ◄────────────────────────► ┌─────────────────────────┐ ──────────────────────►
  (req, gnt, addr, r/wdata)  │   Memory-Mapped Regs    │ (irq_done_o, irq_fail_o)
                             └─────────────────────────┘
```

### 3.1 Frozen Transaction Frame Protocol (14 Bytes)

The hardware parser processes transactions formatted as a strict 14-byte binary packet transmitted via the serial/UART stream:

| Byte Offset | Field Name | Width | Expected Value / Format | Description |
|---|---|---|---|---|
| `0` | **SOF** | 8 bits | `0xAA` | Start of Frame delimiter |
| `1` | **VER_LEN** | 8 bits | `0x18` | Protocol version (`0x1` high nibble) + payload length (`8` bytes low nibble) |
| `2..5` | **TXN_ID** | 32 bits | Big-Endian Unsigned Integer | Monotonically increasing transaction sequence ID |
| `6..9` | **AMOUNT** | 32 bits | Big-Endian Unsigned Integer | Amount in smallest currency unit (**paise**, e.g., ₹10.50 = 1050) |
| `10` | **FLAGS** | 8 bits | Bitfield | bit[0]: Normal payment, bit[1]: Refund, bit[7]: Test mode |
| `11..12`| **CRC16** | 16 bits | Big-Endian (`{crc_hi, crc_lo}`) | CRC-16-CCITT (poly `0x1021`, init `0xFFFF`) calculated over Bytes 1..10 |
| `13` | **EOF** | 8 bits | `0x55` | End of Frame delimiter |

### 3.2 Hardware Validation & Safety Rules
1. **Framing Validation:** Packets with incorrect `SOF`, invalid `VER_LEN`, or incorrect `EOF` are immediately flagged and dropped to the error state.
2. **Amount Bounds Checking:**
   * $0 < \text{AMOUNT} \le \text{MAX\_AMOUNT}$.
   * Zero amounts (`AMOUNT == 0`) are rejected.
   * Amounts exceeding `TXN_MAX_AMOUNT` register (default `1,000,000` paise = ₹10,000.00) are rejected.
3. **CRC-16-CCITT Integrity:**
   * Polynomial: $x^{16} + x^{12} + x^5 + 1$ (`0x1021`), Initial: `0xFFFF`.
   * On-the-fly byte-serial computation.
   * Transactions with CRC mismatch are discarded without updating audio outputs.
4. **Duplicate Detection:**
   * If `TXN_CTRL[2]` (block duplicates) is enabled, any packet whose `TXN_ID` matches `last_txn_id` is rejected.
5. **Commit & Announce Guarantee:**
   * `amount_o` is updated and `txn_valid_o` is pulsed **if and only if** all validation steps succeed.
   * Failed transactions pulse `irq_fail_o`, record the error in `TXN_ERR_CODE`, and leave `txn_valid_o` deasserted.

### 3.3 Register Memory Map (`0x4000_0000`)

| Offset | Name | Type | Reset Value | Description |
|---|---|---|---|---|
| `0x00` | `TXN_CTRL` | RW | `0x0000_0005` | bit[0]: Enable, bit[1]: Soft Reset, bit[2]: Block Duplicates |
| `0x04` | `TXN_STATUS` | RO | `0x0000_0000` | bit[0]: Valid, bit[1]: Fail, bit[2]: Busy, bit[3]: Duplicate, bit[4]: CRC Err |
| `0x08` | `TXN_AMOUNT` | RO | `0x0000_0000` | Last successfully committed transaction amount (in paise) |
| `0x0C` | `TXN_ID` | RO | `0x0000_0000` | Last successfully committed transaction ID |
| `0x10` | `TXN_IRQ_EN` | RW | `0x0000_0003` | bit[0]: Done IRQ Enable, bit[1]: Fail IRQ Enable |
| `0x14` | `TXN_IRQ_STATUS` | RW1C | `0x0000_0000` | bit[0]: Done IRQ pending, bit[1]: Fail IRQ pending (Write 1 to clear) |
| `0x18` | `TXN_ERR_CODE` | RO | `0x0000_0000` | Diagnostic code for the last failed transaction |
| `0x1C` | `TXN_MAX_AMOUNT` | RW | `0x000F_4240` | Upper bound for valid transactions (`1,000,000` paise = ₹10,000) |

#### Error Code Encodings:
* `0x00`: No Error
* `0x01`: Framing Error (Missing `SOF` `0xAA`)
* `0x02`: Bad Header / Version / Length (Expected `0x18`)
* `0x03`: CRC-16 Integrity Mismatch
* `0x04`: Framing Error (Missing `EOF` `0x55`)
* `0x05`: Zero Amount Error (`AMOUNT == 0`)
* `0x06`: Upper Bound Exceeded (`AMOUNT > TXN_MAX_AMOUNT`)
* `0x07`: Duplicate Transaction Detected (`TXN_ID == last_txn_id`)

---

## 4. Verification & Simulation Strategy

### 4.1 Verification Levels
1. **Unit Level:** Self-checking testbench (`tb_payment_engine.sv`) with corner cases:
   * Valid single and sequential transactions.
   * Corrupted payload bit flip (CRC failure).
   * Framing violations (wrong SOF, truncated packet, wrong EOF).
   * Out-of-bounds amount (zero amount and excessive amount).
   * Duplicate transaction handling.
   * Memory-mapped OBI read/write register access.
   * Interrupt generation and RW1C clearing.
2. **Integration Level:** Connection between `uart_rx` -> `payment_engine` -> `audio_engine`.
3. **SoC Level:** Ibex software firmware polling `TXN_STATUS` or servicing `irq_fast[0]`.
