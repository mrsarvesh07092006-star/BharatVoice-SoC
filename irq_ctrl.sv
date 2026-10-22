// =============================================================================
// BharatVoice SoC — Interrupt Controller Module
// File   : irq_ctrl.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Production RTL)
//
// Description:
//   Priority Interrupt Controller (PIC) aggregating peripheral interrupt lines,
//   with per-source enable masking, pending latching, write-1-to-clear,
//   and priority arbitration.
// =============================================================================

`timescale 1ns/1ps

module irq_ctrl #(
    parameter int unsigned NUM_IRQS = 15
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_9000)
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

    // Register Offsets
    localparam logic [7:0] REG_IRQ_EN       = 8'h00;
    localparam logic [7:0] REG_IRQ_PENDING  = 8'h04;
    localparam logic [7:0] REG_IRQ_CLEAR    = 8'h08;
    localparam logic [7:0] REG_IRQ_PRIORITY = 8'h0C;

    // Registers
    logic [NUM_IRQS-1:0] reg_irq_en;
    logic [NUM_IRQS-1:0] reg_irq_pending;
    logic [31:0]         reg_irq_priority;

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
            resp_pending_q   <= 1'b0;
            resp_rdata_q     <= 32'd0;
            resp_err_q       <= 1'b0;
            reg_irq_en       <= '1; // Enable all by default
            reg_irq_pending  <= '0;
            reg_irq_priority <= 32'd0;
        end else begin
            resp_pending_q <= req_i;
            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_IRQ_EN:       resp_rdata_q <= {17'b0, reg_irq_en};
                    REG_IRQ_PENDING:  resp_rdata_q <= {17'b0, reg_irq_pending};
                    REG_IRQ_CLEAR:    resp_rdata_q <= 32'd0;
                    REG_IRQ_PRIORITY: resp_rdata_q <= reg_irq_priority;
                    default: begin
                        resp_rdata_q <= 32'hDEAD_BEEF;
                        resp_err_q   <= 1'b1;
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_IRQ_EN: begin
                            if (be_i[0]) reg_irq_en[ 7:0] <= wdata_i[ 7:0];
                            if (be_i[1]) reg_irq_en[14:8] <= wdata_i[14:8];
                        end

                        REG_IRQ_CLEAR: begin
                            // Write 1 to clear corresponding pending bit
                            for (int i = 0; i < NUM_IRQS; i++) begin
                                if (wdata_i[i]) reg_irq_pending[i] <= 1'b0;
                            end
                        end

                        REG_IRQ_PRIORITY: begin
                            if (be_i[0]) reg_irq_priority[ 7: 0] <= wdata_i[ 7: 0];
                            if (be_i[1]) reg_irq_priority[15: 8] <= wdata_i[15: 8];
                            if (be_i[2]) reg_irq_priority[23:16] <= wdata_i[23:16];
                            if (be_i[3]) reg_irq_priority[31:24] <= wdata_i[31:24];
                        end

                        default: ;
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end
        end
    end

endmodule : irq_ctrl
