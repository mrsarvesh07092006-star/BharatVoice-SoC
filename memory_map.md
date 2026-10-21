# BharatVoice SoC — Peripheral Address Map

**Project:** BharatVoice Payment Announcement SoC  
**Owner:** Sanjana Arun  
**Revision:** 0.1 — Draft  
**Date:** 2026-10-14  

---

## 1. Address Space Overview

The BharatVoice SoC uses a 32-bit flat address space. The layout follows a simple region-based decode. All peripherals are naturally aligned to their region size.

```
0xFFFF_FFFF ┌──────────────────────────────┐
            │        Reserved              │
0x4000_0000 ├──────────────────────────────┤
            │   Peripheral Region (I/O)    │  (256 MB — split into sub-regions)
0x2000_0000 ├──────────────────────────────┤
            │     Data SRAM (64 KB)        │
0x1001_0000 ├──────────────────────────────┤
            │     Reserved                 │
0x1000_0000 ├──────────────────────────────┤
            │     Boot ROM  (4 KB)         │
0x0000_0000 └──────────────────────────────┘
```

---

## 2. Detailed Address Map

### 2.1 Memory Regions

| Region         | Base Address | End Address  | Size   | Type       | Owner   |
|----------------|--------------|--------------|--------|------------|---------|
| Boot ROM       | `0x0000_0000`| `0x0000_0FFF`| 4 KB   | ROM        | Sanjana |
| Data SRAM      | `0x2000_0000`| `0x2000_FFFF`| 64 KB  | SRAM       | Hrdya   |
| Peripheral I/O | `0x4000_0000`| `0x4FFF_FFFF`| 256 MB | Mapped I/O | Various |

### 2.2 Peripheral Sub-Regions

Each peripheral occupies a 4 KB page (256 registers × 16 bytes, aligned). Only used registers are defined; others read back `0x00000000`.

| Peripheral           | Base Address | End Address  | Size | Owner   |
|----------------------|--------------|--------------|------|---------|
| Payment Engine       | `0x4000_0000`| `0x4000_0FFF`| 4 KB | Sarvesh |
| Audio Engine         | `0x4000_1000`| `0x4000_1FFF`| 4 KB | Pradeep |
| SRAM Controller      | `0x4000_2000`| `0x4000_2FFF`| 4 KB | Hrdya   |
| Transaction Cache    | `0x4000_3000`| `0x4000_3FFF`| 4 KB | Hrdya   |
| SPI Master           | `0x4000_4000`| `0x4000_4FFF`| 4 KB | Hrdya   |
| CRC Checker          | `0x4000_5000`| `0x4000_5FFF`| 4 KB | Bhumi   |
| Transaction Guard    | `0x4000_6000`| `0x4000_6FFF`| 4 KB | Bhumi   |
| Power Manager        | `0x4000_7000`| `0x4000_7FFF`| 4 KB | Bhumi   |
| UART RX              | `0x4000_8000`| `0x4000_8FFF`| 4 KB | Sanjana |
| Interrupt Controller | `0x4000_9000`| `0x4000_9FFF`| 4 KB | Sanjana |
| CLINT (Timer)        | `0x4000_A000`| `0x4000_AFFF`| 4 KB | Sanjana |
| Reserved             | `0x4000_B000`| `0x4FFF_FFFF`| —    | —       |

---

## 3. Register Definitions

### 3.1 Payment Engine Registers (`0x4000_0000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `TXN_CTRL`       | RW     | `0x0000`   | [0]=enable, [1]=clear                    |
| `0x04` | `TXN_STATUS`     | RO     | `0x0000`   | [0]=valid, [1]=fail, [2]=busy            |
| `0x08` | `TXN_AMOUNT`     | RO     | `0x0000`   | Validated transaction amount (32-bit)    |
| `0x0C` | `TXN_ID`         | RO     | `0x0000`   | Transaction sequence number              |
| `0x10` | `TXN_IRQ_EN`     | RW     | `0x0000`   | [0]=done_irq_en, [1]=fail_irq_en         |
| `0x14` | `TXN_IRQ_STATUS` | RW1C   | `0x0000`   | [0]=done, [1]=fail (write 1 to clear)    |
| `0x18` | `TXN_ERR_CODE`   | RO     | `0x0000`   | Error code for failed transactions       |
| `0x1C` | `TXN_MAX_AMOUNT` | RW     | `0xFFFF`   | Maximum valid amount threshold           |

