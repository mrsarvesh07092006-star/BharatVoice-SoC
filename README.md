# BharatVoice SoC — SRAM model and SPI master (bus-independent)

Owner: Hrdya VR (memory / SPI / transaction cache). No AXI/AHB/APB/Ibex adapters, no register wrappers.
`Ibex_suggestions.docx` was **not** included in the upload, so nothing here depends on it; the bus-facing choices are listed under "Parameters to agree".

## Files
| File | Purpose |
|---|---|
| `sram_model.sv` | Behavioral, parameterized SRAM with byte enables, fixed read latency, error on invalid address |
| `tb_sram_model.sv` | Self-checking TB: cycle-accurate scoreboard + directed tests, timeout |
| `spi_master.sv` | Synthesizable SPI master, modes 0–3, MSB-first, 1–`DATA_W` bits, clock divider |
| `tb_spi_master.sv` | Self-checking TB with an edge-accurate SPI slave model (not a loopback) |
| `run_iverilog.sh` | Convenience script (run with `sh run_iverilog.sh`) |

## sram_model — interface
| Signal | Dir | Width | Meaning |
|---|---|---|---|
| clk | in | 1 | clock |
| rst_n | in | 1 | active-low **synchronous** reset |
| req | in | 1 | request valid |
| we | in | 1 | 1 write / 0 read |
| addr | in | ADDR_W | **byte** address; low log2(DATA_W/8) bits ignored |
| wdata | in | DATA_W | write data |
| be | in | DATA_W/8 | byte enables (writes only) |
| ready | out | 1 | can accept; request accepted when `req && ready` at a clock edge |
| rvalid | out | 1 | 1-cycle response pulse for every accepted request (read and write) |
| rdata | out | DATA_W | read data; 0 for valid write ack and when idle; `ERR_RDATA` on error |
| err | out | 1 | with rvalid: address out of range |

Parameters (defaults): `ADDR_W=32, DATA_W=32, DEPTH=1024, READ_LATENCY=1, INIT_MODE=0, INIT_VALUE=0, ERR_RDATA=0xDEADBEEF, INIT_FILE=""`.

Behavior contract
- **Timing:** accepted at edge N → response visible after edge N+L−1 (L=`READ_LATENCY`≥1). One request per cycle, fully pipelined, in order.
- **Write commit** at the accept edge → a read accepted on the next edge sees the new data.
- **Invalid address** (word index ≥ DEPTH): no array access, `rvalid=1, err=1, rdata=ERR_RDATA`. Misaligned in-range addresses access the containing word (no error). `be==0` write: no change, no error.
- **Reset:** `ready` drops, in-flight (not yet visible) responses are dropped, a request on a reset edge is ignored. `ready` returns one clock after release. **Memory contents survive reset.**
- **Initialization:** explicit — fill with `INIT_VALUE` (default 0), `'x`, or `$readmemh`.
- **Simulation vs synthesizable:** the clocked read/write/pipeline logic is synthesizable (RAM-inference candidate). The `initial` init/X-fill/`$readmemh` and `$fatal` parameter checks are simulation-oriented. It is not a physical macro.

## spi_master — interface
| Signal | Dir | Width | Meaning |
|---|---|---|---|
| clk | in | 1 | system clock |
| rst_n | in | 1 | active-low, async assert |
| start | in | 1 | level-sampled when not busy; use a 1-cycle pulse |
| tx_data | in | DATA_W | right-aligned; bit `xfer_len-1` sent first |
| xfer_len | in | clog2(DATA_W+1) | bits, valid 1..DATA_W |
| clk_div | in | CLK_DIV_W | SCLK half-period in clk cycles, ≥1; f_sclk = f_clk/(2·clk_div) |
| cpol / cpha | in | 1 / 1 | SPI mode |
| busy | out | 1 | high from accept to done (cs_n low) |
| done | out | 1 | 1-cycle pulse with cs_n rising; rx_data valid |
| err_cfg | out | 1 | 1-cycle pulse: start rejected (len 0 / >DATA_W / div 0) |
| err_busy | out | 1 | 1-cycle pulse: start while busy (ignored) |
| rx_data | out | DATA_W | right-aligned receive data, upper bits 0 |
| sclk, mosi, cs_n | out | 1 | SPI pins (idle: sclk=cpol, mosi=0, cs_n=1) |
| miso | in | 1 | sampled directly |

Defaults: `DATA_W=32, CLK_DIV_W=16`.

Timing (T=clk period, D=clk_div, N=xfer_len, A0=accept edge): `cs_n` falls and `busy` rises at A0; SCLK edge k (0…2N−1) at A0+(k+1)·D·T; `cs_n` rises, `busy` falls, `done` pulses at A0+(2N+1)·D·T. CS setup and hold are each D·T. `cs_n` stays high ≥1 clk between transfers; `start` may be asserted in the `done` cycle.
- Mode 0/2 (cpha=0): first bit on MOSI at CS fall, sample on leading edge, shift on trailing edge. Mode 1/3 (cpha=1): shift on leading edge, sample on trailing edge.
- Config is latched at accept; keep `cpol` stable ≥1 clk before `start`.
- Reset mid-transfer: immediate idle outputs, no `done`, frame truncated, usable right after release.

