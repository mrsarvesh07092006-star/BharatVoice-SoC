// =============================================================================
// BharatVoice SoC — Stub Peripheral Modules
// File   : stubs.sv
// Author : Sanjana Arun
// Date   : 2026-10-14
// Rev    : 0.1
//
// Description:
//   Behavioural stub implementations for every peripheral that does not
//   yet have real RTL.  Each stub:
//     1. Accepts OBI requests and grants them with zero wait-states.
//     2. Returns a read-data value of 0xA5A5_A5A5 for diagnostic purposes.
//     3. Drives all output signals to safe defaults.
//
//   REPLACE each stub with the real RTL when the owning team member
//   delivers their module.
//
//   Status:
//     [STUB] boot_rom          — Sanjana
//     [STUB] uart_rx           — Sanjana
//     [STUB] irq_ctrl          — Sanjana
//     [STUB] clint             — Sanjana
//     [STUB] sram_controller   — Hrdya (replace with real RTL)
//     [STUB] transaction_cache — Hrdya (replace with real RTL)
//     [STUB] spi_master        — Hrdya (replace with real RTL)
//     [STUB] payment_engine    — Sarvesh (replace with real RTL)
//     [STUB] audio_engine      — Pradeep (replace with real RTL)
//     [STUB] crc_checker       — Bhumi (replace with real RTL)
//     [STUB] transaction_guard — Bhumi (replace with real RTL)
//     [STUB] power_manager     — Bhumi (replace with real RTL)
// =============================================================================