### 3.2 Audio Engine Registers (`0x4000_1000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `AUD_CTRL`       | RW     | `0x0000`   | [0]=play_start, [1]=stop, [2]=repeat     |
| `0x04` | `AUD_STATUS`     | RO     | `0x0000`   | [0]=playing, [1]=done, [2]=error         |
| `0x08` | `AUD_AMOUNT`     | RW     | `0x0000`   | Amount to announce (triggers token map)  |
| `0x0C` | `AUD_TOKEN_PTR`  | RO     | `0x0000`   | Current token index in sequence          |
| `0x10` | `AUD_IRQ_EN`     | RW     | `0x0000`   | [0]=done_irq_en                          |
| `0x14` | `AUD_IRQ_STATUS` | RW1C   | `0x0000`   | [0]=playback_done                        |
| `0x18` | `AUD_PWM_PERIOD` | RW     | `0x0064`   | PWM period in clock cycles               |
| `0x1C` | `AUD_VOL`        | RW     | `0x00FF`   | Volume / PWM duty scale factor           |

### 3.3 SRAM Controller Registers (`0x4000_2000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `SRAM_CTRL`      | RW     | `0x0000`   | [0]=enable, [1]=clear_ecc                |
| `0x04` | `SRAM_STATUS`    | RO     | `0x0000`   | [0]=ready, [1]=ecc_error                 |
| `0x08` | `SRAM_BASE`      | RW     | `0x2000_0000` | Base address of managed SRAM          |
| `0x0C` | `SRAM_SIZE`      | RO     | `0x0001_0000` | SRAM size in bytes (64 KB)            |
| `0x10` | `SRAM_ECC_ADDR`  | RO     | `0x0000`   | Address of last ECC error                |

### 3.4 Transaction Cache Registers (`0x4000_3000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `CACHE_CTRL`     | RW     | `0x0000`   | [0]=enable, [1]=flush                    |
| `0x04` | `CACHE_STATUS`   | RO     | `0x0000`   | [0]=hit, [1]=miss, [2]=full              |
| `0x08` | `CACHE_ENTRIES`  | RO     | `0x0010`   | Number of cache entries (16)             |
| `0x0C` | `CACHE_HIT_CNT`  | RO     | `0x0000`   | Cache hit counter (for debug)            |
| `0x10` | `CACHE_MISS_CNT` | RO     | `0x0000`   | Cache miss counter (for debug)           |

### 3.5 SPI Master Registers (`0x4000_4000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `SPI_CTRL`       | RW     | `0x0000`   | [0]=enable, [1]=start, [2]=cpol, [3]=cpha |
| `0x04` | `SPI_STATUS`     | RO     | `0x0000`   | [0]=busy, [1]=done, [2]=tx_empty         |
| `0x08` | `SPI_TX_DATA`    | RW     | `0x0000`   | Transmit data register (8-bit LSB)       |
| `0x0C` | `SPI_RX_DATA`    | RO     | `0x0000`   | Receive data register (8-bit LSB)        |
| `0x10` | `SPI_CLK_DIV`    | RW     | `0x0004`   | Clock divider (spi_clk = sys_clk / div)  |
| `0x14` | `SPI_CS_CTRL`    | RW     | `0x0000`   | Chip select control (1 = deassert)       |
| `0x18` | `SPI_IRQ_EN`     | RW     | `0x0000`   | [0]=done_irq_en                          |
| `0x1C` | `SPI_IRQ_STATUS` | RW1C   | `0x0000`   | [0]=done                                 |

### 3.6 CRC Checker Registers (`0x4000_5000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `CRC_CTRL`       | RW     | `0x0000`   | [0]=enable, [1]=reset_crc                |
| `0x04` | `CRC_STATUS`     | RO     | `0x0000`   | [0]=done, [1]=fail, [2]=busy             |
| `0x08` | `CRC_INPUT`      | RW     | `0x0000`   | Data byte to feed into CRC engine        |
| `0x0C` | `CRC_RESULT`     | RO     | `0x0000`   | Computed CRC value                       |
| `0x10` | `CRC_EXPECTED`   | RW     | `0x0000`   | Expected CRC from transaction            |
| `0x14` | `CRC_POLY`       | RW     | `0x1021`   | CRC polynomial (default CRC-16/CCITT)    |