## Compile / run
Icarus Verilog (≥11, `-g2012` required):
```sh
iverilog -g2012 -Wall -o sim_sram sram_model.sv tb_sram_model.sv && vvp sim_sram
iverilog -g2012 -Ptb_sram_model.LAT=3 -o sim_sram3 sram_model.sv tb_sram_model.sv && vvp sim_sram3   # other latency
iverilog -g2012 -Wall -o sim_spi spi_master.sv tb_spi_master.sv && vvp sim_spi
```
Questa/ModelSim (**commands not executed by the author — no Questa licence was available**):
```sh
vlib work
vlog -sv sram_model.sv tb_sram_model.sv spi_master.sv tb_spi_master.sv
vsim -c work.tb_sram_model -GLAT=1 -do "run -all; quit -f"
vsim -c work.tb_sram_model -GLAT=3 -do "run -all; quit -f"
vsim -c work.tb_spi_master -do "run -all; quit -f"
```
Compatibility notes: `sram_model` uses plain `always` (not `always_ff`) because `mem` also has an `initial` writer, which Questa rejects for `always_ff`. Parameter override syntax differs (`-P<top>.<name>=` vs `-G<name>=`). The TBs avoid queues/classes/randomize so they stay Icarus-friendly; randomness is a local xorshift so results are identical across simulators. Both end with `REGRESSION RESULT: PASS|FAIL`.

## Verified results (executed with Icarus Verilog 12.0)
- `tb_sram_model`: 79 directed checks + scoreboard, 0 failures at READ_LATENCY = 1, 2 and 3.
- `tb_spi_master`: 114 checks, 0 failures.
- Fault injection: 8 deliberately broken RTL variants (wrong sample edge, wrong shift edge, off-by-one setup, missing length check, missing busy flag, ignored byte enables, no address range check, reset not clearing pipeline) were all caught.

## Test cases (stimulus → expected → how checked)
**SRAM** (`ready/rvalid/rdata/err` are checked every cycle by the scoreboard, plus directed checks):
1. Reset: reset 3 cycles, write presented during reset → ready/rvalid/rdata/err idle, ready returns 1 clock after release, write ignored, memory reads 0.
2. Single word write then read → same data.
3. Words 0–15 written with distinct patterns, read back.
4. Byte enables 0001, 0010, 1010, 0000 on a known word → only enabled bytes change.
5. Write then read next cycle → read returns new data.
6. 8 back-to-back writes, 8 back-to-back reads, W/R/W/R alternate → one response per request, in order, correct data.
7. First and last word; neighbours untouched.
8. Invalid addresses (first invalid, highest, write to invalid) → `err=1, rdata=DEADBEEF`, no wrap-around corruption; misaligned in-range reads the word.
9. Latency measured equals `LAT`; rvalid single-cycle; none when idle; one response per request.
10. Reset between transactions (contents survive), with a read in flight (dropped if LAT>1, delivered if LAT=1), during a write stream (earlier writes kept, write on reset edge ignored).

**SPI** (slave model samples/drives only on the correct edge, drives X when no bit is due):
1. Reset/idle levels incl. SCLK following CPOL. 2. TX 0x9C (non-palindrome) MSB-first with garbage upper bits. 3. RX 0x6B. 4. Full duplex, 16 bit, all four modes. 5. clk_div 1,2,3,5,8 → measured half-period = div·T. 6. Modes 0–3 with 8 and 13 bits. 7. CS low exactly (2N+1)·D cycles. 8. Done time = (2N+1)·D·T, busy spans transfer. 9. Four different back-to-back configs and start-in-done-cycle (cs_n high exactly 1 clk). 10. Start while busy with all inputs disturbed → err_busy pulse, transfer unchanged, no queued transfer. 11. Async reset mid-frame → idle immediately, truncated frame, no done, new transfers work. 12. len 0/33/63, div 0 → err_cfg, no CS/busy/done. 13. 1-bit and 32-bit in all modes. 14. 40 random transfers, each bounded by a per-transfer timeout (deadlock detection) plus a global watchdog. Each transfer also checks edge count, first-edge direction, MOSI setup/hold ≥1 clk, done/err pulse width.

## Assumptions and limitations
- SRAM verified at DATA_W=32 only (RTL is parameterized); ADDR_W ≤ 32.
- SRAM is single-port, word-access, always-ready after reset (no back-pressure model).
- SPI: single CS, no MISO synchronizer/late sampling, no CS-high minimum time, `DATA_W ≥ 2`, `start` must be a pulse.
- Questa/ModelSim not run; Verilator and synthesis not run.

## Integration notes
SPI → Flash: a wrapper (later) maps a command register to `start/tx_data/xfer_len`, reads `rx_data` on `done`. A Flash read (e.g. cmd 0x03 + 24-bit addr + data) is either several `start` pulses with CS toggling between bytes (needs a "keep CS low" feature — not implemented) or one long transfer ≤ `DATA_W`; set `DATA_W=32` for command+address in one frame, or add a CS-hold option. Use mode 0, `clk_div` ≥ ceil(f_clk / (2·f_sclk_max)).
SRAM model → SRAM controller: controller drives `req/we/addr/wdata/be`, treats `rvalid` as response, `err` as bus error; `READ_LATENCY` should match the real macro's latency.

Example instantiation:
```systemverilog
sram_model #(.ADDR_W(32), .DATA_W(32), .DEPTH(4096), .READ_LATENCY(1)) u_sram (
  .clk, .rst_n, .req, .we, .addr, .wdata, .be, .ready, .rvalid, .rdata, .err);
spi_master #(.DATA_W(32), .CLK_DIV_W(16)) u_spi (
  .clk, .rst_n, .start, .tx_data, .xfer_len, .clk_div, .cpol, .cpha,
  .busy, .done, .err_cfg, .err_busy, .rx_data, .sclk, .mosi, .miso, .cs_n);
```
Parameters to agree before integration: clock frequency and reset polarity/synchronisation; SRAM depth, data width, byte vs word addressing and read latency; error reporting policy (`err` → bus error?); SPI max transfer length, max SCLK, mode(s) used by the Flash, CS handling for multi-byte commands, interrupt/status needs on `done`/`err_*`.
