// =============================================================================
// BharatVoice SoC — Transaction Cache Module
// File   : transaction_cache.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Production RTL)
//
// Description:
//   16-entry fast on-chip transaction cache with hit/miss performance counters,
//   flash invalidation/flush control, and memory-mapped OBI slave access.
// =============================================================================

`timescale 1ns/1ps

module transaction_cache #(
    parameter int unsigned NUM_ENTRIES = 16
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_3000)
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
    localparam logic [7:0] REG_CACHE_CTRL     = 8'h00;
    localparam logic [7:0] REG_CACHE_STATUS   = 8'h04;
    localparam logic [7:0] REG_CACHE_ENTRIES  = 8'h08;
    localparam logic [7:0] REG_CACHE_HIT_CNT  = 8'h0C;
    localparam logic [7:0] REG_CACHE_MISS_CNT = 8'h10;
    localparam logic [7:0] REG_CACHE_LOOKUP   = 8'h14;

    // Registers
    logic        reg_en;
    logic        reg_status_hit;
    logic        reg_status_miss;
    logic        reg_status_full;
    logic [31:0] reg_hit_cnt;
    logic [31:0] reg_miss_cnt;

    // Cache Storage: 16 entries (valid, ID, amount)
    logic [NUM_ENTRIES-1:0] entry_valid;
    logic [31:0]            entry_id    [0:NUM_ENTRIES-1];
    logic [31:0]            entry_amt   [0:NUM_ENTRIES-1];
    logic [ 3:0]            alloc_ptr;

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

    // Lookup helper
    function automatic logic find_entry(
        input  logic [31:0] id,
        output logic [ 3:0] match_idx
    );
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entry_valid[i] && entry_id[i] == id) begin
                match_idx = i[3:0];
                return 1'b1;
            end
        end
        match_idx = 4'd0;
        return 1'b0;
    endfunction

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            resp_pending_q  <= 1'b0;
            resp_rdata_q    <= 32'd0;
            resp_err_q      <= 1'b0;
            reg_en          <= 1'b1;
            reg_status_hit  <= 1'b0;
            reg_status_miss <= 1'b0;
            reg_status_full <= 1'b0;
            reg_hit_cnt     <= 32'd0;
            reg_miss_cnt    <= 32'd0;
            entry_valid     <= '0;
            alloc_ptr       <= 4'd0;
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                entry_id[i]  <= 32'd0;
                entry_amt[i] <= 32'd0;
            end
        end else begin
            resp_pending_q <= req_i;
            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_CACHE_CTRL:     resp_rdata_q <= {31'b0, reg_en};
                    REG_CACHE_STATUS:   resp_rdata_q <= {29'b0, reg_status_full, reg_status_miss, reg_status_hit};
                    REG_CACHE_ENTRIES:  resp_rdata_q <= NUM_ENTRIES;
                    REG_CACHE_HIT_CNT:  resp_rdata_q <= reg_hit_cnt;
                    REG_CACHE_MISS_CNT: resp_rdata_q <= reg_miss_cnt;
                    default: begin
                        // Direct entry query: offset 0x20..0x5C
                        if (addr_i[7:6] == 2'b01) begin
                            resp_rdata_q <= entry_amt[addr_i[5:2]];
                        end else begin
                            resp_rdata_q <= 32'hDEAD_BEEF;
                            resp_err_q   <= 1'b1;
                        end
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_CACHE_CTRL: begin
                            if (be_i[0]) begin
                                reg_en <= wdata_i[0];
                                if (wdata_i[1]) begin // flush
                                    entry_valid     <= '0;
                                    alloc_ptr       <= 4'd0;
                                    reg_hit_cnt     <= 32'd0;
                                    reg_miss_cnt    <= 32'd0;
                                    reg_status_hit  <= 1'b0;
                                    reg_status_miss <= 1'b0;
                                    reg_status_full <= 1'b0;
                                end
                            end
                        end

                        REG_CACHE_LOOKUP: begin
                            // Software queries an ID
                            if (reg_en) begin
                                logic [3:0] found_idx;
                                if (find_entry(wdata_i, found_idx)) begin
                                    reg_status_hit  <= 1'b1;
                                    reg_status_miss <= 1'b0;
                                    reg_hit_cnt     <= reg_hit_cnt + 32'd1;
                                end else begin
                                    reg_status_hit  <= 1'b0;
                                    reg_status_miss <= 1'b1;
                                    reg_miss_cnt    <= reg_miss_cnt + 32'd1;
                                    // Allocate new entry
                                    entry_valid[alloc_ptr] <= 1'b1;
                                    entry_id[alloc_ptr]    <= wdata_i;
                                    alloc_ptr              <= alloc_ptr + 4'd1;
                                    if (&entry_valid) reg_status_full <= 1'b1;
                                end
                            end
                        end

                        default: begin
                            // Write entry amount directly
                            if (addr_i[7:6] == 2'b01) begin
                                entry_amt[addr_i[5:2]] <= wdata_i;
                            end
                        end
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end
        end
    end

endmodule : transaction_cache
