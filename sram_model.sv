// ============================================================================
// sram_model.sv  --  Parameterized behavioral SRAM (bus-independent)
// BharatVoice SoC | owner: Hrdya VR
//
// INTERFACE CONTRACT (all signals sampled on rising edge of clk)
//   clk     in  1        Clock.
//   rst_n   in  1        Active-low SYNCHRONOUS reset (sampled at posedge clk).
//   req     in  1        Request valid.
//   we      in  1        1 = write, 0 = read.
//   addr    in  ADDR_W   BYTE address. Word index = addr >> log2(DATA_W/8).
//                        Low (byte-offset) bits are ignored (word access only).
//   wdata   in  DATA_W   Write data.
//   be      in  DATA_W/8 Byte enables for writes (be[i] -> wdata[8*i+:8]).
//                        be == 0 on a write: no change, no error. Ignored on reads.
//   ready   out 1        Request-accept. A request is ACCEPTED at a clock edge
//                        iff (req && ready && rst_n) is true at that edge.
//                        ready is 0 during reset and for the first clock edge
//                        after reset release; it is 1 otherwise (the model can
//                        take one request every cycle, i.e. fully pipelined).
//   rvalid  out 1        Response valid. Every accepted request (read OR write)
//                        yields exactly one 1-cycle rvalid pulse, READ_LATENCY
//                        clock cycles after the accept edge.
//   rdata   out DATA_W   Read data (valid when rvalid). 0 for a valid write ack,
//                        ERR_RDATA for an invalid address, 0 when !rvalid.
//   err     out 1        Valid with rvalid: 1 = address out of range.
//
// TIMING (READ_LATENCY = L >= 1)
//   Request accepted at edge N  ->  rvalid/rdata/err visible after edge N+L-1
//   (i.e. L-1 idle cycles, then L-th cycle shows the response). L=1: response
//   is registered at the accept edge and visible in the very next cycle.
//   Writes commit to the array at the accept edge, so a read accepted on the
//   NEXT edge returns the new data (read-after-write is coherent).
//   Consecutive requests: one per cycle, responses in order, no stalls.
//
// INVALID ADDRESS: word index >= DEPTH. No array access happens (no write, no
//   read). Response: rvalid=1, err=1, rdata=ERR_RDATA. Misaligned (byte-offset
//   != 0) addresses inside range are NOT errors; they access the containing word.
//
// RESET: synchronous. Clears ready and every in-flight response (responses not
//   yet visible are dropped; a response already visible is unaffected).
//   A request presented at an edge where rst_n=0 is ignored, even if ready was
//   still 1. MEMORY CONTENTS SURVIVE RESET (like a real SRAM). Writes accepted
//   before reset assertion are retained.
//
// INITIALIZATION (simulation-only `initial` block)
//   INIT_MODE 0: every word = INIT_VALUE (default 0)   <-- deterministic default
//   INIT_MODE 1: every word = 'x (uninitialized; read-before-write shows X)
//   INIT_MODE 2: $readmemh(INIT_FILE) after filling with INIT_VALUE
//
// SIMULATION vs SYNTHESIS
//   Synthesizable (RAM-inference candidate): the clocked read/write/response
//   pipeline, byte-enable merge, address-range check.
//   Simulation-only: INIT_MODE X-fill, $readmemh, $fatal parameter checks.
//   (Memory init values are honoured by FPGA flows, not by ASIC.) This is NOT a
//   physical SRAM macro: no timing, power, BIST or macro-specific pins.
//
// NOTE: `mem` is written by an `initial` block and by a clocked block, so the
//   clocked block is plain `always @(posedge clk)` (not always_ff) -- always_ff
//   forbids a second writer and Questa rejects it.
// ============================================================================
`timescale 1ns/1ps

module sram_model #(
    parameter int unsigned ADDR_W       = 32,    // byte-address width (<= 32)
    parameter int unsigned DATA_W       = 32,    // multiple of 8, power of 2
    parameter int unsigned DEPTH        = 1024,  // number of DATA_W-wide words
    parameter int unsigned READ_LATENCY = 1,     // >= 1 cycles
    parameter int unsigned INIT_MODE    = 0,     // 0 fill, 1 X, 2 hex file
    parameter logic [DATA_W-1:0] INIT_VALUE = '0,
    parameter logic [DATA_W-1:0] ERR_RDATA  = {((DATA_W+31)/32){32'hDEAD_BEEF}},
    parameter string INIT_FILE = ""
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                req,
    input  logic                we,
    input  logic [ADDR_W-1:0]   addr,
    input  logic [DATA_W-1:0]   wdata,
    input  logic [DATA_W/8-1:0] be,
    output logic                ready,
    output logic                rvalid,
    output logic [DATA_W-1:0]   rdata,
    output logic                err
);

    localparam int unsigned BE_W     = DATA_W/8;
    localparam int unsigned BYTE_LSB = $clog2(BE_W);          // 0 when DATA_W=8
    localparam int unsigned IDX_W    = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    // ---- simulation-only parameter sanity checks ----
    initial begin
        if (READ_LATENCY < 1)      $fatal(1, "sram_model: READ_LATENCY must be >= 1");
        if (DATA_W % 8 != 0)       $fatal(1, "sram_model: DATA_W must be a multiple of 8");
        if (BE_W != (1 << BYTE_LSB)) $fatal(1, "sram_model: DATA_W/8 must be a power of 2");
        if (ADDR_W > 32)           $fatal(1, "sram_model: ADDR_W must be <= 32");
        if (IDX_W > ADDR_W - BYTE_LSB) $fatal(1, "sram_model: DEPTH too large for ADDR_W");
    end

    // ---- storage ----
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // simulation-only initialisation
    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            if (INIT_MODE == 1) mem[i] = 'x;
            else                mem[i] = INIT_VALUE;
        end
        if (INIT_MODE == 2) $readmemh(INIT_FILE, mem);
    end

    // ---- address decode (purely combinational, no loops) ----
    wire [ADDR_W-1:0] widx_full = addr >> BYTE_LSB;
    wire              addr_ok   = (widx_full < DEPTH);
    wire [IDX_W-1:0]  widx      = widx_full[IDX_W-1:0];

    // ---- response pipeline: stage 0 .. READ_LATENCY-1 ----
    logic              pv [0:READ_LATENCY-1];
    logic [DATA_W-1:0] pd [0:READ_LATENCY-1];
    logic              pe [0:READ_LATENCY-1];

    assign rvalid = pv[READ_LATENCY-1];
    assign rdata  = pd[READ_LATENCY-1];
    assign err    = pe[READ_LATENCY-1];

    always @(posedge clk) begin : core
        logic [DATA_W-1:0] merged;
        if (!rst_n) begin
            ready <= 1'b0;
            for (int i = 0; i < READ_LATENCY; i++) begin
                pv[i] <= 1'b0;
                pd[i] <= '0;
                pe[i] <= 1'b0;
            end
        end else begin
            ready <= 1'b1;
            // advance the pipeline
            for (int i = 1; i < READ_LATENCY; i++) begin
                pv[i] <= pv[i-1];
                pd[i] <= pd[i-1];
                pe[i] <= pe[i-1];
            end
            // default for stage 0: bubble
            pv[0] <= 1'b0;
            pd[0] <= '0;
            pe[0] <= 1'b0;
            // accept a request
            if (req && ready) begin
                pv[0] <= 1'b1;
                if (!addr_ok) begin
                    pe[0] <= 1'b1;
                    pd[0] <= ERR_RDATA;
                end else if (we) begin
                    merged = mem[widx];
                    for (int b = 0; b < BE_W; b++)
                        if (be[b]) merged[8*b +: 8] = wdata[8*b +: 8];
                    mem[widx] <= merged;
                end else begin
                    pd[0] <= mem[widx];
                end
            end
        end
    end

endmodule
