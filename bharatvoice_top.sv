// =============================================================================
// BharatVoice SoC — Top-Level Module
// File   : bharatvoice_top.sv
// Author : Sanjana Arun
// Date   : 2026-10-14
// Rev    : 0.1
//
// Description:
//   Top-level integration of the BharatVoice SoC. Instantiates the Ibex
//   RISC-V core, the OBI bus interconnect, and all peripheral blocks.
//   Peripheral modules that are not yet delivered are instantiated as
//   behavioural stubs so the top-level compiles and can be simulated.
//
// Status key:
//   [REAL]  – module has real RTL (from a team member or IP)
//   [STUB]  – behavioural placeholder; replace before tape-out
// =============================================================================

`timescale 1ns/1ps

module bharatvoice_top (
    // -----------------------------------------------------------------
    // External ports
    // -----------------------------------------------------------------
    input  logic        clk_i,          // System clock (50 MHz target)
    input  logic        rst_ni,         // Active-low async reset

    // UART — receive channel (transaction stream from payment terminal)
    input  logic        uart_rx_i,

    // SPI external flash / peripheral
    output logic        spi_sclk_o,
    output logic        spi_mosi_o,
    input  logic        spi_miso_i,
    output logic        spi_cs_n_o,

    // PWM audio output
    output logic        pwm_audio_o,

    // JTAG debug
    input  logic        jtag_tck_i,
    input  logic        jtag_tms_i,
    input  logic        jtag_tdi_i,
    output logic        jtag_tdo_o,

    // General purpose outputs (LEDs / status)
    output logic [3:0]  gpio_o
);

// =============================================================================
// Internal parameters
// =============================================================================
localparam int unsigned DATA_WIDTH    = 32;
localparam int unsigned ADDR_WIDTH    = 32;
localparam int unsigned N_PERIPHERALS = 11; // number of peripheral slaves

// =============================================================================
// Clock / reset synchronisation
// =============================================================================
// Synchronise the external reset to the system clock (two-flop synchroniser).
// Deassertion of rst_ni must be synchronous to avoid metastability in logic.
logic rst_sync_n;
logic rst_ff1, rst_ff2;

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        rst_ff1    <= 1'b0;
        rst_ff2    <= 1'b0;
    end else begin
        rst_ff1    <= 1'b1;
        rst_ff2    <= rst_ff1;
    end
end

assign rst_sync_n = rst_ff2;

// =============================================================================
// OBI bus wires — Ibex Instruction port (I-port) → ROM / SRAM
// =============================================================================
logic        instr_req;
logic        instr_gnt;
logic [31:0] instr_addr;
logic [31:0] instr_rdata;
logic        instr_rvalid;
logic        instr_err;

// =============================================================================
// OBI bus wires — Ibex Data port (D-port) → bus interconnect
// =============================================================================
logic        data_req;
logic        data_gnt;
logic [31:0] data_addr;
logic        data_we;
logic [ 3:0] data_be;
logic [31:0] data_wdata;
logic [31:0] data_rdata;
logic        data_rvalid;
logic        data_err;

// =============================================================================
// Interrupt wires (fast interrupts to Ibex)
// =============================================================================
logic [14:0] irq_fast;          // fast interrupt vector to Ibex
logic        irq_timer;         // machine timer interrupt (from CLINT)
logic        irq_external;      // external interrupt (from PLIC stub)

// Individual interrupt sources (connected by each peripheral)
logic        irq_payment_done;
logic        irq_audio_done;
logic        irq_uart_rx;
logic        irq_spi_done;
logic        irq_crc_fail;
logic        irq_power_wakeup;

// IRQ aggregation — map sources to Ibex fast interrupt vector
assign irq_fast[0]  = irq_payment_done;
assign irq_fast[1]  = irq_audio_done;
assign irq_fast[2]  = irq_uart_rx;
assign irq_fast[3]  = irq_spi_done;
assign irq_fast[4]  = irq_crc_fail;
assign irq_fast[5]  = irq_power_wakeup;
assign irq_fast[14:6] = '0;         // unused fast IRQ lines

// =============================================================================
// OBI per-slave buses (output from interconnect → each peripheral)
// =============================================================================
// Naming: s<n>_* where n is the peripheral index in the address map

// Slave port signals
logic [N_PERIPHERALS-1:0] sl_req;
logic [N_PERIPHERALS-1:0] sl_gnt;
logic [31:0]              sl_addr   [N_PERIPHERALS-1:0];
logic [N_PERIPHERALS-1:0] sl_we;
logic [ 3:0]              sl_be     [N_PERIPHERALS-1:0];
logic [31:0]              sl_wdata  [N_PERIPHERALS-1:0];
logic [31:0]              sl_rdata  [N_PERIPHERALS-1:0];
logic [N_PERIPHERALS-1:0] sl_rvalid;
logic [N_PERIPHERALS-1:0] sl_err;

// =============================================================================
// Peripheral data wires
// =============================================================================
// Payment → Audio: validated amount trigger
logic [31:0] payment_amount;
logic        payment_valid;
// UART RX → Payment Engine byte stream
logic [ 7:0] uart_byte_data;
logic        uart_byte_valid;
// Power manager: clock-gate enable
logic        clk_en;

// =============================================================================
// [REAL] Ibex RISC-V core
// NOTE: The ibex_core wrapper below uses the lowRISC ibex port names.
//       Connect ibex repository as a submodule under rtl/ibex/.
// =============================================================================
ibex_core #(
    .PMPEnable        (1'b0),
    .MHPMCounterNum   (0   ),
    .RV32E            (1'b0),  // Use full RV32I (not embedded)
    .ICache           (1'b0),
    .ICacheECC        (1'b0),
    .BranchTargetALU  (1'b1),
    .WritebackStage   (1'b1),
    .BranchPredictor  (1'b0),
    .DbgTriggerEn     (1'b0),
    .DmHaltAddr       (32'h0000_0000),
    .DmExceptionAddr  (32'h0000_0004)
) u_ibex_core (
    .clk_i              (clk_i        ),
    .rst_ni             (rst_sync_n   ),
    // Instruction OBI
    .instr_req_o        (instr_req    ),
    .instr_gnt_i        (instr_gnt    ),
    .instr_addr_o       (instr_addr   ),
    .instr_rdata_i      (instr_rdata  ),
    .instr_rvalid_i     (instr_rvalid ),
    .instr_err_i        (instr_err    ),
    // Data OBI
    .data_req_o         (data_req     ),
    .data_gnt_i         (data_gnt     ),
    .data_addr_o        (data_addr    ),
    .data_we_o          (data_we      ),
    .data_be_o          (data_be      ),
    .data_wdata_o       (data_wdata   ),
    .data_rdata_i       (data_rdata   ),
    .data_rvalid_i      (data_rvalid  ),
    .data_err_i         (data_err     ),
    // Interrupts
    .irq_software_i     (1'b0         ),
    .irq_timer_i        (irq_timer    ),
    .irq_external_i     (irq_external ),
    .irq_fast_i         (irq_fast     ),
    .irq_nm_i           (1'b0         ),
    // Debug (JTAG)
    .debug_req_i        (1'b0         ), // TODO: connect JTAG module
    .crash_dump_o       (             ),
    // Fetch enable
    .fetch_enable_i     (4'b0101      ), // IBEX_FETCH_ENABLE value
    .core_sleep_o       (             )
);

// =============================================================================
// [STUB] Boot ROM (4 KB)
// Real: replace with a synthesizable ROM containing the boot firmware.
// =============================================================================
boot_rom #(
    .DEPTH (1024) // 1024 × 32-bit = 4 KB
) u_boot_rom (
    .clk_i    (clk_i      ),
    .rst_ni   (rst_sync_n ),
    // I-port (instruction fetch)
    .req_i    (instr_req  ),
    .addr_i   (instr_addr ),
    .rdata_o  (instr_rdata),
    .rvalid_o (instr_rvalid),
    .gnt_o    (instr_gnt  ),
    .err_o    (instr_err  )
);

// =============================================================================
// [REAL] OBI Bus Interconnect
// Routes the Ibex D-port to the appropriate peripheral slave.
// =============================================================================
bus_interconnect #(
    .N_SLAVES (N_PERIPHERALS)
) u_bus_interconnect (
    .clk_i       (clk_i     ),
    .rst_ni      (rst_sync_n),
    // Master (Ibex D-port)
    .m_req_i     (data_req  ),
    .m_gnt_o     (data_gnt  ),
    .m_addr_i    (data_addr ),
    .m_we_i      (data_we   ),
    .m_be_i      (data_be   ),
    .m_wdata_i   (data_wdata),
    .m_rdata_o   (data_rdata),
    .m_rvalid_o  (data_rvalid),
    .m_err_o     (data_err  ),
    // Slave ports (flat arrays)
    .s_req_o     (sl_req    ),
    .s_gnt_i     (sl_gnt    ),
    .s_addr_o    (sl_addr   ),
    .s_we_o      (sl_we     ),
    .s_be_o      (sl_be     ),
    .s_wdata_o   (sl_wdata  ),
    .s_rdata_i   (sl_rdata  ),
    .s_rvalid_i  (sl_rvalid ),
    .s_err_i     (sl_err    )
);

// =============================================================================
// [REAL] Data SRAM — 64 KB  [Owner: Hrdya]
// Connected through SRAM controller at peripheral index 2.
// The raw SRAM is at address 0x2000_0000 (direct-mapped, no peripheral decode).
// Stub SRAM model used until Hrdya's sram_controller is integrated.
// =============================================================================
// Note: SRAM is memory-mapped directly; we add a simple adapter here.
// Separate OBI slave on instr_port range 0x2000_0000.
// For now the sram_controller peripheral registers at 0x4000_2000 (sl[2])
// manage ECC/control. The raw SRAM is reachable via data_addr decode.
sram_controller #(
    .ADDR_WIDTH (16), // 64 KB array = 16-bit byte address
    .DATA_WIDTH (32)
`ifdef SYNTHESIS
    ,.MEM_DEPTH (256)
