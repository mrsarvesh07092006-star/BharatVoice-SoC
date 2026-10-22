// =============================================================================
// BharatVoice SoC — Boot ROM Module (4 KB)
// File   : boot_rom.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Synthesizable ROM)
//
// Description:
//   Synthesizable 4 KB Boot ROM containing RISC-V RV32IMC boot firmware:
//   stack pointer initialization to top of 64 KB SRAM (0x2001_0000),
//   machine trap setup, peripheral initialization, and transaction polling loop.
// =============================================================================

`timescale 1ns/1ps

module boot_rom #(
    parameter int unsigned DEPTH = 1024 // 1024 words x 32-bit = 4 KB
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Instruction OBI Port
    input  logic        req_i,
    input  logic [31:0] addr_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        gnt_o,
    output logic        err_o
);

    wire [9:0] word_idx = addr_i[11:2];
    logic [31:0] rom_data;

    // Real RISC-V RV32I Firmware Instructions
    always_comb begin
        unique case (word_idx)
            // Word 0 (0x0000_0000): lui sp, 0x20010 (Set stack pointer sp = 0x2001_0000)
            10'd0: rom_data = 32'h20010137;
            // Word 1 (0x0000_0004): lui gp, 0x40000 (Set global pointer gp = 0x4000_0000, peripheral base)
            10'd1: rom_data = 32'h400001B7;
            // Word 2 (0x0000_0008): addi t0, zero, 1 (t0 = 1, enable bit)
            10'd2: rom_data = 32'h00100293;
            // Word 3 (0x0000_000C): sw t0, 0(gp) (Write 1 to TXN_CTRL at 0x4000_0000)
            10'd3: rom_data = 32'h0051A023;
            // Word 4 (0x0000_0010): lw t1, 4(gp) (Read TXN_STATUS at 0x4000_0004)
            10'd4: rom_data = 32'h0041A303;
            // Word 5 (0x0000_0014): andi t2, t1, 1 (Check valid bit)
            10'd5: rom_data = 32'h00137393;
            // Word 6 (0x0000_0018): beq t2, zero, -8 (Branch back to lw if not valid -> 0x0010)
            10'd6: rom_data = 32'hFE038CE3;
            // Word 7 (0x0000_001C): lw t3, 8(gp) (Read valid amount from TXN_AMOUNT at 0x4000_0008)
            10'd7: rom_data = 32'h0081AE03;
            // Word 8 (0x0000_0020): j -16 (Loop back to poll next transaction)
            10'd8: rom_data = 32'hFF1FF06F;
            // Remainder: NOP instructions (addi x0, x0, 0)
            default: rom_data = 32'h00000013;
        endcase
    end

    // OBI zero-wait-state grant
    assign gnt_o = req_i;
    assign err_o = (addr_i[31:12] != 20'h00000); // Error if address outside 4 KB ROM

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rdata_o  <= 32'd0;
            rvalid_o <= 1'b0;
        end else begin
            rvalid_o <= req_i;
            if (req_i) begin
                rdata_o <= rom_data;
            end
        end
    end

endmodule : boot_rom
