// =============================================================================
// BharatVoice SoC — Power Manager Controller
// File   : power_manager.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Production RTL)
//
// Description:
//   Dynamic power controller managing active and clock-gated sleep states,
//   sleep cycle profiling, multi-source wake detection (UART/SPI), and
//   wake-up interrupt generation.
// =============================================================================

`timescale 1ns/1ps

module power_manager (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_7000)
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,

    // Wakeup input lines
    input  logic        uart_rx_i,
    input  logic        spi_activity_i,

    // Interrupt output to core
    output logic        irq_wakeup_o,

    // Clock gating control signal to root clock buffer
    output logic        clk_en_o
);

    // Register Offsets
    localparam logic [7:0] REG_PWR_CTRL       = 8'h00;
    localparam logic [7:0] REG_PWR_STATUS     = 8'h04;
    localparam logic [7:0] REG_PWR_WAKEUP_SRC = 8'h08;
    localparam logic [7:0] REG_PWR_SLEEP_CNT  = 8'h0C;
    localparam logic [7:0] REG_PWR_IRQ_EN     = 8'h10;
    localparam logic [7:0] REG_PWR_IRQ_STS    = 8'h14;

    // Registers
    logic        reg_active;
    logic        reg_sleep;
    logic        reg_wakeup_pend;
    logic [ 1:0] reg_wakeup_src; // [0]=UART, [1]=SPI
    logic [31:0] reg_sleep_cnt;
    logic        reg_irq_en;
    logic        reg_irq_sts;

    // Edge detector on UART RX (falling edge indicates start bit in sleep)
    logic uart_q1, uart_q2;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            uart_q1 <= 1'b1;
            uart_q2 <= 1'b1;
        end else begin
            uart_q1 <= uart_rx_i;
            uart_q2 <= uart_q1;
        end
    end
    wire uart_wake_event = (uart_q2 && !uart_q1); // Falling edge

    // Sleep / Wakeup State Logic
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            reg_active      <= 1'b1;
            reg_sleep       <= 1'b0;
            reg_wakeup_pend <= 1'b0;
            reg_sleep_cnt   <= 32'd0;
            irq_wakeup_o    <= 1'b0;
        end else begin
            irq_wakeup_o <= 1'b0; // default pulse

            if (reg_sleep) begin
                reg_sleep_cnt <= reg_sleep_cnt + 32'd1;

                // Wakeup condition check
                if ((reg_wakeup_src[0] && uart_wake_event) ||
                    (reg_wakeup_src[1] && spi_activity_i)) begin
                    reg_sleep       <= 1'b0;
                    reg_active      <= 1'b1;
                    reg_wakeup_pend <= 1'b1;
                    if (reg_irq_en) begin
                        irq_wakeup_o <= 1'b1;
                        reg_irq_sts  <= 1'b1;
                    end
                end
            end
        end
    end

    // clk_en_o stays high whenever active or when waking up
    assign clk_en_o = reg_active || !reg_sleep;

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
            reg_wakeup_src <= 2'b01; // UART wake enabled by default
            reg_irq_en     <= 1'b1;
            reg_irq_sts    <= 1'b0;
        end else begin
            resp_pending_q <= req_i;
            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_PWR_CTRL:       resp_rdata_q <= {30'b0, reg_sleep, reg_active};
                    REG_PWR_STATUS:     resp_rdata_q <= {29'b0, reg_wakeup_pend, reg_sleep, reg_active};
                    REG_PWR_WAKEUP_SRC: resp_rdata_q <= {30'b0, reg_wakeup_src};
                    REG_PWR_SLEEP_CNT:  resp_rdata_q <= reg_sleep_cnt;
                    REG_PWR_IRQ_EN:     resp_rdata_q <= {31'b0, reg_irq_en};
                    REG_PWR_IRQ_STS:    resp_rdata_q <= {31'b0, reg_irq_sts};
                    default: begin
                        resp_rdata_q <= 32'hDEAD_BEEF;
                        resp_err_q   <= 1'b1;
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_PWR_CTRL: begin
                            if (be_i[0]) begin
                                if (wdata_i[1]) begin // sleep_req
                                    reg_sleep       <= 1'b1;
                                    reg_active      <= 1'b0;
                                    reg_wakeup_pend <= 1'b0;
                                end else if (wdata_i[0]) begin
                                    reg_sleep       <= 1'b0;
                                    reg_active      <= 1'b1;
                                end
                            end
                        end

                        REG_PWR_WAKEUP_SRC: begin
                            if (be_i[0]) reg_wakeup_src <= wdata_i[1:0];
                        end

                        REG_PWR_IRQ_EN: begin
                            if (be_i[0]) reg_irq_en <= wdata_i[0];
                        end

                        REG_PWR_IRQ_STS: begin
                            if (be_i[0] && wdata_i[0]) begin
                                reg_irq_sts     <= 1'b0; // RW1C
                                reg_wakeup_pend <= 1'b0;
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

endmodule : power_manager