`else
    ,.MEM_DEPTH (16384)
`endif
) u_sram_ctrl (
    .clk_i    (clk_i           ),
    .rst_ni   (rst_sync_n      ),
    // OBI register interface (control/status at 0x4000_2000)
    .reg_req_i    (sl_req  [2] ),
    .reg_gnt_o    (sl_gnt  [2] ),
    .reg_addr_i   (sl_addr [2] ),
    .reg_we_i     (sl_we   [2] ),
    .reg_be_i     (sl_be   [2] ),
    .reg_wdata_i  (sl_wdata[2] ),
    .reg_rdata_o  (sl_rdata[2] ),
    .reg_rvalid_o (sl_rvalid[2]),
    .reg_err_o    (sl_err  [2] )
);

// =============================================================================
// [REAL] Payment Engine  [Owner: Sarvesh] — peripheral index 0
// =============================================================================
payment_engine u_payment_engine (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    // OBI bus interface
    .req_i          (sl_req  [0]     ),
    .gnt_o          (sl_gnt  [0]     ),
    .addr_i         (sl_addr [0]     ),
    .we_i           (sl_we   [0]     ),
    .be_i           (sl_be   [0]     ),
    .wdata_i        (sl_wdata[0]     ),
    .rdata_o        (sl_rdata[0]     ),
    .rvalid_o       (sl_rvalid[0]    ),
    .err_o          (sl_err  [0]     ),
    // UART raw byte stream (from UART RX stub)
    .uart_data_i    (uart_byte_data  ),
    .uart_valid_i   (uart_byte_valid ),
    // Outputs to other peripherals
    .amount_o       (payment_amount  ),
    .txn_valid_o    (payment_valid   ),
    // Interrupt
    .irq_done_o     (irq_payment_done),
    .irq_fail_o     (               )
);

