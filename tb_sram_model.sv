// ============================================================================
// tb_sram_model.sv -- self-checking testbench for sram_model
//
// Method: all stimulus is driven at NEGEDGE clk, all sampling is done at
// NEGEDGE clk (DUT outputs change only after posedge), so there are no races.
// Two layers of checking:
//   (1) a cycle-accurate SCOREBOARD (independent reference model + response
//       delay line) compares ready/rvalid/rdata/err every cycle;
//   (2) DIRECTED tests with hard-coded expected values and explicit latency checks.
//
// Override latency:  Icarus  -Ptb_sram_model.LAT=3     Questa  -GLAT=3
// ============================================================================
`timescale 1ns/1ps

module tb_sram_model;

    parameter int ADDR_W = 12;     // 4096 byte addresses = 1024 word indices
    parameter int DEPTH  = 64;     // only 64 valid words -> invalid addresses exist
    parameter int LAT    = 1;      // READ_LATENCY under test
    localparam int DATA_W = 32;    // testbench patterns assume 32 bits
    localparam int LSB    = 2;
    localparam logic [31:0] ERR_PAT = 32'hDEAD_BEEF;
    localparam int LASTW  = DEPTH - 1;

    // ---------------- DUT hookup ----------------
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic req = 1'b0, we = 1'b0;
    logic [ADDR_W-1:0] addr = '0;
    logic [DATA_W-1:0] wdata = '0;
    logic [3:0]        be = '0;
    wire               ready, rvalid, err;
    wire  [DATA_W-1:0] rdata;

    always #5 clk = ~clk;   // 100 MHz

    sram_model #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .DEPTH(DEPTH),
        .READ_LATENCY(LAT), .INIT_MODE(0), .INIT_VALUE(32'h0),
        .ERR_RDATA(ERR_PAT), .INIT_FILE("")
    ) dut (
        .clk(clk), .rst_n(rst_n), .req(req), .we(we), .addr(addr),
        .wdata(wdata), .be(be), .ready(ready), .rvalid(rvalid),
        .rdata(rdata), .err(err)
    );

    // ---------------- bookkeeping ----------------
    int pass_cnt = 0, fail_cnt = 0;
    int sb_err = 0, sb_cycles = 0;
    bit sb_en = 1'b0;

    task automatic check(input bit cond, input string msg);
        if (cond) begin pass_cnt++; $display("  [PASS] %s", msg); end
        else      begin fail_cnt++; $display("  [FAIL] %s  (t=%0t)", msg, $time); end
    endtask

    // ---------------- scoreboard (reference model) ----------------
    logic [31:0] ref_mem [0:DEPTH-1];
    logic        pv [0:LAT-1];
    logic [31:0] pd [0:LAT-1];
    logic        pe [0:LAT-1];
    logic        exp_ready = 1'b0;

    initial for (int i = 0; i < DEPTH; i++) ref_mem[i] = 32'h0;

    always @(posedge clk) begin : sb_model
        int idx;
        logic [31:0] cur;
        exp_ready <= rst_n;
        if (!rst_n) begin
            for (int i = 0; i < LAT; i++) begin pv[i] <= 1'b0; pd[i] <= 32'h0; pe[i] <= 1'b0; end
        end else begin
            for (int i = 1; i < LAT; i++) begin pv[i] <= pv[i-1]; pd[i] <= pd[i-1]; pe[i] <= pe[i-1]; end
            pv[0] <= 1'b0; pd[0] <= 32'h0; pe[0] <= 1'b0;
            if (req && exp_ready) begin
                idx = addr >> LSB;
                pv[0] <= 1'b1;
                if (idx >= DEPTH) begin
                    pe[0] <= 1'b1; pd[0] <= ERR_PAT;
                end else if (we) begin
                    cur = ref_mem[idx];
                    for (int b = 0; b < 4; b++) if (be[b]) cur[8*b +: 8] = wdata[8*b +: 8];
                    ref_mem[idx] = cur;
                end else begin
                    pd[0] <= ref_mem[idx];
                end
            end
        end
    end

    // response log + cycle-by-cycle comparison, sampled at negedge
    logic [31:0] rsp_data [0:2047];
    bit          rsp_err  [0:2047];
    int          rsp_cnt = 0;

    always @(negedge clk) if (sb_en) begin
        sb_cycles++;
        if (ready !== exp_ready || rvalid !== pv[LAT-1] ||
            rdata !== pd[LAT-1] || err !== pe[LAT-1]) begin
            sb_err++;
            if (sb_err <= 10)
                $display("  [SB-MISMATCH] t=%0t ready=%b/%b rvalid=%b/%b rdata=%h/%h err=%b/%b (got/exp)",
                         $time, ready, exp_ready, rvalid, pv[LAT-1], rdata, pd[LAT-1], err, pe[LAT-1]);
        end
        if (rvalid === 1'b1) begin
            rsp_data[rsp_cnt % 2048] = rdata;
            rsp_err [rsp_cnt % 2048] = err;
            rsp_cnt++;
        end
    end

    // ---------------- driver tasks ----------------
    // Present one request and return at the posedge where it is accepted.
    // Back-to-back calls give one request per cycle (signals change at negedge).
    task automatic issue(input bit w, input [ADDR_W-1:0] a, input [31:0] d, input [3:0] b);
        int guard;
        begin
            guard = 0;
            @(negedge clk);
            req = 1'b1; we = w; addr = a; wdata = d; be = b;
            while (ready !== 1'b1 && guard < 100) begin guard++; @(negedge clk); end
            if (guard >= 100) check(1'b0, "issue(): ready stuck low");
            @(posedge clk);
        end
    endtask

    task automatic idle(input int n);
        repeat (n) begin @(negedge clk); req = 1'b0; we = 1'b0; end
    endtask

    // Isolated access with explicit latency/pulse checks.
    task automatic access(input bit w, input [ADDR_W-1:0] a, input [31:0] d, input [3:0] b,
                          input [31:0] expd, input bit expe, input string name);
        bit ok;
        begin
            ok = 1'b1;
            issue(w, a, d, b);
            for (int k = 1; k <= LAT; k++) begin
                @(negedge clk); req = 1'b0; we = 1'b0;
                if (k < LAT) ok &= (rvalid === 1'b0);
                else         ok &= (rvalid === 1'b1) && (rdata === expd) && (err === expe);
            end
            @(negedge clk);
            ok &= (rvalid === 1'b0);          // single-cycle pulse
            if (!ok) $display("      got rvalid=%b rdata=%h err=%b ; expected data=%h err=%b",
                              rvalid, rdata, err, expd, expe);
            check(ok, name);
        end
    endtask

    task automatic wr(input int widx, input [31:0] d, input [3:0] b, input string name);
        access(1'b1, widx*4, d, b, 32'h0, 1'b0, name);
    endtask
    task automatic rd(input int widx, input [31:0] expd, input string name);
        access(1'b0, widx*4, 32'h0, 4'h0, expd, 1'b0, name);
    endtask

    function automatic [31:0] pat(input int i);
        pat = (32'h0101_0101 * (i + 1)) ^ 32'h5A5A_C3C3;
    endfunction

    // ---------------- main ----------------
    int rc0;
    bit okb;
    int tw;
    initial begin : main
        // initial reset (scoreboard armed once pipeline regs are defined)
        repeat (3) @(negedge clk);
        sb_en = 1'b1;
        @(negedge clk); rst_n = 1'b1;
        repeat (2) @(negedge clk);

        $display("=== tb_sram_model  (READ_LATENCY=%0d, DEPTH=%0d, ADDR_W=%0d) ===", LAT, DEPTH, ADDR_W);

        // ---- Test 1: reset behaviour ----
        $display("TEST 1: reset behaviour");
        @(negedge clk); req = 1'b0; rst_n = 1'b0;
        repeat (3) @(negedge clk);
        check(ready === 1'b0 && rvalid === 1'b0 && rdata === 32'h0 && err === 1'b0,
              "T1a outputs idle during reset (ready=0,rvalid=0,rdata=0,err=0)");
        req = 1'b1; we = 1'b1; addr = 4*4; wdata = 32'hFFFF_FFFF; be = 4'hF;   // request during reset
        @(negedge clk); req = 1'b0; we = 1'b0;
        check(ready === 1'b0 && rvalid === 1'b0, "T1b ready stays low and no response for request made during reset");
        rst_n = 1'b1;
        check(ready === 1'b0, "T1c ready still low until first clock edge after release");
        @(negedge clk);
        check(ready === 1'b1, "T1d ready=1 one cycle after reset release");
        rd(4, 32'h0, "T1e request during reset was ignored; memory initialised to 0 (INIT_MODE 0)");
        rd(LASTW, 32'h0, "T1f last word initialised to 0");

        // ---- Test 2: single word ----
        $display("TEST 2: single word write/read");
        wr(8, 32'hA5A5_1234, 4'hF, "T2a write word 8");
        rd(8, 32'hA5A5_1234, "T2b read back word 8");

        // ---- Test 3: multiple addresses ----
        $display("TEST 3: multiple addresses");
        for (int i = 0; i < 16; i++) wr(i, pat(i), 4'hF, $sformatf("T3 write word %0d", i));
        for (int i = 0; i < 16; i++) rd(i, pat(i), $sformatf("T3 read word %0d", i));

        // ---- Test 4: byte enables ----
        $display("TEST 4: byte enables");
        wr(20, 32'h1122_3344, 4'hF, "T4a full word");
        wr(20, 32'hAABB_CCDD, 4'b0001, "T4b be=0001");
        rd(20, 32'h1122_33DD, "T4b' only byte0 changed");
        wr(20, 32'hAABB_CCDD, 4'b0010, "T4c be=0010");
        rd(20, 32'h1122_CCDD, "T4c' only byte1 changed");
        wr(20, 32'h5566_7788, 4'b1010, "T4d be=1010");
        rd(20, 32'h5522_77DD, "T4d' bytes 3,1 changed");
        wr(20, 32'hFFFF_FFFF, 4'b0000, "T4e be=0000");
        rd(20, 32'h5522_77DD, "T4e' unchanged for be=0");

        // ---- Test 5: read-after-write, write then read on NEXT cycle ----
        $display("TEST 5: read after write (back-to-back)");
        rc0 = rsp_cnt;
        issue(1'b1, 21*4, 32'hCAFE_F00D, 4'hF);
        issue(1'b0, 21*4, 32'h0,         4'h0);
        idle(LAT + 2);
        check(rsp_cnt - rc0 == 2, "T5a two responses (write ack + read)");
        check(rsp_data[rc0+0] === 32'h0 && rsp_err[rc0+0] === 1'b0, "T5b write ack rdata=0 err=0");
        check(rsp_data[rc0+1] === 32'hCAFE_F00D, "T5c read in the cycle after write sees new data");

        // ---- Test 6: consecutive / back-to-back streams ----
        $display("TEST 6: consecutive requests");
        rc0 = rsp_cnt;
        for (int i = 0; i < 8; i++) issue(1'b1, (24+i)*4, 32'hC0DE_0000 + i, 4'hF);
        idle(LAT + 2);
        check(rsp_cnt - rc0 == 8, "T6a 8 back-to-back writes -> 8 acks");
        rc0 = rsp_cnt;
        for (int i = 0; i < 8; i++) issue(1'b0, (24+i)*4, 32'h0, 4'h0);
        idle(LAT + 2);
        okb = (rsp_cnt - rc0 == 8);
        for (int i = 0; i < 8; i++) okb &= (rsp_data[rc0+i] === 32'hC0DE_0000 + i);
        check(okb, "T6b 8 back-to-back reads -> 8 in-order responses with correct data");
        rc0 = rsp_cnt;
        issue(1'b1, 33*4, 32'h1111_1111, 4'hF);
        issue(1'b0, 33*4, 32'h0, 4'h0);
        issue(1'b1, 33*4, 32'h2222_2222, 4'hF);
        issue(1'b0, 33*4, 32'h0, 4'h0);
        idle(LAT + 2);
        check(rsp_cnt - rc0 == 4 && rsp_data[rc0+1] === 32'h1111_1111 && rsp_data[rc0+3] === 32'h2222_2222,
              "T6c W,R,W,R same address returns 1111_1111 then 2222_2222");

        // ---- Test 7: first / last location ----
        $display("TEST 7: first and last valid locations");
        wr(0,     32'h0F1E_2D3C, 4'hF, "T7a write first word");
        wr(LASTW, 32'h4B5A_6978, 4'hF, "T7b write last word");
        rd(0,     32'h0F1E_2D3C, "T7c read first word");
        rd(LASTW, 32'h4B5A_6978, "T7d read last word");
        rd(LASTW-1, 32'h0, "T7e word before last untouched (no aliasing)");
        rd(1, pat(1), "T7f word after first untouched");

        // ---- Test 8: invalid address ----
        $display("TEST 8: invalid addresses");
        access(1'b0, DEPTH*4, 32'h0, 4'h0, ERR_PAT, 1'b1, "T8a read first invalid word -> err, ERR_RDATA");
        access(1'b1, DEPTH*4, 32'h0BAD_0BAD, 4'hF, ERR_PAT, 1'b1, "T8b write first invalid word -> err");
        rd(0, 32'h0F1E_2D3C, "T8c word 0 not corrupted (no address wrap-around)");
        rd(LASTW, 32'h4B5A_6978, "T8d last word not corrupted");
        access(1'b0, {ADDR_W{1'b1}}, 32'h0, 4'h0, ERR_PAT, 1'b1, "T8e read highest address -> err");
        access(1'b0, 8*4 + 3, 32'h0, 4'h0, pat(8), 1'b0, "T8f misaligned in-range address reads containing word, no err");

        // ---- Test 9: timing & acceptance ----
        $display("TEST 9: response timing and acceptance");
        issue(1'b0, 8*4, 32'h0, 4'h0);
        tw = 0;
        do begin @(negedge clk); req = 1'b0; tw++; end while (rvalid !== 1'b1 && tw < 20);
        check(tw == LAT, $sformatf("T9a read latency = %0d cycle(s) (measured %0d)", LAT, tw));
        @(negedge clk);
        check(rvalid === 1'b0, "T9b rvalid is a single-cycle pulse");
        idle(4);
        check(rvalid === 1'b0 && ready === 1'b1, "T9c no response while idle, ready=1");
        rc0 = rsp_cnt;
        issue(1'b0, 8*4, 32'h0, 4'h0);
        idle(LAT + 3);
        check(rsp_cnt - rc0 == 1, "T9d exactly one response per accepted request");

        // ---- Test 10: reset during / between transactions ----
        $display("TEST 10: reset during and between transactions");
        wr(40, 32'h1357_9BDF, 4'hF, "T10a write before reset");
        @(negedge clk); rst_n = 1'b0; repeat (2) @(negedge clk); rst_n = 1'b1; idle(2);
        rd(40, 32'h1357_9BDF, "T10b memory contents survive reset");
        // in-flight read at reset
        rc0 = rsp_cnt;
        issue(1'b0, 40*4, 32'h0, 4'h0);
        @(negedge clk); req = 1'b0; rst_n = 1'b0;
        repeat (3) @(negedge clk); rst_n = 1'b1; idle(LAT + 3);
        check(rsp_cnt - rc0 == ((LAT == 1) ? 1 : 0),
              (LAT == 1) ? "T10c LAT=1: response already visible at reset edge is delivered"
                         : "T10c in-flight response dropped by reset");
        // reset during a write stream
        for (int i = 0; i < 4; i++) issue(1'b1, (44+i)*4, 32'hD00D_0000 + i, 4'hF);
        @(negedge clk); rst_n = 1'b0;                       // 5th write presented on the reset edge
        req = 1'b1; we = 1'b1; addr = 48*4; wdata = 32'hBAD0_BAD0; be = 4'hF;
        repeat (2) @(negedge clk);
        req = 1'b0; we = 1'b0; rst_n = 1'b1; idle(LAT + 2);
        okb = 1'b1;
        rd(44, 32'hD00D_0000, "T10d write accepted before reset retained (word 44)");
        rd(47, 32'hD00D_0003, "T10e write accepted before reset retained (word 47)");
        rd(48, 32'h0, "T10f write presented during reset ignored");
        check(sb_err == 0, $sformatf("T10g scoreboard clean through all reset scenarios (%0d mismatches)", sb_err));

        // ---- summary ----
        idle(4);
        check(sb_err == 0, $sformatf("SCOREBOARD: %0d cycles compared, %0d mismatches", sb_cycles, sb_err));
        $display("---------------------------------------------------------------");
        $display("  Directed checks: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0 && sb_err == 0) $display("  REGRESSION RESULT: PASS  (tb_sram_model, LAT=%0d)", LAT);
        else                              $display("  REGRESSION RESULT: FAIL  (tb_sram_model, LAT=%0d)", LAT);
        $finish;
    end

    // global watchdog
    initial begin
        #200000;
        $display("  [FAIL] TIMEOUT: simulation hung");
        $display("  REGRESSION RESULT: FAIL  (tb_sram_model, LAT=%0d)", LAT);
        $finish;
    end

endmodule
