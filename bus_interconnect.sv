// =============================================================================
// BharatVoice SoC — OBI Bus Interconnect
// File   : bus_interconnect.sv
// Author : Sanjana Arun
// Date   : 2026-10-14
// Rev    : 0.1
//
// Description:
//   Single-master, N-slave OBI bus interconnect for the BharatVoice SoC.
//   Decodes the 32-bit address from the Ibex D-port and routes each
//   transaction to the correct peripheral slave.  All peripheral slaves
//   must respond with zero wait-states (gnt asserted in the same cycle
//   as req, rvalid asserted the following cycle).
//
// Address decode:
//   Boot ROM    0x0000_0000 – 0x0000_0FFF  (4 KB,  bits[31:28]=4'h0)
//   Data SRAM   0x2000_0000 – 0x2000_FFFF  (64 KB, bits[31:28]=4'h2)
//   Peripherals 0x4000_0000 – 0x4FFF_FFFF  (bits[31:28]=4'h4)
//     Payment Eng  [15:12]=4'h0
//     Audio Eng    [15:12]=4'h1
//     SRAM Ctrl    [15:12]=4'h2
//     TXN Cache    [15:12]=4'h3
//     SPI Master   [15:12]=4'h4
//     CRC Checker  [15:12]=4'h5
//     TXN Guard    [15:12]=4'h6
//     Power Mgr    [15:12]=4'h7
//     UART RX      [15:12]=4'h8
//     IRQ Ctrl     [15:12]=4'h9
//     CLINT        [15:12]=4'hA
// =============================================================================

