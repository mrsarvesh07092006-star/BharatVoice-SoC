// ============================================================================
// tb_spi_master.sv -- self-checking testbench for spi_master
//
// Contains an edge-accurate SPI SLAVE MODEL (not a loopback):
//   * Samples MOSI only on the sampling edge of the selected CPOL/CPHA mode.
//   * Changes MISO (after a 1 ns clk-to-q) only on the shifting edge.
//   * MISO is driven to X when no valid bit is due (before first leading edge
//     in modes 1/3, after the last bit), so sampling on a wrong edge returns
//     wrong/X data and fails the === comparison.
//   * Records timestamps/edge counts for SCLK frequency, CS setup/hold, done
//     timing checks, and flags MOSI setup (<1 clk) / hold (<1 clk) violations.
// Stimulus is driven at negedge clk and sampled at negedge clk (race-free).
// ============================================================================
`timescale 1ns/1ps

module spi_slave_model #(
    parameter int DATA_W    = 32,
    parameter int MIN_SETUP = 10     // ns: MOSI must be stable this long before sample edge
) (
    input  logic              cs_n,
    input  logic              sclk,
    input  logic              mosi,
    input  logic              cpol,
    input  logic              cpha,
    input  logic [DATA_W-1:0] tx_word,   // response, right-aligned, MSB (bit tx_len-1) first
    input  logic [7:0]        tx_len,
    output logic              miso
);
    logic miso_r = 1'bx;
    assign miso = miso_r;

    logic [DATA_W-1:0] rx_word = '0;
    int  rx_bits = 0, n_edges = 0, n_cs_falls = 0, n_shift = 0;
    int  setup_viol = 0, hold_viol = 0;
    time t_cs_fall = 0, t_cs_rise = 0, t_first_edge = 0, t_last_edge = 0, t_prev_edge = 0;
    time min_half = 0, max_half = 0, t_mosi_chg = 0, t_last_sample = 0;
    bit  first_edge_dir_ok = 1'b0;
    bit  cpol_l = 1'b0, cpha_l = 1'b0;   // mode latched at CS fall (a real slave does not change mode mid-frame)

    always @(negedge cs_n) begin
        cpol_l = cpol; cpha_l = cpha;
        n_cs_falls++; n_edges = 0; rx_bits = 0; rx_word = '0; n_shift = 0;
        t_cs_fall = $time; min_half = 64'hFFFF_FFFF; max_half = 0; first_edge_dir_ok = 1'b0;
        if (!cpha_l) miso_r <= #1 tx_word[tx_len-1];     // mode 0/2: first bit valid at CS fall
        else       miso_r <= #1 1'bx;                  // mode 1/3: not valid until 1st leading edge
    end

    always @(posedge cs_n) begin
        t_cs_rise = $time;
        miso_r <= #1 1'bx;
    end

    always @(mosi) begin
        if (cs_n === 1'b0 && ($time - t_last_sample) < MIN_SETUP) hold_viol++;
        t_mosi_chg = $time;
    end

    always @(sclk) if (cs_n === 1'b0) begin : edge_proc
        bit lead;
        int cur;
        n_edges++;
        if (n_edges == 1) begin
            t_first_edge = $time;
            first_edge_dir_ok = (sclk === ~cpol_l);
        end else begin
            if (($time - t_prev_edge) < min_half) min_half = $time - t_prev_edge;
            if (($time - t_prev_edge) > max_half) max_half = $time - t_prev_edge;
        end
        t_prev_edge = $time; t_last_edge = $time;
        lead = (sclk !== cpol_l);
        if (lead ^ cpha_l) begin                       // SAMPLE edge
            if (($time - t_mosi_chg) < MIN_SETUP) setup_viol++;
            t_last_sample = $time;
            rx_word = {rx_word[DATA_W-2:0], mosi};
            rx_bits++;
        end else begin                               // SHIFT edge
            if (!cpha_l) begin n_shift++; cur = tx_len - 1 - n_shift; end
            else       begin cur = tx_len - 1 - n_shift; n_shift++; end
            if (cur >= 0) miso_r <= #1 tx_word[cur];
            else          miso_r <= #1 1'bx;
        end
    end
endmodule


module tb_spi_master;

    localparam int DATA_W    = 32;
    localparam int CLK_DIV_W = 16;
    localparam int LEN_W     = $clog2(DATA_W+1);
    localparam int T         = 10;               // clk period in ns

    logic clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    logic                 start = 1'b0;
    logic [DATA_W-1:0]    tx_data = '0;
    logic [LEN_W-1:0]     xfer_len = '0;
    logic [CLK_DIV_W-1:0] clk_div = 16'd1;
    logic                 cpol = 1'b0, cpha = 1'b0;
    wire                  busy, done, err_cfg, err_busy, sclk, mosi, cs_n, miso;
    wire [DATA_W-1:0]     rx_data;
    logic [DATA_W-1:0]    slave_tx = '0;
    logic [7:0]           slave_len = 8'd8;

    spi_master #(.DATA_W(DATA_W), .CLK_DIV_W(CLK_DIV_W)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .tx_data(tx_data), .xfer_len(xfer_len),
        .clk_div(clk_div), .cpol(cpol), .cpha(cpha), .busy(busy), .done(done),
        .err_cfg(err_cfg), .err_busy(err_busy), .rx_data(rx_data),
        .sclk(sclk), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    spi_slave_model #(.DATA_W(DATA_W)) u_slave (
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .cpol(cpol), .cpha(cpha),
        .tx_word(slave_tx), .tx_len(slave_len), .miso(miso)
    );

    // ---------------- counters / monitors ----------------
    int pass_cnt = 0, fail_cnt = 0, sub_fail = 0;
    int done_cnt = 0, errc_cnt = 0, errb_cnt = 0, busy_rise_cnt = 0;
    int done_w_bad = 0, errc_w_bad = 0, errb_w_bad = 0;
    time t_done_r = 0, t_busy_r = 0, t_busy_f = 0, t_errc_r = 0, t_errb_r = 0;
    // snapshots taken before each transfer
    int s_falls = 0, s_viol = 0, s_errc = 0, s_errb = 0, s_done = 0;

    always @(posedge done)    begin done_cnt++;  t_done_r = $time; end
    always @(negedge done)    if (done_cnt > 0)  if (($time - t_done_r) != T) done_w_bad++;
    always @(posedge err_cfg) begin errc_cnt++;  t_errc_r = $time; end
    always @(negedge err_cfg) if (errc_cnt > 0)  if (($time - t_errc_r) != T) errc_w_bad++;
    always @(posedge err_busy) begin errb_cnt++; t_errb_r = $time; end
    always @(negedge err_busy) if (errb_cnt > 0) if (($time - t_errb_r) != T) errb_w_bad++;
    always @(posedge busy)    begin busy_rise_cnt++; t_busy_r = $time; end
    always @(negedge busy)    t_busy_f = $time;

    // ---------------- helpers ----------------
    task automatic check(input bit cond, input string msg);
        if (cond) begin pass_cnt++; $display("  [PASS] %s", msg); end
        else      begin fail_cnt++; $display("  [FAIL] %s  (t=%0t)", msg, $time); end
    endtask

    task automatic sub(input bit cond, input string what);
        if (!cond) begin sub_fail++; $display("      mismatch: %s", what); end
    endtask

    function automatic [31:0] mask(input int len);
        mask = (len >= 32) ? 32'hFFFF_FFFF : ((32'd1 << len) - 32'd1);
    endfunction

    function automatic [31:0] xs32(input [31:0] x);
        logic [31:0] y;
        begin y = x; y = y ^ (y << 13); y = y ^ (y >> 17); y = y ^ (y << 5); xs32 = y; end
    endfunction

    task automatic snap;
        begin
            s_falls = u_slave.n_cs_falls; s_viol = u_slave.setup_viol + u_slave.hold_viol;
            s_errc = errc_cnt; s_errb = errb_cnt; s_done = done_cnt;
        end
    endtask

    // set configuration (at negedge), settle 3 cycles so SCLK idle follows cpol, snapshot
    task automatic cfg(input bit cpol_i, input bit cpha_i, input int len, input int div,
                       input [31:0] tx, input [31:0] stx);
        begin
            @(negedge clk);
            cpol = cpol_i; cpha = cpha_i; clk_div = div; xfer_len = len;
            tx_data = tx; slave_tx = stx; slave_len = len;
            repeat (3) @(negedge clk);
            snap;
        end
    endtask

    task automatic go;   // one-cycle start pulse (we are at a negedge)
        begin start = 1'b1; @(negedge clk); start = 1'b0; end
    endtask

    // wait (bounded) for done; returns at the negedge where done==1
    task automatic wait_done(input int len, input int div, output bit got);
        int tmo, limit;
        begin
            got = 1'b0; tmo = 0; limit = (2*len + 4)*div + 20;
            while (!got && tmo < limit) begin
                if (done === 1'b1) got = 1'b1;
                else begin @(negedge clk); tmo++; end
            end
        end
    endtask

    // check everything about a completed transfer (call at the negedge where done==1)
    task automatic verify(input bit cpol_i, input bit cpha_i, input int len, input int div,
                          input [31:0] tx, input [31:0] stx, input string name);
        logic [31:0] expm, exps;
        begin
            sub_fail = 0; exps = stx & mask(len); expm = tx & mask(len);
            sub(rx_data === exps, $sformatf("rx_data got %h exp %h", rx_data, exps));
            sub(busy === 1'b0 && cs_n === 1'b1, "busy=0 and cs_n=1 at done");
            sub(sclk === cpol_i, "SCLK returned to idle level (cpol)");
            sub(mosi === 1'b0, "MOSI idle 0 after transfer");
            sub(u_slave.rx_word === expm, $sformatf("slave got %h exp %h", u_slave.rx_word, expm));
            sub(u_slave.rx_bits == len, $sformatf("sampled bits %0d exp %0d", u_slave.rx_bits, len));
            sub(u_slave.n_edges == 2*len, $sformatf("SCLK edges %0d exp %0d", u_slave.n_edges, 2*len));
            sub(u_slave.n_cs_falls == s_falls + 1, "exactly one CS assertion");
            sub(u_slave.first_edge_dir_ok, "first SCLK edge leaves the CPOL idle level");
            sub(u_slave.min_half == div*T && u_slave.max_half == div*T,
                $sformatf("SCLK half-period %0d..%0d ns exp %0d", u_slave.min_half, u_slave.max_half, div*T));
            sub((u_slave.t_first_edge - u_slave.t_cs_fall) == div*T, "CS setup = clk_div cycles");
            sub((u_slave.t_cs_rise - u_slave.t_last_edge) == div*T, "CS hold = clk_div cycles");
            sub(t_done_r == u_slave.t_cs_rise, "done rises with cs_n");
            sub((t_done_r - u_slave.t_cs_fall) == (2*len + 1)*div*T,
                $sformatf("completion time %0d ns exp %0d", t_done_r - u_slave.t_cs_fall, (2*len+1)*div*T));
            sub(t_busy_r == u_slave.t_cs_fall && t_busy_f == t_done_r, "busy spans cs_n low");
            sub(done_cnt == s_done + 1, "exactly one done pulse");
            sub(errc_cnt == s_errc && errb_cnt == s_errb, "no error pulses");
            sub((u_slave.setup_viol + u_slave.hold_viol) == s_viol, "no MOSI setup/hold violations");
            check(sub_fail == 0, name);
        end
    endtask

    task automatic run_xfer(input bit cpol_i, input bit cpha_i, input int len, input int div,
                            input [31:0] tx, input [31:0] stx, input string name);
        bit got;
        begin
            cfg(cpol_i, cpha_i, len, div, tx, stx);
            sub_fail = 0;
            sub(cs_n === 1'b1 && busy === 1'b0 && done === 1'b0 && sclk === cpol_i, "idle before start");
            go;
            sub(busy === 1'b1 && cs_n === 1'b0, "busy=1, cs_n=0 right after start");
            wait_done(len, div, got);
            if (!got) begin
                check(1'b0, {name, " -- TIMEOUT/DEADLOCK: done never asserted"});
            end else begin
                if (sub_fail != 0) check(1'b0, {name, " -- start handshake"});
                verify(cpol_i, cpha_i, len, div, tx, stx, name);
            end
        end
    endtask

    // ---------------- main ----------------
    bit got, got2;
    int rc;
    logic [31:0] seed, r1, r2, r3, tA, sA, tB, sB;
    time t_riseA;
    int mlen, mdiv;
    bit [1:0] md;

    initial begin : main
        $display("=== tb_spi_master (DATA_W=%0d, CLK_DIV_W=%0d, Tclk=%0d ns) ===", DATA_W, CLK_DIV_W, T);

        // ---- Test 1: reset and idle states ----
        $display("TEST 1: reset and idle output states");
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        check(cs_n === 1'b1 && sclk === 1'b0 && mosi === 1'b0 && busy === 1'b0 && done === 1'b0 &&
              err_cfg === 1'b0 && err_busy === 1'b0 && rx_data === 32'h0,
              "T1a all outputs idle during reset (cs_n=1,sclk=0,mosi=0,busy=0,done=0,err=0,rx=0)");
        rst_n = 1'b1;
        repeat (3) @(negedge clk);
        check(cs_n === 1'b1 && sclk === 1'b0 && mosi === 1'b0 && busy === 1'b0 && done === 1'b0,
              "T1b idle after reset release, no spontaneous activity");
        cpol = 1'b1; repeat (2) @(negedge clk);
        check(sclk === 1'b1 && cs_n === 1'b1, "T1c SCLK idle level follows CPOL=1 while idle");
        cpol = 1'b0; repeat (2) @(negedge clk);
        check(sclk === 1'b0, "T1d SCLK idle level back to 0 for CPOL=0");

        // ---- Test 2: known TX byte, MSB first (0x9C is not a palindrome) ----
        $display("TEST 2: known TX byte MSB-first (upper tx_data bits are garbage)");
        run_xfer(0, 0, 8, 2, 32'hFFFF_FF9C, 32'h0, "T2 TX 0x9C MSB-first, mode 0, div 2");

        // ---- Test 3: known RX byte ----
        $display("TEST 3: known RX byte");
        run_xfer(0, 0, 8, 2, 32'h0, 32'h6B, "T3 RX 0x6B, mode 0, div 2");

        // ---- Test 4: full duplex, all modes ----
        $display("TEST 4: simultaneous full duplex");
        run_xfer(0, 0, 16, 2, 32'hB2D5, 32'h4F69, "T4 full duplex 16 bit mode 0");
        run_xfer(0, 1, 16, 2, 32'hB2D5, 32'h4F69, "T4 full duplex 16 bit mode 1");
        run_xfer(1, 0, 16, 2, 32'hB2D5, 32'h4F69, "T4 full duplex 16 bit mode 2");
        run_xfer(1, 1, 16, 2, 32'hB2D5, 32'h4F69, "T4 full duplex 16 bit mode 3");

        // ---- Test 5: SCLK frequency for several dividers ----
        $display("TEST 5: SCLK frequency vs clk_div (f_sclk = f_clk/(2*clk_div))");
        for (int k = 0; k < 5; k++) begin
            mdiv = (k == 0) ? 1 : (k == 1) ? 2 : (k == 2) ? 3 : (k == 3) ? 5 : 8;
            run_xfer(0, 0, 8, mdiv, 32'hD2, 32'h35, $sformatf("T5 clk_div=%0d transfer", mdiv));
            check(2*u_slave.max_half == 2*mdiv*T && u_slave.min_half == mdiv*T,
                  $sformatf("T5 SCLK period = %0d ns (= 2*%0d*%0d)", 2*u_slave.max_half, mdiv, T));
        end

        // ---- Test 6: CPOL/CPHA, different lengths ----
        $display("TEST 6: CPOL/CPHA modes 0..3");
        for (int m = 0; m < 4; m++) begin
            md = m;
            run_xfer(md[1], md[0], 8,  1, 32'hA3,   32'h5C,   $sformatf("T6 mode %0d len 8 div 1", m));
            run_xfer(md[1], md[0], 13, 3, 32'h1ACE, 32'h0D95, $sformatf("T6 mode %0d len 13 div 3", m));
        end

        // ---- Test 7: chip-select behaviour ----
        $display("TEST 7: chip select");
        run_xfer(0, 1, 8, 2, 32'h96, 32'h2B, "T7 transfer for CS checks");
        check((u_slave.t_cs_rise - u_slave.t_cs_fall) == 17*2*T, "T7a cs_n low for exactly (2N+1)*div cycles");
        check(cs_n === 1'b1, "T7b cs_n deasserted after completion");

        // ---- Test 8: completion timing ----
        $display("TEST 8: completion timing");
        run_xfer(1, 0, 11, 3, 32'h5A3, 32'h2D1, "T8 len 11 div 3");
        check((t_done_r - u_slave.t_cs_fall) == 23*3*T, "T8a done at A0 + (2N+1)*div*Tclk = 690 ns");
        check((t_busy_f - t_busy_r) == (t_done_r - u_slave.t_cs_fall), "T8b busy high exactly during the transfer");

        // ---- Test 9: consecutive transfers ----
        $display("TEST 9: consecutive independent transfers");
        run_xfer(0, 0, 8,  2, 32'h11, 32'hEE, "T9a #1 mode 0 len 8");
        run_xfer(1, 1, 16, 1, 32'hCAFE, 32'h1234, "T9b #2 mode 3 len 16");
        run_xfer(0, 1, 5,  4, 32'h15, 32'h0A, "T9c #3 mode 1 len 5");
        run_xfer(1, 0, 32, 1, 32'hDEADBEEF, 32'h01234567, "T9d #4 mode 2 len 32");
        // tightest back-to-back: start asserted in the cycle where done=1
        tA = 32'h00A7; sA = 32'h003D; tB = 32'h5E1C; sB = 32'hB07A;
        cfg(0, 0, 8, 2, tA, sA);
        go;
        wait_done(8, 2, got);
        check(got, "T9e first of back-to-back completed");
        if (got) begin
            verify(0, 0, 8, 2, tA, sA, "T9e transfer A verified");
            t_riseA = u_slave.t_cs_rise;
            snap;
            xfer_len = 16; clk_div = 3; tx_data = tB; slave_tx = sB; slave_len = 16;  // same cpol/cpha
            start = 1'b1; @(negedge clk); start = 1'b0;
            wait_done(16, 3, got2);
            check(got2, "T9f second of back-to-back completed");
            if (got2) verify(0, 0, 16, 3, tB, sB, "T9f transfer B (started in done cycle) verified");
            check((u_slave.t_cs_fall - t_riseA) == T, "T9g cs_n high exactly 1 clk between back-to-back transfers");
        end

        // ---- Test 10: start while busy ----
        $display("TEST 10: start asserted while busy");
        cfg(0, 0, 16, 3, 32'hA55A, 32'h3C69);
        go;
        repeat (10) @(negedge clk);
        check(busy === 1'b1, "T10a transfer in progress");
        // disturb every config input and pulse start
        tx_data = 32'hFFFF_FFFF; xfer_len = 4; clk_div = 1; cpha = 1'b1;
        start = 1'b1; @(negedge clk); start = 1'b0;
        check(errb_cnt == s_errb + 1, "T10b err_busy pulsed once");
        s_errb = errb_cnt;     // expected pulse; exclude from the no-error check in verify()
        wait_done(16, 3, got);
        check(got, "T10c original transfer still completes");
        if (got) verify(0, 0, 16, 3, 32'hA55A, 32'h3C69, "T10d original transfer unaffected (data,len,div,mode)");
        repeat (20) @(negedge clk);
        check(u_slave.n_cs_falls == s_falls + 1 && cs_n === 1'b1 && busy === 1'b0,
              "T10e ignored start did not queue a new transfer");

        // ---- Test 11: reset during active transfer ----
        $display("TEST 11: reset during active transfer");
        cfg(0, 0, 16, 2, 32'hF0F0, 32'h0FF0);
        go;
        repeat (20) @(negedge clk);
        check(busy === 1'b1 && cs_n === 1'b0, "T11a transfer active before reset");
        rst_n = 1'b0; #1;
        check(cs_n === 1'b1 && busy === 1'b0 && done === 1'b0 && sclk === 1'b0 && mosi === 1'b0,
              "T11b asynchronous reset: cs_n=1,busy=0,done=0,sclk=0,mosi=0 immediately");
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);
        check(rx_data === 32'h0 && u_slave.rx_bits < 16 && done_cnt == s_done, "T11c transfer abandoned: truncated frame, rx cleared, no done pulse");
        check(cs_n === 1'b1 && busy === 1'b0, "T11d idle after reset");
        run_xfer(1, 1, 12, 2, 32'h0B5E, 32'h0A9C, "T11e new transfer after reset works (no extra reset needed afterwards)");
        run_xfer(0, 0, 12, 2, 32'h0B5E, 32'h0A9C, "T11f repeated transfer works");

        // ---- Test 12: invalid configuration ----
        $display("TEST 12: invalid transfer configuration");
        for (int k = 0; k < 5; k++) begin
            mlen = (k == 0) ? 0 : (k == 1) ? 33 : (k == 2) ? 63 : (k == 3) ? 8 : 0;
            mdiv = (k == 3 || k == 4) ? 0 : 2;
            cfg(0, 0, mlen, mdiv, 32'h55, 32'h0);
            rc = busy_rise_cnt;
            go;
            repeat (5) @(negedge clk);
            check(errc_cnt == s_errc + 1 && busy_rise_cnt == rc && done_cnt == s_done &&
                  u_slave.n_cs_falls == s_falls && cs_n === 1'b1 && busy === 1'b0,
                  $sformatf("T12 len=%0d clk_div=%0d rejected: err_cfg pulse, no CS, no busy, no done", mlen, mdiv));
        end
        run_xfer(0, 0, 8, 2, 32'h77, 32'h88, "T12f valid transfer after rejected starts");

        // ---- Test 13: minimum / maximum length ----
        $display("TEST 13: minimum (1 bit) and maximum (32 bit) length");
        for (int m = 0; m < 4; m++) begin
            md = m;
            run_xfer(md[1], md[0], 1, 2, 32'h1, 32'h0, $sformatf("T13 mode %0d len 1 tx=1 rx=0", m));
            run_xfer(md[1], md[0], 1, 1, 32'h0, 32'h1, $sformatf("T13 mode %0d len 1 tx=0 rx=1", m));
            run_xfer(md[1], md[0], 32, 1, 32'h9ABCDEF1, 32'h87654321, $sformatf("T13 mode %0d len 32", m));
        end

        // ---- Test 14: deadlock detection / random regression ----
        $display("TEST 14: deadlock detection + random regression (every transfer bounded by timeout)");
        seed = 32'hC0FF_EE01;
        for (int n = 0; n < 40; n++) begin
            seed = xs32(seed); r1 = seed;
            seed = xs32(seed); r2 = seed;
            seed = xs32(seed); r3 = seed;
            md = r1[1:0]; mlen = 1 + (r1[7:2] % 32); mdiv = 1 + (r1[10:8] % 4);
            run_xfer(md[1], md[0], mlen, mdiv, r2, r3,
                     $sformatf("T14.%0d mode %0d len %0d div %0d", n, md, mlen, mdiv));
        end
        check(busy === 1'b0 && cs_n === 1'b1, "T14z core not stuck busy after regression");

        // ---- global pulse-width checks ----
        check(done_w_bad == 0 && errc_w_bad == 0 && errb_w_bad == 0,
              "done / err_cfg / err_busy were always exactly 1 clk wide");

        $display("---------------------------------------------------------------");
        $display("  Checks: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("  REGRESSION RESULT: PASS  (tb_spi_master)");
        else               $display("  REGRESSION RESULT: FAIL  (tb_spi_master)");
        $finish;
    end

    // global watchdog
    initial begin
        #5_000_000;
        $display("  [FAIL] TIMEOUT: simulation hung");
        $display("  REGRESSION RESULT: FAIL  (tb_spi_master)");
        $finish;
    end

endmodule