### 3.7 Transaction Guard Registers (`0x4000_6000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `GUARD_CTRL`     | RW     | `0x0000`   | [0]=enable, [1]=block_duplicates         |
| `0x04` | `GUARD_STATUS`   | RO     | `0x0000`   | [0]=ok, [1]=crc_fail, [2]=duplicate      |
| `0x08` | `GUARD_TXN_ID`   | RO     | `0x0000`   | Last seen transaction ID                 |
| `0x0C` | `GUARD_FAIL_CNT` | RO     | `0x0000`   | Count of rejected transactions           |
| `0x10` | `GUARD_IRQ_EN`   | RW     | `0x0000`   | [0]=crc_fail_irq_en                      |
| `0x14` | `GUARD_IRQ_STS`  | RW1C   | `0x0000`   | [0]=crc_fail, [1]=duplicate              |

### 3.8 Power Manager Registers (`0x4000_7000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `PWR_CTRL`       | RW     | `0x0001`   | [0]=active, [1]=sleep_req                |
| `0x04` | `PWR_STATUS`     | RO     | `0x0001`   | [0]=active, [1]=sleep, [2]=wakeup_pend   |
| `0x08` | `PWR_WAKEUP_SRC` | RW     | `0x0001`   | Wakeup source mask [0]=uart [1]=spi      |
| `0x0C` | `PWR_SLEEP_CNT`  | RO     | `0x0000`   | Number of sleep cycles (debug)           |
| `0x10` | `PWR_IRQ_EN`     | RW     | `0x0000`   | [0]=wakeup_irq_en                        |
| `0x14` | `PWR_IRQ_STS`    | RW1C   | `0x0000`   | [0]=wakeup event                         |

### 3.9 UART RX Registers (`0x4000_8000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `UART_CTRL`      | RW     | `0x0001`   | [0]=enable, [1]=rx_clear                 |
| `0x04` | `UART_STATUS`    | RO     | `0x0000`   | [0]=rx_valid, [1]=rx_full, [2]=rx_err    |
| `0x08` | `UART_RX_DATA`   | RO     | `0x0000`   | Received byte (8-bit, auto-clear)        |
| `0x0C` | `UART_BAUD_DIV`  | RW     | `0x01B2`   | Baud rate divisor (50MHz / 115200 ≈ 434) |
| `0x10` | `UART_IRQ_EN`    | RW     | `0x0000`   | [0]=rx_valid_irq_en                      |
| `0x14` | `UART_IRQ_STS`   | RW1C   | `0x0000`   | [0]=rx_valid                             |

### 3.10 Interrupt Controller Registers (`0x4000_9000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `IRQ_EN`         | RW     | `0x0000`   | Interrupt enable mask (bit per source)   |
| `0x04` | `IRQ_PENDING`    | RO     | `0x0000`   | Pending interrupt bits                   |
| `0x08` | `IRQ_CLEAR`      | WO     | `0x0000`   | Write 1 to clear pending bit             |
| `0x0C` | `IRQ_PRIORITY`   | RW     | `0x0000`   | Priority field (4 bits per source)       |

### 3.11 CLINT Timer Registers (`0x4000_A000`)

| Offset | Name             | Access | Reset      | Description                              |
|--------|------------------|--------|------------|------------------------------------------|
| `0x00` | `MTIME_LO`       | RW     | `0x0000`   | Machine timer low 32 bits                |
| `0x04` | `MTIME_HI`       | RW     | `0x0000`   | Machine timer high 32 bits               |
| `0x08` | `MTIMECMP_LO`    | RW     | `0xFFFF`   | Timer compare low 32 bits                |
| `0x0C` | `MTIMECMP_HI`    | RW     | `0xFFFF`   | Timer compare high 32 bits               |

---

## 4. Address Decode Logic

The interconnect uses the top 4 bits of the 32-bit address to select the region, then bits [15:12] to select the peripheral within the I/O region.

```
Bits [31:28] = 4'h0  → Boot ROM          (0x0xxx_xxxx)
Bits [31:28] = 4'h2  → Data SRAM         (0x2xxx_xxxx)
Bits [31:28] = 4'h4  → Peripheral region (0x4xxx_xxxx)
  Bits [15:12]:
    4'h0 → Payment Engine
    4'h1 → Audio Engine
    4'h2 → SRAM Controller
    4'h3 → Transaction Cache
    4'h4 → SPI Master
    4'h5 → CRC Checker
    4'h6 → Transaction Guard
    4'h7 → Power Manager
    4'h8 → UART RX
    4'h9 → Interrupt Controller
    4'hA → CLINT Timer
    default → Error / no decode
```

---

## 5. Revision History

| Rev | Date       | Author  | Notes                                         |
|-----|------------|---------|-----------------------------------------------|
| 0.1 | 2026-10-14 | Sanjana | Initial draft — addresses assigned, registers TBD pending interface freeze |