// =============================================================================
// [REAL] Audio Engine  [Owner: Pradeep] — peripheral index 1
// =============================================================================
audio_engine u_audio_engine (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    // OBI bus interface
    .req_i          (sl_req  [1]     ),
    .gnt_o          (sl_gnt  [1]     ),
    .addr_i         (sl_addr [1]     ),
    .we_i           (sl_we   [1]     ),
    .be_i           (sl_be   [1]     ),
    .wdata_i        (sl_wdata[1]     ),
    .rdata_o        (sl_rdata[1]     ),
    .rvalid_o       (sl_rvalid[1]    ),
    .err_o          (sl_err  [1]     ),
    // Amount from payment engine
    .amount_i       (payment_amount  ),
    .amount_valid_i (payment_valid   ),
    // PWM audio output
    .pwm_o          (pwm_audio_o     ),
    // Interrupt
    .irq_done_o     (irq_audio_done  )
);

// =============================================================================
// [REAL] Transaction Cache  [Owner: Hrdya] — peripheral index 3
// =============================================================================
transaction_cache u_txn_cache (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    .req_i          (sl_req  [3]     ),
    .gnt_o          (sl_gnt  [3]     ),
    .addr_i         (sl_addr [3]     ),
    .we_i           (sl_we   [3]     ),
    .be_i           (sl_be   [3]     ),
    .wdata_i        (sl_wdata[3]     ),
    .rdata_o        (sl_rdata[3]     ),
    .rvalid_o       (sl_rvalid[3]    ),
    .err_o          (sl_err  [3]     )
);

