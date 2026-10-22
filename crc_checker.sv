// =============================================================================
// BharatVoice SoC — CRC Checker Hardware Accelerator
// File   : crc_checker.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Production RTL)
//
// Description:
//   Configurable hardware CRC engine supporting byte/word-serial computation,
//   programmable polynomial (defaults to CRC-16-CCITT 0x1021), hardware comparison
//   against expected CRC, and IRQ generation on integrity failure.
// =============================================================================

`timescale 1ns/1ps

module crc_checker (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_5000)
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,

    // Interrupt output on integrity failure
    output logic        irq_crc_fail_o
);

    // Register Offsets
    localparam logic [7:0] REG_CRC_CTRL     = 8'h00;
    localparam logic [7:0] REG_CRC_STATUS   = 8'h04;
    localparam logic [7:0] REG_CRC_INPUT    = 8'h08;
    localparam logic [7:0] REG_CRC_RESULT   = 8'h0C;
    localparam logic [7:0] REG_CRC_EXPECTED = 8'h10;
    localparam logic [7:0] REG_CRC_POLY     = 8'h14;

    // Registers
    logic        reg_en;
    logic        reg_status_done;
    logic        reg_status_fail;
    logic        reg_status_busy;
    logic [15:0] reg_crc_result;
    logic [15:0] reg_crc_expected;
    logic [15:0] reg_crc_poly;

    // CRC Step Function
    function automatic [15:0] calc_crc16_byte(
        input [15:0] curr_crc,
        input [ 7:0] byte_in,
        input [15:0] poly
    );
        logic [15:0] c;
        c = curr_crc ^ ({byte_in, 8'h00});
        for (int i = 0; i < 8; i++) begin
            if (c[15])
                c = (c << 1) ^ poly;
            else
                c = (c << 1);
        end
        return c;
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
            resp_pending_q   <= 1'b0;
            resp_rdata_q     <= 32'd0;
            resp_err_q       <= 1'b0;
            reg_en           <= 1'b1;
            reg_status_done  <= 1'b0;
            reg_status_fail  <= 1'b0;
            reg_status_busy  <= 1'b0;
            reg_crc_result   <= 16'hFFFF;
            reg_crc_expected <= 16'h0000;
            reg_crc_poly     <= 16'h1021; // CRC-16-CCITT default
            irq_crc_fail_o   <= 1'b0;
        end else begin
            irq_crc_fail_o <= 1'b0; // default pulse
            resp_pending_q <= req_i;

            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_CRC_CTRL:     resp_rdata_q <= {31'b0, reg_en};
                    REG_CRC_STATUS:   resp_rdata_q <= {29'b0, reg_status_busy, reg_status_fail, reg_status_done};
                    REG_CRC_INPUT:    resp_rdata_q <= 32'd0;
                    REG_CRC_RESULT:   resp_rdata_q <= {16'b0, reg_crc_result};
                    REG_CRC_EXPECTED: resp_rdata_q <= {16'b0, reg_crc_expected};
                    REG_CRC_POLY:     resp_rdata_q <= {16'b0, reg_crc_poly};
                    default: begin
                        resp_rdata_q <= 32'hDEAD_BEEF;
                        resp_err_q   <= 1'b1;
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_CRC_CTRL: begin
                            if (be_i[0]) begin
                                reg_en <= wdata_i[0];
                                if (wdata_i[1]) begin // reset CRC
                                    reg_crc_result  <= 16'hFFFF;
                                    reg_status_done <= 1'b0;
                                    reg_status_fail <= 1'b0;
                                end
                            end
                        end

                        REG_CRC_INPUT: begin
                            // Feed up to 4 bytes into CRC engine
                            if (reg_en) begin
                                logic [15:0] intermediate_crc;
                                intermediate_crc = reg_crc_result;
                                if (be_i[0]) intermediate_crc = calc_crc16_byte(intermediate_crc, wdata_i[ 7: 0], reg_crc_poly);
                                if (be_i[1]) intermediate_crc = calc_crc16_byte(intermediate_crc, wdata_i[15: 8], reg_crc_poly);
                                if (be_i[2]) intermediate_crc = calc_crc16_byte(intermediate_crc, wdata_i[23:16], reg_crc_poly);
                                if (be_i[3]) intermediate_crc = calc_crc16_byte(intermediate_crc, wdata_i[31:24], reg_crc_poly);
                                reg_crc_result <= intermediate_crc;
                            end
                        end

                        REG_CRC_EXPECTED: begin
                            if (be_i[0]) reg_crc_expected[ 7:0] <= wdata_i[ 7:0];
                            if (be_i[1]) reg_crc_expected[15:8] <= wdata_i[15:8];

                            // Check integrity against expected
                            if (reg_crc_result != {wdata_i[15:8], wdata_i[7:0]}) begin
                                reg_status_fail <= 1'b1;
                                reg_status_done <= 1'b0;
                                irq_crc_fail_o  <= 1'b1;
                            end else begin
                                reg_status_fail <= 1'b0;
                                reg_status_done <= 1'b1;
                            end
                        end

                        REG_CRC_POLY: begin
                            if (be_i[0]) reg_crc_poly[ 7:0] <= wdata_i[ 7:0];
                            if (be_i[1]) reg_crc_poly[15:8] <= wdata_i[15:8];
                        end

                        default: ;
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end
        end
    end

endmodule : crc_checker
