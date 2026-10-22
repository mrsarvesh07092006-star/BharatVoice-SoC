// =============================================================================
// BharatVoice SoC — Core Local Interruptor (CLINT) Module
// File   : clint.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Production RTL)
//
// Description:
//   Standard RISC-V CLINT timer module providing 64-bit mtime counter,
//   64-bit mtimecmp comparator, and level-triggered machine timer interrupt.
// =============================================================================

`timescale 1ns/1ps

module clint (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_A000)
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,

    // Interrupt lines to Ibex core
    output logic        irq_timer_o,
    output logic        irq_external_o
);

    // Register Offsets
    localparam logic [7:0] REG_MTIME_LO    = 8'h00;
    localparam logic [7:0] REG_MTIME_HI    = 8'h04;
    localparam logic [7:0] REG_MTIMECMP_LO = 8'h08;
    localparam logic [7:0] REG_MTIMECMP_HI = 8'h0C;

    // 64-bit timer and compare registers
    logic [63:0] mtime;
    logic [63:0] mtimecmp;

    // Timer Interrupt generation
    assign irq_timer_o    = (mtime >= mtimecmp);
    assign irq_external_o = 1'b0;

    // =========================================================================
    // OBI Slave Register Interface (Single-cycle latency)
    // =========================================================================
    logic        resp_pending_q;
    logic [31:0] resp_rdata_q;
    logic        resp_err_q;

    assign gnt_o    = req_i;
    assign rvalid_o = resp_pending_q;
    assign rdata_o  = resp_rdata_q;
    assign err_o    = resp_err_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            resp_pending_q <= 1'b0;
            resp_rdata_q   <= 32'd0;
            resp_err_q     <= 1'b0;
            mtime          <= 64'd0;
            mtimecmp       <= 64'hFFFF_FFFF_FFFF_FFFF; // Max value on reset
        end else begin
            mtime          <= mtime + 64'd1;
            resp_pending_q <= req_i;

            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_MTIME_LO:    resp_rdata_q <= mtime[31:0];
                    REG_MTIME_HI:    resp_rdata_q <= mtime[63:32];
                    REG_MTIMECMP_LO: resp_rdata_q <= mtimecmp[31:0];
                    REG_MTIMECMP_HI: resp_rdata_q <= mtimecmp[63:32];
                    default: begin
                        resp_rdata_q <= 32'hDEAD_BEEF;
                        resp_err_q   <= 1'b1;
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_MTIME_LO: begin
                            if (be_i[0]) mtime[ 7: 0] <= wdata_i[ 7: 0];
                            if (be_i[1]) mtime[15: 8] <= wdata_i[15: 8];
                            if (be_i[2]) mtime[23:16] <= wdata_i[23:16];
                            if (be_i[3]) mtime[31:24] <= wdata_i[31:24];
                        end
                        REG_MTIME_HI: begin
                            if (be_i[0]) mtime[39:32] <= wdata_i[ 7: 0];
                            if (be_i[1]) mtime[47:40] <= wdata_i[15: 8];
                            if (be_i[2]) mtime[55:48] <= wdata_i[23:16];
                            if (be_i[3]) mtime[63:56] <= wdata_i[31:24];
                        end
                        REG_MTIMECMP_LO: begin
                            if (be_i[0]) mtimecmp[ 7: 0] <= wdata_i[ 7: 0];
                            if (be_i[1]) mtimecmp[15: 8] <= wdata_i[15: 8];
                            if (be_i[2]) mtimecmp[23:16] <= wdata_i[23:16];
                            if (be_i[3]) mtimecmp[31:24] <= wdata_i[31:24];
                        end
                        REG_MTIMECMP_HI: begin
                            if (be_i[0]) mtimecmp[39:32] <= wdata_i[ 7: 0];
                            if (be_i[1]) mtimecmp[47:40] <= wdata_i[15: 8];
                            if (be_i[2]) mtimecmp[55:48] <= wdata_i[23:16];
                            if (be_i[3]) mtimecmp[63:56] <= wdata_i[31:24];
                        end
                        default: ;
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end
        end
    end

endmodule : clint