// =============================================================================
// [REAL] SPI Master  [Owner: Hrdya] — peripheral index 4
// =============================================================================
// [REAL] SPI Master Controller [Owner: Hrdya] — peripheral index 4
// =============================================================================
spi_controller u_spi_master (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    .req_i          (sl_req  [4]     ),
    .gnt_o          (sl_gnt  [4]     ),
    .addr_i         (sl_addr [4]     ),
    .we_i           (sl_we   [4]     ),
    .be_i           (sl_be   [4]     ),
    .wdata_i        (sl_wdata[4]     ),
    .rdata_o        (sl_rdata[4]     ),
    .rvalid_o       (sl_rvalid[4]    ),
    .err_o          (sl_err  [4]     ),
    // SPI external pins
    .sclk_o         (spi_sclk_o      ),
    .mosi_o         (spi_mosi_o      ),
    .miso_i         (spi_miso_i      ),
    .cs_n_o         (spi_cs_n_o      ),
    // Interrupt
    .irq_done_o     (irq_spi_done    )
);

// =============================================================================
// [REAL] CRC Checker  [Owner: Bhumi] — peripheral index 5
// =============================================================================
crc_checker u_crc_checker (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    .req_i          (sl_req  [5]     ),
    .gnt_o          (sl_gnt  [5]     ),
    .addr_i         (sl_addr [5]     ),
    .we_i           (sl_we   [5]     ),
    .be_i           (sl_be   [5]     ),
    .wdata_i        (sl_wdata[5]     ),
    .rdata_o        (sl_rdata[5]     ),
    .rvalid_o       (sl_rvalid[5]    ),
    .err_o          (sl_err  [5]     ),
    // Interrupt
    .irq_crc_fail_o (irq_crc_fail    )
);

// =============================================================================
// [REAL] Transaction Guard  [Owner: Bhumi] — peripheral index 6
// =============================================================================
transaction_guard u_txn_guard (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    .req_i          (sl_req  [6]     ),
    .gnt_o          (sl_gnt  [6]     ),
    .addr_i         (sl_addr [6]     ),
    .we_i           (sl_we   [6]     ),
    .be_i           (sl_be   [6]     ),
    .wdata_i        (sl_wdata[6]     ),
    .rdata_o        (sl_rdata[6]     ),
    .rvalid_o       (sl_rvalid[6]    ),
    .err_o          (sl_err  [6]     )
);

