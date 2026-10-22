// =============================================================================
// BharatVoice SoC — Transaction Guard Security Module
// File   : transaction_guard.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Production RTL)
//
// Description:
//   Security supervisor for transaction monitoring, replay attack prevention,
//   duplicate transaction detection, and security violation counter.
// =============================================================================

`timescale 1ns/1ps

module transaction_guard (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_6000)
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
    localparam logic [7:0] REG_GUARD_CTRL     = 8'h00;
    localparam logic [7:0] REG_GUARD_STATUS   = 8'h04;
    localparam logic [7:0] REG_GUARD_TXN_ID   = 8'h08;
    localparam logic [7:0] REG_GUARD_FAIL_CNT = 8'h0C;
    localparam logic [7:0] REG_GUARD_IRQ_EN   = 8'h10;
    localparam logic [7:0] REG_GUARD_IRQ_STS  = 8'h14;

    // Registers
    logic        reg_en;
    logic        reg_block_dup;
    logic        reg_status_ok;
    logic        reg_status_crc_fail;
    logic        reg_status_duplicate;
    logic [31:0] reg_last_txn_id;
    logic [15:0] reg_fail_cnt;
    logic [ 1:0] reg_irq_en;
    logic [ 1:0] reg_irq_sts;

    // 8-entry circular history buffer for recent transaction IDs
    logic [31:0] id_history [0:7];
    logic [ 2:0] hist_ptr;
    logic [ 3:0] hist_count;

    // Duplicate check logic
    function automatic logic is_duplicate(input logic [31:0] id_to_check);
        for (int i = 0; i < 8; i++) begin
            if (i < hist_count && id_history[i] == id_to_check) return 1'b1;
        end
        return 1'b0;
    endfunction

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
            resp_pending_q       <= 1'b0;
            resp_rdata_q         <= 32'd0;
            resp_err_q           <= 1'b0;
            reg_en               <= 1'b1;
            reg_block_dup        <= 1'b1;
            reg_status_ok        <= 1'b1;
            reg_status_crc_fail  <= 1'b0;
            reg_status_duplicate <= 1'b0;
            reg_last_txn_id      <= 32'd0;
            reg_fail_cnt         <= 16'd0;
            reg_irq_en           <= 2'b11;
            reg_irq_sts          <= 2'b00;
            hist_ptr             <= 3'd0;
            hist_count           <= 4'd0;
            for (int i = 0; i < 8; i++) id_history[i] <= 32'd0;
        end else begin
            resp_pending_q <= req_i;
            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_GUARD_CTRL:     resp_rdata_q <= {30'b0, reg_block_dup, reg_en};
                    REG_GUARD_STATUS:   resp_rdata_q <= {29'b0, reg_status_duplicate, reg_status_crc_fail, reg_status_ok};
                    REG_GUARD_TXN_ID:   resp_rdata_q <= reg_last_txn_id;
                    REG_GUARD_FAIL_CNT: resp_rdata_q <= {16'b0, reg_fail_cnt};
                    REG_GUARD_IRQ_EN:   resp_rdata_q <= {30'b0, reg_irq_en};
                    REG_GUARD_IRQ_STS:  resp_rdata_q <= {30'b0, reg_irq_sts};
                    default: begin
                        resp_rdata_q <= 32'hDEAD_BEEF;
                        resp_err_q   <= 1'b1;
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_GUARD_CTRL: begin
                            if (be_i[0]) begin
                                reg_en        <= wdata_i[0];
                                reg_block_dup <= wdata_i[1];
                            end
                        end

                        REG_GUARD_TXN_ID: begin
                            if (reg_en) begin
                                reg_last_txn_id <= wdata_i;
                                if (reg_block_dup && is_duplicate(wdata_i)) begin
                                    reg_status_duplicate <= 1'b1;
                                    reg_status_ok        <= 1'b0;
                                    reg_fail_cnt         <= reg_fail_cnt + 16'd1;
                                    if (reg_irq_en[1]) reg_irq_sts[1] <= 1'b1;
                                end else begin
                                    reg_status_duplicate    <= 1'b0;
                                    reg_status_ok           <= 1'b1;
                                    id_history[hist_ptr]    <= wdata_i;
                                    hist_ptr                <= hist_ptr + 3'd1;
                                    if (hist_count < 4'd8) hist_count <= hist_count + 4'd1;
                                end
                            end
                        end

                        REG_GUARD_FAIL_CNT: begin
                            // Write clears fail count
                            reg_fail_cnt <= 16'd0;
                        end

                        REG_GUARD_IRQ_EN: begin
                            if (be_i[0]) reg_irq_en <= wdata_i[1:0];
                        end

                        REG_GUARD_IRQ_STS: begin
                            // RW1C
                            if (be_i[0]) begin
                                if (wdata_i[0]) reg_irq_sts[0] <= 1'b0;
                                if (wdata_i[1]) reg_irq_sts[1] <= 1'b0;
                            end
                        end

                        default: ;
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end
        end
    end

endmodule : transaction_guard