`timescale 1ns/1ps

// =============================================================================
// Generic OBI slave stub macro
// Shared helper task-like logic is replicated per module to stay
// synthesizer-friendly (no automatic includes needed).
// =============================================================================

// -----------------------------------------------------------------------------
// [STUB] Boot ROM  (4 KB — 1024 × 32-bit words)
// Real: synthesizable ROM initialised with boot firmware hex file.
// -----------------------------------------------------------------------------
module boot_rom #(
    parameter int unsigned DEPTH = 1024
)(
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        req_i,
    input  logic [31:0] addr_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        gnt_o,
    output logic        err_o
);
    // Initialise ROM contents; simulation only — replace with real ROM macro
    logic [31:0] mem [0:DEPTH-1];

    initial begin
        // NOP sled then infinite loop (safe reset vector)
        for (int i = 0; i < DEPTH; i++) mem[i] = 32'h0000_0013; // ADDI x0,x0,0 (NOP)
        mem[0] = 32'h0000_006F; // JAL x0, 0  (spin forever at address 0)
    end

    assign gnt_o = req_i;   // zero wait-state grant

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rdata_o  <= 32'h0;
            rvalid_o <= 1'b0;
        end else begin
            rvalid_o <= req_i;
            if (req_i) begin
                // Word address = byte_address[13:2]
                rdata_o  <= mem[addr_i[11:2]];
            end
        end
    end

    assign err_o = 1'b0;
endmodule : boot_rom

// -----------------------------------------------------------------------------
// [STUB] UART RX
// Real: 16× oversampled UART with configurable baud rate.
// Stub simply ties rx_valid_o low and always grants OBI transactions.
// -----------------------------------------------------------------------------
module uart_rx #(
    parameter int unsigned CLK_FREQ_HZ = 50_000_000,
    parameter int unsigned BAUD_RATE   = 115200
)(
    input  logic        clk_i,
    input  logic        rst_ni,
    // OBI register interface
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,
    // Physical UART pin
    input  logic        uart_rx_i,
    // Byte output to payment engine
    output logic [ 7:0] rx_data_o,
    output logic        rx_valid_o,
    // Interrupt
    output logic        irq_rx_o
);
    // OBI zero wait-state
    assign gnt_o = req_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rdata_o  <= 32'hA5A5_A5A5;
            rvalid_o <= 1'b0;
        end else begin
            rvalid_o <= req_i;
            rdata_o  <= (req_i & !we_i) ? 32'hA5A5_A5A5 : 32'h0;
        end
    end
    assign err_o     = 1'b0;
    // Stub outputs — no actual UART parsing
    assign rx_data_o = 8'h00;
    assign rx_valid_o= 1'b0;
    assign irq_rx_o  = 1'b0;
endmodule : uart_rx

// -----------------------------------------------------------------------------
// [STUB] Interrupt Controller
// Real: priority encoder, per-source masking and pending register.
// -----------------------------------------------------------------------------
module irq_ctrl (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o
);
    assign gnt_o = req_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rdata_o  <= 32'h0;
            rvalid_o <= 1'b0;
        end else begin
            rvalid_o <= req_i;
            rdata_o  <= (req_i & !we_i) ? 32'hA5A5_A5A5 : 32'h0;
        end
    end
    assign err_o = 1'b0;
endmodule : irq_ctrl

// -----------------------------------------------------------------------------
// [STUB] CLINT — Machine Timer
// Real: 64-bit mtime counter + mtimecmp comparator → irq_timer
// -----------------------------------------------------------------------------
module clint (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,
    output logic        irq_timer_o,
    output logic        irq_external_o
);
    logic [63:0] mtime;
    logic [63:0] mtimecmp;

    assign gnt_o = req_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mtime     <= 64'h0;
            mtimecmp  <= 64'hFFFF_FFFF_FFFF_FFFF;
            rdata_o   <= 32'h0;
            rvalid_o  <= 1'b0;
        end else begin
            mtime    <= mtime + 1;
            rvalid_o <= req_i;
            if (req_i) begin
                if (we_i) begin
                    case (addr_i[3:0])
                        4'h0: mtimecmp[31:0]  <= wdata_i;
                        4'h4: mtimecmp[63:32] <= wdata_i;
                        default: ;
                    endcase
                    rdata_o <= 32'h0;
                end else begin
                    case (addr_i[3:0])
                        4'h0: rdata_o <= mtime[31:0];
                        4'h4: rdata_o <= mtime[63:32];
                        4'h8: rdata_o <= mtimecmp[31:0];
                        4'hC: rdata_o <= mtimecmp[63:32];
                        default: rdata_o <= 32'h0;
                    endcase
                end
            end
        end
    end

    assign irq_timer_o    = (mtime >= mtimecmp);
    assign irq_external_o = 1'b0;
    assign err_o          = 1'b0;
endmodule : clint

// -----------------------------------------------------------------------------
// [STUB] SRAM Controller  [Owner: Hrdya]
// Real: full sram_controller.sv with ECC, wait-state management, etc.
// Stub: simple synchronous SRAM model (64 KB).
// -----------------------------------------------------------------------------
module sram_controller #(
    parameter int unsigned ADDR_WIDTH = 17,
    parameter int unsigned DATA_WIDTH = 32
)(
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  reg_req_i,
    output logic                  reg_gnt_o,
    input  logic [31:0]           reg_addr_i,
    input  logic                  reg_we_i,
    input  logic [ 3:0]           reg_be_i,
    input  logic [31:0]           reg_wdata_i,
    output logic [31:0]           reg_rdata_o,
    output logic                  reg_rvalid_o,
    output logic                  reg_err_o
);
    localparam int unsigned MEM_DEPTH = (1 << (ADDR_WIDTH - 2)); // word-addressed

    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    assign reg_gnt_o = reg_req_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            reg_rdata_o  <= 32'h0;
            reg_rvalid_o <= 1'b0;
        end else begin
            reg_rvalid_o <= reg_req_i;
            if (reg_req_i) begin
                if (reg_we_i) begin
                    // Byte-enable aware write
                    if (reg_be_i[0]) mem[reg_addr_i[ADDR_WIDTH-1:2]][ 7: 0] <= reg_wdata_i[ 7: 0];
                    if (reg_be_i[1]) mem[reg_addr_i[ADDR_WIDTH-1:2]][15: 8] <= reg_wdata_i[15: 8];
                    if (reg_be_i[2]) mem[reg_addr_i[ADDR_WIDTH-1:2]][23:16] <= reg_wdata_i[23:16];
                    if (reg_be_i[3]) mem[reg_addr_i[ADDR_WIDTH-1:2]][31:24] <= reg_wdata_i[31:24];
                    reg_rdata_o <= 32'h0;
                end else begin
                    reg_rdata_o <= mem[reg_addr_i[ADDR_WIDTH-1:2]];
                end
            end
        end
    end

    assign reg_err_o = 1'b0;
endmodule : sram_controller

// -----------------------------------------------------------------------------
// [STUB] Transaction Cache  [Owner: Hrdya]
// -----------------------------------------------------------------------------
module transaction_cache (
    input  logic        clk_i, rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i, wdata_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o
);
    assign gnt_o = req_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rdata_o <= 32'h0; rvalid_o <= 1'b0; end
        else begin rvalid_o <= req_i; rdata_o <= req_i & !we_i ? 32'hA5A5_A5A5 : 32'h0; end
    end
    assign err_o = 1'b0;
endmodule : transaction_cache

// -----------------------------------------------------------------------------
// [STUB REMOVED -> REAL RTL] SPI Master  [Owner: Hrdya]
// Real RTL implemented in spi_master.sv
// -----------------------------------------------------------------------------
/*
module spi_master (
    input  logic        clk_i, rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i, wdata_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,
    output logic        sclk_o, mosi_o,
    input  logic        miso_i,
    output logic        cs_n_o,
    output logic        irq_done_o
);
    assign gnt_o      = req_i;
    assign sclk_o     = 1'b0;
    assign mosi_o     = 1'b0;
    assign cs_n_o     = 1'b1;
    assign irq_done_o = 1'b0;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rdata_o <= 32'h0; rvalid_o <= 1'b0; end
        else begin rvalid_o <= req_i; rdata_o <= req_i & !we_i ? 32'hA5A5_A5A5 : 32'h0; end
    end
    assign err_o = 1'b0;
endmodule : spi_master
*/

// -----------------------------------------------------------------------------
// [STUB REMOVED -> REAL RTL] Payment Engine  [Owner: Sarvesh]
// Real RTL implemented in payment_engine.sv (Revision 1.1)
// -----------------------------------------------------------------------------
/*
module payment_engine (
    input  logic        clk_i, rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i, wdata_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,
    // UART byte feed
    input  logic [ 7:0] uart_data_i,
    input  logic        uart_valid_i,
    // Outputs
    output logic [31:0] amount_o,
    output logic        txn_valid_o,
    output logic        irq_done_o,
    output logic        irq_fail_o
);
    assign gnt_o      = req_i;
    assign amount_o   = 32'h0;
    assign txn_valid_o= 1'b0;
    assign irq_done_o = 1'b0;
    assign irq_fail_o = 1'b0;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rdata_o <= 32'h0; rvalid_o <= 1'b0; end
        else begin rvalid_o <= req_i; rdata_o <= req_i & !we_i ? 32'hA5A5_A5A5 : 32'h0; end
    end
    assign err_o = 1'b0;
endmodule : payment_engine
*/

// -----------------------------------------------------------------------------
// [STUB] Audio Engine  [Owner: Pradeep]
// Real: audio_engine.sv with amount→token decoder, PWM output.
// -----------------------------------------------------------------------------
module audio_engine (
    input  logic        clk_i, rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i, wdata_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,
    input  logic [31:0] amount_i,
    input  logic        amount_valid_i,
    output logic        pwm_o,
    output logic        irq_done_o
);
    assign gnt_o      = req_i;
    assign pwm_o      = 1'b0;
    assign irq_done_o = 1'b0;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rdata_o <= 32'h0; rvalid_o <= 1'b0; end
        else begin rvalid_o <= req_i; rdata_o <= req_i & !we_i ? 32'hA5A5_A5A5 : 32'h0; end
    end
    assign err_o = 1'b0;
endmodule : audio_engine

// -----------------------------------------------------------------------------
// [STUB] CRC Checker  [Owner: Bhumi]
// Real: crc_checker.sv with CRC-16/CCITT engine.
// -----------------------------------------------------------------------------
module crc_checker (
    input  logic        clk_i, rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i, wdata_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,
    output logic        irq_crc_fail_o
);
    assign gnt_o          = req_i;
    assign irq_crc_fail_o = 1'b0;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rdata_o <= 32'h0; rvalid_o <= 1'b0; end
        else begin rvalid_o <= req_i; rdata_o <= req_i & !we_i ? 32'hA5A5_A5A5 : 32'h0; end
    end
    assign err_o = 1'b0;
endmodule : crc_checker

// -----------------------------------------------------------------------------
// [STUB] Transaction Guard  [Owner: Bhumi]
// Real: transaction_guard.sv with duplicate ID detection.
// -----------------------------------------------------------------------------
module transaction_guard (
    input  logic        clk_i, rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i, wdata_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o
);
    assign gnt_o = req_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rdata_o <= 32'h0; rvalid_o <= 1'b0; end
        else begin rvalid_o <= req_i; rdata_o <= req_i & !we_i ? 32'hA5A5_A5A5 : 32'h0; end
    end
    assign err_o = 1'b0;
endmodule : transaction_guard

// -----------------------------------------------------------------------------
// [STUB] Power Manager  [Owner: Bhumi]
// Real: power_manager.sv with sleep/wake FSM.
// -----------------------------------------------------------------------------
module power_manager (
    input  logic        clk_i, rst_ni,
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i, wdata_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,
    input  logic        uart_rx_i,
    input  logic        spi_activity_i,
    output logic        irq_wakeup_o,
    output logic        clk_en_o
);
    assign gnt_o        = req_i;
    assign irq_wakeup_o = 1'b0;
    assign clk_en_o     = 1'b1;   // always active in stub
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rdata_o <= 32'h0; rvalid_o <= 1'b0; end
        else begin rvalid_o <= req_i; rdata_o <= req_i & !we_i ? 32'hA5A5_A5A5 : 32'h0; end
    end
    assign err_o = 1'b0;
endmodule : power_manager