// =============================================================================
// [REAL] Power Manager  [Owner: Bhumi] — peripheral index 7
// =============================================================================
power_manager u_power_manager (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    .req_i          (sl_req  [7]     ),
    .gnt_o          (sl_gnt  [7]     ),
    .addr_i         (sl_addr [7]     ),
    .we_i           (sl_we   [7]     ),
    .be_i           (sl_be   [7]     ),
    .wdata_i        (sl_wdata[7]     ),
    .rdata_o        (sl_rdata[7]     ),
    .rvalid_o       (sl_rvalid[7]    ),
    .err_o          (sl_err  [7]     ),
    // Wake sources
    .uart_rx_i      (uart_rx_i       ),
    .spi_activity_i (1'b0            ),
    // Interrupt
    .irq_wakeup_o   (irq_power_wakeup),
    // Clock gate control
    .clk_en_o       (clk_en          )
);

// =============================================================================
// [REAL] UART RX  — peripheral index 8
// Parses serial byte stream from uart_rx_i and forwards bytes to payment_engine.
// =============================================================================
uart_rx #(
    .CLK_FREQ_HZ (50_000_000),
    .BAUD_RATE   (115200    )
) u_uart_rx (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    // OBI register interface
    .req_i          (sl_req  [8]     ),
    .gnt_o          (sl_gnt  [8]     ),
    .addr_i         (sl_addr [8]     ),
    .we_i           (sl_we   [8]     ),
    .be_i           (sl_be   [8]     ),
    .wdata_i        (sl_wdata[8]     ),
    .rdata_o        (sl_rdata[8]     ),
    .rvalid_o       (sl_rvalid[8]    ),
    .err_o          (sl_err  [8]     ),
    // Physical UART pin
    .uart_rx_i      (uart_rx_i       ),
    // Byte output to Payment Engine
    .rx_data_o      (uart_byte_data  ),
    .rx_valid_o     (uart_byte_valid ),
    // Interrupt
    .irq_rx_o       (irq_uart_rx     )
);

// =============================================================================
// [STUB] Interrupt Controller — peripheral index 9
// Collects all IRQ lines; forwards to Ibex fast-IRQ vector.
// (Simple passthrough in first version; replace with priority encoder.)
// =============================================================================
irq_ctrl u_irq_ctrl (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    .req_i          (sl_req  [9]     ),
    .gnt_o          (sl_gnt  [9]     ),
    .addr_i         (sl_addr [9]     ),
    .we_i           (sl_we   [9]     ),
    .be_i           (sl_be   [9]     ),
    .wdata_i        (sl_wdata[9]     ),
    .rdata_o        (sl_rdata[9]     ),
    .rvalid_o       (sl_rvalid[9]    ),
    .err_o          (sl_err  [9]     )
);

// =============================================================================
// [STUB] CLINT (Machine Timer) — peripheral index 10
// Generates irq_timer for Ibex. Standard RISC-V CLINT behaviour.
// =============================================================================
clint u_clint (
    .clk_i          (clk_i           ),
    .rst_ni         (rst_sync_n      ),
    .req_i          (sl_req  [10]    ),
    .gnt_o          (sl_gnt  [10]    ),
    .addr_i         (sl_addr [10]    ),
    .we_i           (sl_we   [10]    ),
    .be_i           (sl_be   [10]    ),
    .wdata_i        (sl_wdata[10]    ),
    .rdata_o        (sl_rdata[10]    ),
    .rvalid_o       (sl_rvalid[10]   ),
    .err_o          (sl_err  [10]    ),
    // Timer interrupt to Ibex
    .irq_timer_o    (irq_timer       ),
    .irq_external_o (irq_external    )
);

// =============================================================================
// GPIO status outputs (visible on LEDs / testpoints)
// =============================================================================
assign gpio_o[0] = payment_valid;          // payment received
assign gpio_o[1] = irq_audio_done;         // audio playback finished
assign gpio_o[2] = irq_crc_fail;           // CRC error indicator
assign gpio_o[3] = clk_en;                 // system active (not sleeping)

endmodule : bharatvoice_top
