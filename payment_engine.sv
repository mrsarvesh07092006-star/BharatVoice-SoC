// =============================================================================
// BharatVoice SoC — Payment Processing Engine
// File   : payment_engine.sv
// Author : Sarvesh (Lead Designer)
// Date   : 2026-10-16
// Rev    : 1.1 (Production RTL — Deterministic Single-Cycle Commit FSM)
//
// Description:
//   Dedicated hardware accelerator for payment transaction reception,
//   framing, CRC-16 integrity verification, bounds checking, duplicate
//   detection, and direct audio-engine announcement triggering.
//
// Bus Interface:
//   Single-beat OBI slave (0 wait-state grant, 1-cycle registered read response)
//   Mapped to 0x4000_0000 (4 KB slot)
// =============================================================================

`timescale 1ns/1ps

module payment_engine #(
    parameter logic [31:0] DEFAULT_MAX_AMOUNT = 32'd1000000 // 1,000,000 paise (Rs 10,000.00)
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // -------------------------------------------------------------------------
    // OBI Slave Bus Interface (Ibex D-Port / Interconnect)
    // -------------------------------------------------------------------------
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,

    // -------------------------------------------------------------------------
    // UART Byte Stream Input (from UART RX)
    // -------------------------------------------------------------------------
    input  logic [ 7:0] uart_data_i,
    input  logic        uart_valid_i,

    // -------------------------------------------------------------------------
    // Dedicated Outputs to Audio Engine
    // -------------------------------------------------------------------------
    output logic [31:0] amount_o,
    output logic        txn_valid_o,

    // -------------------------------------------------------------------------
    // Interrupt Outputs to Core (Ibex Fast IRQ Vector)
    // -------------------------------------------------------------------------
    output logic        irq_done_o,
    output logic        irq_fail_o
);

    // =========================================================================
    // Protocol Constants
    // =========================================================================
    localparam logic [7:0] FRAME_SOF      = 8'hAA;
    localparam logic [7:0] FRAME_VER_LEN  = 8'h18; // Version 1, 8 bytes payload
    localparam logic [7:0] FRAME_EOF      = 8'h55;

    // Error Codes
    localparam logic [7:0] ERR_NONE       = 8'h00;
    localparam logic [7:0] ERR_SOF        = 8'h01;
    localparam logic [7:0] ERR_VER_LEN    = 8'h02;
    localparam logic [7:0] ERR_CRC        = 8'h03;
    localparam logic [7:0] ERR_EOF        = 8'h04;
    localparam logic [7:0] ERR_ZERO_AMT   = 8'h05;
    localparam logic [7:0] ERR_MAX_AMT    = 8'h06;
    localparam logic [7:0] ERR_DUPLICATE  = 8'h07;

    // Register Offsets
    localparam logic [7:0] REG_TXN_CTRL       = 8'h00;
    localparam logic [7:0] REG_TXN_STATUS     = 8'h04;
    localparam logic [7:0] REG_TXN_AMOUNT     = 8'h08;
    localparam logic [7:0] REG_TXN_ID         = 8'h0C;
    localparam logic [7:0] REG_TXN_IRQ_EN     = 8'h10;
    localparam logic [7:0] REG_TXN_IRQ_STATUS = 8'h14;
    localparam logic [7:0] REG_TXN_ERR_CODE   = 8'h18;
    localparam logic [7:0] REG_TXN_MAX_AMOUNT = 8'h1C;

    // =========================================================================
    // CRC-16-CCITT Byte Calculation Function
    // Poly: 0x1021 (x^16 + x^12 + x^5 + 1), Init: 0xFFFF
    // =========================================================================
    function automatic [15:0] crc16_step(input [15:0] current_crc, input [7:0] byte_in);
        logic [15:0] c;
        c = current_crc ^ ({byte_in, 8'h00});
        for (int i = 0; i < 8; i++) begin
            if (c[15])
                c = (c << 1) ^ 16'h1021;
            else
                c = (c << 1);
        end
        return c;
    endfunction

    // =========================================================================
    // Control & Status Registers
    // =========================================================================
    logic        reg_ctrl_en;
    logic        reg_ctrl_block_dup;
    logic        reg_status_valid;
    logic        reg_status_fail;
    logic        reg_status_busy;
    logic        reg_status_dup;
    logic        reg_status_crc;
    logic [31:0] reg_amount;
    logic [31:0] reg_txn_id;
    logic [31:0] reg_last_txn_id;
    logic        has_committed;
    logic        reg_irq_en_done;
    logic        reg_irq_en_fail;
    logic        reg_irq_sts_done;
    logic        reg_irq_sts_fail;
    logic [ 7:0] reg_err_code;
    logic [31:0] reg_max_amount;

    // =========================================================================
    // FSM State Definition
    // =========================================================================
    typedef enum logic [2:0] {
        ST_IDLE      = 3'd0,
        ST_VER_LEN   = 3'd1,
        ST_TXN_ID    = 3'd2,
        ST_AMOUNT    = 3'd3,
        ST_FLAGS     = 3'd4,
        ST_CRC_HI    = 3'd5,
        ST_CRC_LO    = 3'd6,
        ST_EOF       = 3'd7
    } state_t;

    state_t state_q;

    // Parsing Shift Registers & Counters
    logic [ 1:0] byte_cnt;
    logic [31:0] rx_txn_id;
    logic [31:0] rx_amount;
    logic [ 7:0] rx_flags;
    logic [15:0] rx_crc;
    logic [15:0] crc_calc;

    // =========================================================================
    // OBI Slave Response Pipeline (Single-cycle latency)
    // =========================================================================
    logic        resp_pending_q;
    logic [31:0] resp_rdata_q;
    logic        resp_err_q;

    assign gnt_o    = req_i;            // Zero wait-state grant
    assign rvalid_o = resp_pending_q;
    assign rdata_o  = resp_rdata_q;
    assign err_o    = resp_err_q;

    // OBI Read Decode Logic
    logic [31:0] read_val;
    logic        addr_match;

    always_comb begin
        addr_match = 1'b1;
        unique case (addr_i[7:0])
            REG_TXN_CTRL: begin
                read_val = {29'b0, reg_ctrl_block_dup, 1'b0, reg_ctrl_en};
            end
            REG_TXN_STATUS: begin
                read_val = {27'b0, reg_status_crc, reg_status_dup, reg_status_busy, reg_status_fail, reg_status_valid};
            end
            REG_TXN_AMOUNT: begin
                read_val = reg_amount;
            end
            REG_TXN_ID: begin
                read_val = reg_txn_id;
            end
            REG_TXN_IRQ_EN: begin
                read_val = {30'b0, reg_irq_en_fail, reg_irq_en_done};
            end
            REG_TXN_IRQ_STATUS: begin
                read_val = {30'b0, reg_irq_sts_fail, reg_irq_sts_done};
            end
            REG_TXN_ERR_CODE: begin
                read_val = {24'b0, reg_err_code};
            end
            REG_TXN_MAX_AMOUNT: begin
                read_val = reg_max_amount;
            end
            default: begin
                read_val   = 32'hDEAD_BEEF;
                addr_match = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // Main Synchronous Logic: Registers, OBI Access & Frame Processing
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Reset control & status registers
            reg_ctrl_en         <= 1'b1;         // Enabled by default
            reg_ctrl_block_dup  <= 1'b1;         // Duplicate protection on by default
            reg_status_valid    <= 1'b0;
            reg_status_fail     <= 1'b0;
            reg_status_busy     <= 1'b0;
            reg_status_dup      <= 1'b0;
            reg_status_crc      <= 1'b0;
            reg_amount          <= 32'd0;
            reg_txn_id          <= 32'd0;
            reg_last_txn_id     <= 32'd0;
            has_committed       <= 1'b0;
            reg_irq_en_done     <= 1'b1;
            reg_irq_en_fail     <= 1'b1;
            reg_irq_sts_done    <= 1'b0;
            reg_irq_sts_fail    <= 1'b0;
            reg_err_code        <= ERR_NONE;
            reg_max_amount      <= DEFAULT_MAX_AMOUNT;

            // OBI response pipeline
            resp_pending_q      <= 1'b0;
            resp_rdata_q        <= 32'd0;
            resp_err_q          <= 1'b0;

            // FSM and packet signals
            state_q             <= ST_IDLE;
            byte_cnt            <= 2'd0;
            rx_txn_id           <= 32'd0;
            rx_amount           <= 32'd0;
            rx_flags            <= 8'd0;
            rx_crc              <= 16'd0;
            crc_calc            <= 16'hFFFF;

            // Output ports
            amount_o            <= 32'd0;
            txn_valid_o         <= 1'b0;
            irq_done_o          <= 1'b0;
            irq_fail_o          <= 1'b0;
        end else begin
            // -----------------------------------------------------------------
            // Default pulse de-assertions (one-cycle events)
            // -----------------------------------------------------------------
            txn_valid_o <= 1'b0;
            irq_done_o  <= 1'b0;
            irq_fail_o  <= 1'b0;

            // -----------------------------------------------------------------
            // OBI Bus Transactions
            // -----------------------------------------------------------------
            resp_pending_q <= req_i;
            if (req_i) begin
                resp_err_q   <= !addr_match;
                resp_rdata_q <= read_val;

                if (we_i && addr_match) begin
                    unique case (addr_i[7:0])
                        REG_TXN_CTRL: begin
                            if (be_i[0]) begin
                                reg_ctrl_en        <= wdata_i[0];
                                reg_ctrl_block_dup <= wdata_i[2];
                                // Soft reset bit (wdata_i[1])
                                if (wdata_i[1]) begin
                                    state_q          <= ST_IDLE;
                                    reg_status_busy  <= 1'b0;
                                    reg_status_valid <= 1'b0;
                                    reg_status_fail  <= 1'b0;
                                    reg_status_dup   <= 1'b0;
                                    reg_status_crc   <= 1'b0;
                                    reg_err_code     <= ERR_NONE;
                                end
                            end
                        end
                        REG_TXN_IRQ_EN: begin
                            if (be_i[0]) begin
                                reg_irq_en_done <= wdata_i[0];
                                reg_irq_en_fail <= wdata_i[1];
                            end
                        end
                        REG_TXN_IRQ_STATUS: begin
                            // RW1C: write 1 to clear
                            if (be_i[0]) begin
                                if (wdata_i[0]) reg_irq_sts_done <= 1'b0;
                                if (wdata_i[1]) reg_irq_sts_fail <= 1'b0;
                            end
                        end
                        REG_TXN_MAX_AMOUNT: begin
                            if (be_i[0]) reg_max_amount[ 7: 0] <= wdata_i[ 7: 0];
                            if (be_i[1]) reg_max_amount[15: 8] <= wdata_i[15: 8];
                            if (be_i[2]) reg_max_amount[23:16] <= wdata_i[23:16];
                            if (be_i[3]) reg_max_amount[31:24] <= wdata_i[31:24];
                        end
                        default: ;
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end

            // -----------------------------------------------------------------
            // Packet Parsing & Validation FSM
            // -----------------------------------------------------------------
            if (!reg_ctrl_en) begin
                // Processing disabled via control register
                state_q         <= ST_IDLE;
                reg_status_busy <= 1'b0;
            end else begin
                unique case (state_q)
                    // ---------------------------------------------------------
                    // ST_IDLE: Wait for Start of Frame (0xAA)
                    // ---------------------------------------------------------
                    ST_IDLE: begin
                        byte_cnt <= 2'd0;
                        if (uart_valid_i) begin
                            if (uart_data_i == FRAME_SOF) begin
                                reg_status_busy <= 1'b1;
                                state_q         <= ST_VER_LEN;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // ST_VER_LEN: Check version & length byte (0x18)
                    // ---------------------------------------------------------
                    ST_VER_LEN: begin
                        if (uart_valid_i) begin
                            if (uart_data_i == FRAME_VER_LEN) begin
                                // Seed CRC-16 with initial 0xFFFF and feed VER_LEN byte
                                crc_calc <= crc16_step(16'hFFFF, uart_data_i);
                                byte_cnt <= 2'd0;
                                state_q  <= ST_TXN_ID;
                            end else begin
                                reg_status_valid <= 1'b0;
                                reg_status_fail  <= 1'b1;
                                reg_status_busy  <= 1'b0;
                                reg_err_code     <= ERR_VER_LEN;
                                if (reg_irq_en_fail) irq_fail_o <= 1'b1;
                                reg_irq_sts_fail <= 1'b1;
                                state_q          <= ST_IDLE;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // ST_TXN_ID: Receive 4 bytes of Transaction ID (Big-Endian)
                    // ---------------------------------------------------------
                    ST_TXN_ID: begin
                        if (uart_valid_i) begin
                            rx_txn_id <= {rx_txn_id[23:0], uart_data_i};
                            crc_calc  <= crc16_step(crc_calc, uart_data_i);
                            byte_cnt  <= byte_cnt + 2'd1;
                            if (byte_cnt == 2'd3) begin
                                byte_cnt <= 2'd0;
                                state_q  <= ST_AMOUNT;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // ST_AMOUNT: Receive 4 bytes of Amount in paise (Big-Endian)
                    // ---------------------------------------------------------
                    ST_AMOUNT: begin
                        if (uart_valid_i) begin
                            rx_amount <= {rx_amount[23:0], uart_data_i};
                            crc_calc  <= crc16_step(crc_calc, uart_data_i);
                            byte_cnt  <= byte_cnt + 2'd1;
                            if (byte_cnt == 2'd3) begin
                                byte_cnt <= 2'd0;
                                state_q  <= ST_FLAGS;
                            end
                        end
                    end

                    // ---------------------------------------------------------
                    // ST_FLAGS: Receive 1 byte of Transaction Flags
                    // ---------------------------------------------------------
                    ST_FLAGS: begin
                        if (uart_valid_i) begin
                            rx_flags <= uart_data_i;
                            crc_calc <= crc16_step(crc_calc, uart_data_i);
                            state_q  <= ST_CRC_HI;
                        end
                    end

                    // ---------------------------------------------------------
                    // ST_CRC_HI: Receive upper byte of received CRC-16
                    // ---------------------------------------------------------
                    ST_CRC_HI: begin
                        if (uart_valid_i) begin
                            rx_crc[15:8] <= uart_data_i;
                            state_q      <= ST_CRC_LO;
                        end
                    end

                    // ---------------------------------------------------------
                    // ST_CRC_LO: Receive lower byte of received CRC-16
                    // ---------------------------------------------------------
                    ST_CRC_LO: begin
                        if (uart_valid_i) begin
                            rx_crc[7:0] <= uart_data_i;
                            state_q     <= ST_EOF;
                        end
                    end

                    // ---------------------------------------------------------
                    // ST_EOF: Validate Delimiter, CRC, Bounds, and Commit
                    // ---------------------------------------------------------
                    ST_EOF: begin
                        if (uart_valid_i) begin
                            if (uart_data_i != FRAME_EOF) begin
                                // Framing violation: EOF missing
                                reg_status_valid <= 1'b0;
                                reg_status_fail  <= 1'b1;
                                reg_status_busy  <= 1'b0;
                                reg_err_code     <= ERR_EOF;
                                if (reg_irq_en_fail) irq_fail_o <= 1'b1;
                                reg_irq_sts_fail <= 1'b1;
                                state_q          <= ST_IDLE;
                            end else if (rx_crc != crc_calc) begin
                                // CRC integrity check failed
                                reg_status_valid <= 1'b0;
                                reg_status_fail  <= 1'b1;
                                reg_status_crc   <= 1'b1;
                                reg_status_busy  <= 1'b0;
                                reg_err_code     <= ERR_CRC;
                                if (reg_irq_en_fail) irq_fail_o <= 1'b1;
                                reg_irq_sts_fail <= 1'b1;
                                state_q          <= ST_IDLE;
                            end else if (rx_amount == 32'd0) begin
                                // Zero-amount invalid
                                reg_status_valid <= 1'b0;
                                reg_status_fail  <= 1'b1;
                                reg_status_busy  <= 1'b0;
                                reg_err_code     <= ERR_ZERO_AMT;
                                if (reg_irq_en_fail) irq_fail_o <= 1'b1;
                                reg_irq_sts_fail <= 1'b1;
                                state_q          <= ST_IDLE;
                            end else if (rx_amount > reg_max_amount) begin
                                // Exceeds upper limit threshold
                                reg_status_valid <= 1'b0;
                                reg_status_fail  <= 1'b1;
                                reg_status_busy  <= 1'b0;
                                reg_err_code     <= ERR_MAX_AMT;
                                if (reg_irq_en_fail) irq_fail_o <= 1'b1;
                                reg_irq_sts_fail <= 1'b1;
                                state_q          <= ST_IDLE;
                            end else if (reg_ctrl_block_dup && has_committed && (rx_txn_id == reg_last_txn_id)) begin
                                // Duplicate transaction sequence ID detected
                                reg_status_valid <= 1'b0;
                                reg_status_fail  <= 1'b1;
                                reg_status_dup   <= 1'b1;
                                reg_status_busy  <= 1'b0;
                                reg_err_code     <= ERR_DUPLICATE;
                                if (reg_irq_en_fail) irq_fail_o <= 1'b1;
                                reg_irq_sts_fail <= 1'b1;
                                state_q          <= ST_IDLE;
                            end else begin
                                // All checks passed -> Single-cycle commit!
                                amount_o         <= rx_amount;
                                txn_valid_o      <= 1'b1;
                                if (reg_irq_en_done) irq_done_o <= 1'b1;
                                reg_irq_sts_done <= 1'b1;

                                reg_status_valid <= 1'b1;
                                reg_status_fail  <= 1'b0;
                                reg_status_dup   <= 1'b0;
                                reg_status_crc   <= 1'b0;
                                reg_status_busy  <= 1'b0;
                                reg_err_code     <= ERR_NONE;
                                reg_amount       <= rx_amount;
                                reg_txn_id       <= rx_txn_id;
                                reg_last_txn_id  <= rx_txn_id;
                                has_committed    <= 1'b1;

                                state_q          <= ST_IDLE;
                            end
                        end
                    end

                    default: state_q <= ST_IDLE;
                endcase
            end
        end
    end

endmodule : payment_engine
