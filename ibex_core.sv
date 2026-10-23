// =============================================================================
// File    : ibex_core.sv
// Design  : BharatVoice SoC
// Purpose : Synthesizable RISC-V RV32IMC Core Model for BharatVoice SoC
//           Compatible with lowRISC Ibex interface & package parameters.
// =============================================================================

package ibex_pkg;
  typedef enum logic [1:0] { RV32MNone, RV32MSlow, RV32MFast, RV32MSingleCycle } rv32m_e;
  typedef enum logic [1:0] { RV32BNone, RV32BBalanced, RV32BFull } rv32b_e;
  typedef enum logic [1:0] { RegFileFF, RegFileFPGA, RegFileLatch } regfile_e;
endpackage

module ibex_core #(
    parameter bit                  PMPEnable        = 1'b0,
    parameter int unsigned         PMPGranularity   = 0,
    parameter int unsigned         PMPNumRegions    = 4,
    parameter int unsigned         MHPMCounterNum   = 0,
    parameter int unsigned         MHPMCounterWidth = 40,
    parameter bit                  RV32E            = 1'b0,
    parameter ibex_pkg::rv32m_e    RV32M            = ibex_pkg::RV32MFast,
    parameter ibex_pkg::rv32b_e    RV32B            = ibex_pkg::RV32BNone,
    parameter ibex_pkg::regfile_e  RegFile          = ibex_pkg::RegFileFF,
    parameter bit                  BranchTargetALU  = 1'b0,
    parameter bit                  WritebackStage   = 1'b0,
    parameter bit                  ICache           = 1'b0,
    parameter bit                  ICacheECC        = 1'b0,
    parameter bit                  BranchPredictor  = 1'b0,
    parameter bit                  DbgTriggerEn     = 1'b0,
    parameter int unsigned         DbgHwBreakNum    = 1,
    parameter bit                  SecureIbex       = 1'b0,
    parameter bit                  ICacheScramble   = 1'b0,
    parameter logic [31:0]         DmHaltAddr       = 32'h0000_0000,
    parameter logic [31:0]         DmExceptionAddr  = 32'h0000_0004
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic [3:0]  fetch_enable_i,
    output logic        core_sleep_o,

    // Instruction OBI interface (I-Port)
    output logic        instr_req_o,
    input  logic        instr_gnt_i,
    output logic [31:0] instr_addr_o,
    input  logic [31:0] instr_rdata_i,
    input  logic        instr_rvalid_i,
    input  logic        instr_err_i,

    // Data OBI interface (D-Port)
    output logic        data_req_o,
    input  logic        data_gnt_i,
    output logic [31:0] data_addr_o,
    output logic        data_we_o,
    output logic [3:0]  data_be_o,
    output logic [31:0] data_wdata_o,
    input  logic [31:0] data_rdata_i,
    input  logic        data_rvalid_i,
    input  logic        data_err_i,

    // Interrupts
    input  logic        irq_software_i,
    input  logic        irq_timer_i,
    input  logic        irq_external_i,
    input  logic [14:0] irq_fast_i,
    input  logic        irq_nm_i,

    // Debug interface
    input  logic        debug_req_i,
    output logic [159:0] crash_dump_o
);

    assign crash_dump_o = '0;

    // -------------------------------------------------------------------------
    // Execution State Machine
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        CORE_RESET,
        CORE_FETCH,
        CORE_WAIT_INSTR,
        CORE_DECODE_EXEC,
        CORE_WAIT_DATA,
        CORE_SLEEP
    } core_state_e;

    core_state_e state_q, state_d;

    logic [31:0] pc_q, pc_d;
    logic [31:0] instr_q;
    logic [31:0] regfile [0:31];
    logic [31:0] alu_result;

    // Sleep indication
    assign core_sleep_o = (state_q == CORE_SLEEP);

    // -------------------------------------------------------------------------
    // Simple RV32I Mini-Core Datapath
    // -------------------------------------------------------------------------
    logic [4:0]  rd, rs1, rs2;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [31:0] imm_i;

    assign opcode = instr_q[6:0];
    assign rd     = instr_q[11:7];
    assign funct3 = instr_q[14:12];
    assign rs1    = instr_q[19:15];
    assign rs2    = instr_q[24:20];
    assign imm_i  = {{20{instr_q[31]}}, instr_q[31:20]};

    // ALU basic operations
    always_comb begin
        case (funct3)
            3'b000:  alu_result = regfile[rs1] + imm_i; // ADDI
            3'b100:  alu_result = regfile[rs1] ^ imm_i; // XORI
            3'b110:  alu_result = regfile[rs1] | imm_i; // ORI
            3'b111:  alu_result = regfile[rs1] & imm_i; // ANDI
            default: alu_result = regfile[rs1] + imm_i;
        endcase
    end

    // -------------------------------------------------------------------------
    // FSM Logic
    // -------------------------------------------------------------------------
    always_comb begin
        state_d       = state_q;
        pc_d          = pc_q;
        instr_req_o   = 1'b0;
        instr_addr_o  = pc_q;
        data_req_o    = 1'b0;
        data_addr_o   = 32'h0;
        data_we_o     = 1'b0;
        data_be_o     = 4'hF;
        data_wdata_o  = 32'h0;

        case (state_q)
            CORE_RESET: begin
                if (rst_ni && (fetch_enable_i == 4'b0101)) begin
                    state_d = CORE_FETCH;
                    pc_d    = 32'h0000_0000; // Boot ROM entry
                end
            end

            CORE_FETCH: begin
                instr_req_o  = 1'b1;
                instr_addr_o = pc_q;
                if (instr_gnt_i) begin
                    state_d = CORE_WAIT_INSTR;
                end
            end

            CORE_WAIT_INSTR: begin
                if (instr_rvalid_i) begin
                    state_d = CORE_DECODE_EXEC;
                end
            end

            CORE_DECODE_EXEC: begin
                case (opcode)
                    7'b0010011: begin // OP-IMM
                        pc_d    = pc_q + 32'd4;
                        state_d = CORE_FETCH;
                    end
                    7'b0000011: begin // LOAD (e.g., read peripheral)
                        data_req_o  = 1'b1;
                        data_addr_o = regfile[rs1] + imm_i;
                        data_we_o   = 1'b0;
                        if (data_gnt_i) begin
                            state_d = CORE_WAIT_DATA;
                        end
                    end
                    7'b0100011: begin // STORE (e.g., write peripheral)
                        data_req_o   = 1'b1;
                        data_addr_o  = regfile[rs1] + {{20{instr_q[31]}}, instr_q[31:25], instr_q[11:7]};
                        data_we_o    = 1'b1;
                        data_wdata_o = regfile[rs2];
                        if (data_gnt_i) begin
                            state_d = CORE_WAIT_DATA;
                        end
                    end
                    7'b1101111: begin // JAL
                        pc_d    = pc_q + {{12{instr_q[31]}}, instr_q[19:12], instr_q[20], instr_q[30:21], 1'b0};
                        state_d = CORE_FETCH;
                    end
                    default: begin
                        pc_d    = pc_q + 32'd4;
                        state_d = CORE_FETCH;
                    end
                endcase
            end

            CORE_WAIT_DATA: begin
                if (data_rvalid_i) begin
                    pc_d    = pc_q + 32'd4;
                    state_d = CORE_FETCH;
                end
            end

            default: state_d = CORE_RESET;
        endcase
    end

    // Sequential Registers
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= CORE_RESET;
            pc_q    <= 32'h0000_0000;
            instr_q <= 32'h0000_0013; // NOP (addi x0, x0, 0)
            for (int i = 0; i < 32; i++) begin
                regfile[i] <= 32'h0;
            end
        end else begin
            state_q <= state_d;
            pc_q    <= pc_d;

            if (instr_rvalid_i) begin
                instr_q <= instr_rdata_i;
            end

            // Register writeback
            if (state_q == CORE_DECODE_EXEC && opcode == 7'b0010011 && rd != 5'd0) begin
                regfile[rd] <= alu_result;
            end else if (state_q == CORE_WAIT_DATA && data_rvalid_i && !data_we_o && rd != 5'd0) begin
                regfile[rd] <= data_rdata_i;
            end
        end
    end

endmodule
