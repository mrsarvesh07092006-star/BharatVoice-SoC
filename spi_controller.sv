// =============================================================================
// BharatVoice SoC — SPI Controller with OBI Bus Interface
// File   : spi_controller.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Synthesis & DRC/LVS Aware Production RTL)
//
// Description:
//   Connects the Ibex OBI bus to the high-speed SPI Master core.
//   Exposes control, status, TX/RX buffers, clock divider, and interrupt registers
//   matching memory_map.md Section 3.5 (0x4000_4000).
// =============================================================================

`timescale 1ns/1ps

module spi_controller #(
    parameter int unsigned DATA_W    = 32,
    parameter int unsigned CLK_DIV_W = 16
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_4000)
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,

    // External SPI pins
    output logic        sclk_o,
    output logic        mosi_o,
    input  logic        miso_i,
    output logic        cs_n_o,

    // Interrupt output to core
    output logic        irq_done_o
);

    // Register Offsets
    localparam logic [7:0] REG_SPI_CTRL       = 8'h00;
    localparam logic [7:0] REG_SPI_STATUS     = 8'h04;
    localparam logic [7:0] REG_SPI_TX_DATA    = 8'h08;
    localparam logic [7:0] REG_SPI_RX_DATA    = 8'h0C;
    localparam logic [7:0] REG_SPI_CLK_DIV    = 8'h10;
    localparam logic [7:0] REG_SPI_CS_CTRL    = 8'h14;
    localparam logic [7:0] REG_SPI_IRQ_EN     = 8'h18;
    localparam logic [7:0] REG_SPI_IRQ_STATUS = 8'h1C;

    // Registers
    logic                 reg_en;
    logic                 reg_cpol;
    logic                 reg_cpha;
    logic                 spi_start_pulse;
    logic [DATA_W-1:0]    reg_tx_data;
    logic [DATA_W-1:0]    reg_rx_data;
    logic [CLK_DIV_W-1:0] reg_clk_div;
    logic                 reg_cs_force_high;
    logic                 reg_irq_en;
    logic                 reg_irq_sts;

    // Internal SPI Core Wires
    logic                 core_busy;
    logic                 core_done;
    logic                 core_err_cfg;
    logic                 core_err_busy;
    logic [DATA_W-1:0]    core_rx_data;
    logic                 core_sclk;
    logic                 core_mosi;
    logic                 core_cs_n;

    // Instantiate Physical SPI Master Core
    spi_master #(
        .DATA_W    (DATA_W),
        .CLK_DIV_W (CLK_DIV_W)
    ) u_core (
        .clk      (clk_i),
        .rst_n    (rst_ni),
        .start    (spi_start_pulse),
        .tx_data  (reg_tx_data),
        .xfer_len (6'd8), // Default 8-bit byte transfers
        .clk_div  (reg_clk_div),
        .cpol     (reg_cpol),
        .cpha     (reg_cpha),
        .busy     (core_busy),
        .done     (core_done),
        .err_cfg  (core_err_cfg),
        .err_busy (core_err_busy),
        .rx_data  (core_rx_data),
        .sclk     (core_sclk),
        .mosi     (core_mosi),
        .miso     (miso_i),
        .cs_n     (core_cs_n)
    );

    assign sclk_o     = core_sclk;
    assign mosi_o     = core_mosi;
    assign cs_n_o     = reg_cs_force_high ? 1'b1 : core_cs_n;
    assign irq_done_o = core_done && reg_irq_en;

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
            resp_pending_q    <= 1'b0;
            resp_rdata_q      <= 32'd0;
            resp_err_q        <= 1'b0;
            reg_en            <= 1'b1;
            reg_cpol          <= 1'b0;
            reg_cpha          <= 1'b0;
            spi_start_pulse   <= 1'b0;
            reg_tx_data       <= '0;
            reg_rx_data       <= '0;
            reg_clk_div       <= 16'd4; // Default sys_clk / 4
            reg_cs_force_high <= 1'b0;
            reg_irq_en        <= 1'b1;
            reg_irq_sts       <= 1'b0;
        end else begin
            spi_start_pulse <= 1'b0; // 1-cycle auto-clearing pulse
            resp_pending_q  <= req_i;

            // Core status capture
            if (core_done) begin
                reg_rx_data <= core_rx_data;
                if (reg_irq_en) reg_irq_sts <= 1'b1;
            end

            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_SPI_CTRL:       resp_rdata_q <= {28'b0, reg_cpha, reg_cpol, 1'b0, reg_en};
                    REG_SPI_STATUS:     resp_rdata_q <= {29'b0, !core_busy, core_done, core_busy};
                    REG_SPI_TX_DATA:    resp_rdata_q <= reg_tx_data;
                    REG_SPI_RX_DATA:    resp_rdata_q <= reg_rx_data;
                    REG_SPI_CLK_DIV:    resp_rdata_q <= {16'b0, reg_clk_div};
                    REG_SPI_CS_CTRL:    resp_rdata_q <= {31'b0, reg_cs_force_high};
                    REG_SPI_IRQ_EN:     resp_rdata_q <= {31'b0, reg_irq_en};
                    REG_SPI_IRQ_STATUS: resp_rdata_q <= {31'b0, reg_irq_sts};
                    default: begin
                        resp_rdata_q <= 32'hDEAD_BEEF;
                        resp_err_q   <= 1'b1;
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_SPI_CTRL: begin
                            if (be_i[0]) begin
                                reg_en          <= wdata_i[0];
                                spi_start_pulse <= wdata_i[1];
                                reg_cpol        <= wdata_i[2];
                                reg_cpha        <= wdata_i[3];
                            end
                        end
                        REG_SPI_TX_DATA: begin
                            if (be_i[0]) reg_tx_data[ 7: 0] <= wdata_i[ 7: 0];
                            if (be_i[1]) reg_tx_data[15: 8] <= wdata_i[15: 8];
                            if (be_i[2]) reg_tx_data[23:16] <= wdata_i[23:16];
                            if (be_i[3]) reg_tx_data[31:24] <= wdata_i[31:24];
                        end
                        REG_SPI_CLK_DIV: begin
                            if (be_i[0]) reg_clk_div[ 7:0] <= wdata_i[ 7:0];
                            if (be_i[1]) reg_clk_div[15:8] <= wdata_i[15:8];
                        end
                        REG_SPI_CS_CTRL: begin
                            if (be_i[0]) reg_cs_force_high <= wdata_i[0];
                        end
                        REG_SPI_IRQ_EN: begin
                            if (be_i[0]) reg_irq_en <= wdata_i[0];
                        end
                        REG_SPI_IRQ_STATUS: begin
                            if (be_i[0] && wdata_i[0]) reg_irq_sts <= 1'b0; // RW1C
                        end
                        default: ;
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end
        end
    end

endmodule : spi_controller
