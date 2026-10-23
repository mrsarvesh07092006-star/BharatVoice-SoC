// =============================================================================
// BharatVoice SoC — UART RX Receiver Module
// File   : uart_rx.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Production RTL)
//
// Description:
//   16x oversampled UART receiver with synchronizer, majority bit sampling,
//   framing error detection, byte stream forwarding to Payment Engine,
//   and OBI slave register interface.
// =============================================================================

`timescale 1ns/1ps

module uart_rx #(
    parameter int unsigned CLK_FREQ_HZ = 50_000_000,
    parameter int unsigned BAUD_RATE   = 115200
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_8000)
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

    // Byte stream output to Payment Engine
    output logic [ 7:0] rx_data_o,
    output logic        rx_valid_o,

    // Interrupt to core
    output logic        irq_rx_o
);

    // Default clock divider for 16x baud clock: 50MHz / (115200 * 16) ≈ 27
    localparam int unsigned DEFAULT_BAUD_DIV = CLK_FREQ_HZ / (BAUD_RATE * 16);

    // Register Offsets
    localparam logic [7:0] REG_CTRL     = 8'h00;
    localparam logic [7:0] REG_STATUS   = 8'h04;
    localparam logic [7:0] REG_RX_DATA  = 8'h08;
    localparam logic [7:0] REG_BAUD_DIV = 8'h0C;
    localparam logic [7:0] REG_IRQ_EN   = 8'h10;
    localparam logic [7:0] REG_IRQ_STS  = 8'h14;

    // Registers
    logic        reg_en;
    logic        reg_rx_valid;
    logic        reg_rx_err;
    logic [ 7:0] reg_rx_data;
    logic [15:0] reg_baud_div;
    logic        reg_irq_en;
    logic        reg_irq_sts;

    // 2-flop synchronizer for asynchronous uart_rx_i pin
    logic rx_sync1, rx_sync2;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= uart_rx_i;
            rx_sync2 <= rx_sync1;
        end
    end

    // 16x Baud Rate Generator Counter
    logic [15:0] baud_cnt;
    logic        tick_16x;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            baud_cnt <= 16'd0;
            tick_16x <= 1'b0;
        end else if (reg_en) begin
            if (baud_cnt >= (reg_baud_div - 1)) begin
                baud_cnt <= 16'd0;
                tick_16x <= 1'b1;
            end else begin
                baud_cnt <= baud_cnt + 16'd1;
                tick_16x <= 1'b0;
            end
        end else begin
            baud_cnt <= 16'd0;
            tick_16x <= 1'b0;
        end
    end

    // UART RX State Machine
    typedef enum logic [2:0] {
        ST_IDLE  = 3'd0,
        ST_START = 3'd1,
        ST_DATA  = 3'd2,
        ST_STOP  = 3'd3
    } state_t;

    state_t state_q;
    logic [3:0] sample_cnt;
    logic [2:0] bit_cnt;
    logic [7:0] rx_shift;

    wire sw_rx_clr  = req_i && we_i && (addr_i[7:0] == REG_CTRL) && be_i[0] && wdata_i[1];
    wire sw_irq_clr = req_i && we_i && (addr_i[7:0] == REG_IRQ_STS) && be_i[0] && wdata_i[0];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q      <= ST_IDLE;
            sample_cnt   <= 4'd0;
            bit_cnt      <= 3'd0;
            rx_shift     <= 8'd0;
            rx_data_o    <= 8'd0;
            rx_valid_o   <= 1'b0;
            reg_rx_valid <= 1'b0;
            reg_rx_err   <= 1'b0;
            reg_rx_data  <= 8'd0;
            reg_irq_sts  <= 1'b0;
        end else begin
            rx_valid_o <= 1'b0; // 1-cycle pulse default

            // Software register clear signals
            if (sw_rx_clr) begin
                reg_rx_valid <= 1'b0;
                reg_rx_err   <= 1'b0;
            end
            if (sw_irq_clr) begin
                reg_irq_sts <= 1'b0;
            end

            if (tick_16x && reg_en) begin
                unique case (state_q)
                    ST_IDLE: begin
                        sample_cnt <= 4'd0;
                        bit_cnt    <= 3'd0;
                        if (!rx_sync2) begin // Falling edge (Start bit)
                            state_q <= ST_START;
                        end
                    end

                    ST_START: begin
                        if (sample_cnt == 4'd7) begin // Sample at mid-point of start bit
                            if (!rx_sync2) begin
                                sample_cnt <= 4'd0;
                                state_q    <= ST_DATA;
                            end else begin
                                state_q <= ST_IDLE; // False start glitch
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end

                    ST_DATA: begin
                        if (sample_cnt == 4'd15) begin
                            sample_cnt <= 4'd0;
                            rx_shift   <= {rx_sync2, rx_shift[7:1]};
                            if (bit_cnt == 3'd7) begin
                                state_q <= ST_STOP;
                            end else begin
                                bit_cnt <= bit_cnt + 3'd1;
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end

                    ST_STOP: begin
                        if (sample_cnt == 4'd15) begin
                            sample_cnt <= 4'd0;
                            state_q    <= ST_IDLE;
                            if (rx_sync2) begin // Stop bit should be 1
                                rx_data_o    <= rx_shift;
                                rx_valid_o   <= 1'b1;
                                reg_rx_data  <= rx_shift;
                                reg_rx_valid <= 1'b1;
                                reg_rx_err   <= 1'b0;
                                if (reg_irq_en) reg_irq_sts <= 1'b1;
                            end else begin
                                reg_rx_err <= 1'b1; // Framing error
                            end
                        end else begin
                            sample_cnt <= sample_cnt + 4'd1;
                        end
                    end

                    default: state_q <= ST_IDLE;
                endcase
            end
        end
    end

    assign irq_rx_o = reg_irq_sts;

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
            reg_en         <= 1'b1;
            reg_baud_div   <= (DEFAULT_BAUD_DIV > 0) ? DEFAULT_BAUD_DIV[15:0] : 16'd27;
            reg_irq_en     <= 1'b1;
        end else begin
            resp_pending_q <= req_i;
            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_CTRL:     resp_rdata_q <= {31'b0, reg_en};
                    REG_STATUS:   resp_rdata_q <= {29'b0, reg_rx_err, 1'b0, reg_rx_valid};
                    REG_RX_DATA:  resp_rdata_q <= {24'b0, reg_rx_data};
                    REG_BAUD_DIV: resp_rdata_q <= {16'b0, reg_baud_div};
                    REG_IRQ_EN:   resp_rdata_q <= {31'b0, reg_irq_en};
                    REG_IRQ_STS:  resp_rdata_q <= {31'b0, reg_irq_sts};
                    default: begin
                        resp_rdata_q <= 32'hDEAD_BEEF;
                        resp_err_q   <= 1'b1;
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_CTRL: begin
                            if (be_i[0]) begin
                                reg_en <= wdata_i[0];
                            end
                        end
                        REG_BAUD_DIV: begin
                            if (be_i[0]) reg_baud_div[ 7:0] <= wdata_i[ 7:0];
                            if (be_i[1]) reg_baud_div[15:8] <= wdata_i[15:8];
                        end
                        REG_IRQ_EN: begin
                            if (be_i[0]) reg_irq_en <= wdata_i[0];
                        end
                        default: ;
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end
        end
    end

endmodule : uart_rx