`timescale 1ns/1ps

module bus_interconnect #(
    parameter int unsigned N_SLAVES = 11
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // -------------------------------------------------------------------------
    // Master port (Ibex D-port)
    // -------------------------------------------------------------------------
    input  logic        m_req_i,
    output logic        m_gnt_o,
    input  logic [31:0] m_addr_i,
    input  logic        m_we_i,
    input  logic [ 3:0] m_be_i,
    input  logic [31:0] m_wdata_i,
    output logic [31:0] m_rdata_o,
    output logic        m_rvalid_o,
    output logic        m_err_o,

    // -------------------------------------------------------------------------
    // Slave ports (flattened arrays — one entry per peripheral)
    // -------------------------------------------------------------------------
    output logic [N_SLAVES-1:0] s_req_o,
    input  logic [N_SLAVES-1:0] s_gnt_i,
    output logic [31:0]         s_addr_o  [N_SLAVES-1:0],
    output logic [N_SLAVES-1:0] s_we_o,
    output logic [ 3:0]         s_be_o    [N_SLAVES-1:0],
    output logic [31:0]         s_wdata_o [N_SLAVES-1:0],
    input  logic [31:0]         s_rdata_i [N_SLAVES-1:0],
    input  logic [N_SLAVES-1:0] s_rvalid_i,
    input  logic [N_SLAVES-1:0] s_err_i
);

// =============================================================================
// Slave index definitions (must match peripheral order in bharatvoice_top)
// =============================================================================
localparam int unsigned IDX_PAYMENT  = 0;
localparam int unsigned IDX_AUDIO    = 1;
localparam int unsigned IDX_SRAM_CTL = 2;
localparam int unsigned IDX_TXN_CACHE= 3;
localparam int unsigned IDX_SPI      = 4;
localparam int unsigned IDX_CRC      = 5;
localparam int unsigned IDX_GUARD    = 6;
localparam int unsigned IDX_PWR      = 7;
localparam int unsigned IDX_UART     = 8;
localparam int unsigned IDX_IRQ      = 9;
localparam int unsigned IDX_CLINT    = 10;

// =============================================================================
// Address decode — combinational
// =============================================================================
// sel_slave: one-hot, selects which slave receives the current transaction
logic [N_SLAVES-1:0] sel_slave;
logic                decode_error;   // asserted when no slave matches

always_comb begin
    sel_slave    = '0;
    decode_error = 1'b0;

    if (m_req_i) begin
        unique casez (m_addr_i[31:28])
            // ── Peripheral region ──────────────────────────────────────────
            4'h4: begin
                unique casez (m_addr_i[15:12])
                    4'h0:    sel_slave[IDX_PAYMENT  ] = 1'b1;
                    4'h1:    sel_slave[IDX_AUDIO    ] = 1'b1;
                    4'h2:    sel_slave[IDX_SRAM_CTL ] = 1'b1;
                    4'h3:    sel_slave[IDX_TXN_CACHE] = 1'b1;
                    4'h4:    sel_slave[IDX_SPI      ] = 1'b1;
                    4'h5:    sel_slave[IDX_CRC      ] = 1'b1;
                    4'h6:    sel_slave[IDX_GUARD    ] = 1'b1;
                    4'h7:    sel_slave[IDX_PWR      ] = 1'b1;
                    4'h8:    sel_slave[IDX_UART     ] = 1'b1;
                    4'h9:    sel_slave[IDX_IRQ      ] = 1'b1;
                    4'hA:    sel_slave[IDX_CLINT    ] = 1'b1;
                    default: decode_error              = 1'b1;
                endcase
            end
            // ── SRAM direct-data region (0x2xxx_xxxx) — re-route to SRAM ctrl
            4'h2: sel_slave[IDX_SRAM_CTL] = 1'b1;
            // ── Unrecognised ────────────────────────────────────────────────
            default: decode_error = 1'b1;
        endcase
    end
end

// =============================================================================
// Drive slave request lines
// Each slave receives the request only when selected
// =============================================================================
generate
    for (genvar s = 0; s < N_SLAVES; s++) begin : gen_slave_req
        assign s_req_o  [s] = m_req_i & sel_slave[s];
        assign s_addr_o [s] = m_addr_i;
        assign s_we_o   [s] = m_we_i;
        assign s_be_o   [s] = m_be_i;
        assign s_wdata_o[s] = m_wdata_i;
    end
endgenerate

// =============================================================================
// Grant: forward the selected slave's grant back to the master
// =============================================================================
always_comb begin
    m_gnt_o = decode_error;            // error path grants immediately
    for (int s = 0; s < N_SLAVES; s++) begin
        if (sel_slave[s]) m_gnt_o = s_gnt_i[s];
    end
end

// =============================================================================
// Read-data / rvalid / error mux
// Because we grant in the same cycle, rvalid arrives 1 cycle later.
// We register which slave was selected so we can mux rdata correctly.
// =============================================================================
logic [N_SLAVES-1:0] sel_slave_q;    // registered sel for response cycle
logic                decode_err_q;   // registered decode error

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        sel_slave_q  <= '0;
        decode_err_q <= 1'b0;
    end else if (m_req_i & m_gnt_o) begin
        sel_slave_q  <= sel_slave;
        decode_err_q <= decode_error;
    end else if (m_rvalid_o) begin
        sel_slave_q  <= '0;
        decode_err_q <= 1'b0;
    end
end

// Mux rdata from selected slave
always_comb begin
    m_rdata_o  = 32'hDEAD_BEEF;   // default (decode error return)
    m_rvalid_o = decode_err_q;    // error path completes immediately
    m_err_o    = decode_err_q;

    for (int s = 0; s < N_SLAVES; s++) begin
        if (sel_slave_q[s]) begin
            m_rdata_o  = s_rdata_i [s];
            m_rvalid_o = s_rvalid_i[s];
            m_err_o    = s_err_i   [s];
        end
    end
end

// =============================================================================
// Assertions (simulation only)
// =============================================================================
`ifdef SIMULATION
// No two slaves should be selected simultaneously
always_comb begin
    assert ($onehot0(sel_slave))
        else $error("[bus_interconnect] More than one slave selected! addr=%08h", m_addr_i);
end
`endif

endmodule : bus_interconnect
