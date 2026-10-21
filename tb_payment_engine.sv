// =============================================================================
// BharatVoice SoC — Payment Processing Engine Testbench
// File   : tb_payment_engine.sv
// Author : Sarvesh (Lead Designer)
// Date   : 2026-10-16
// Rev    : 1.1
//
// Description:
//   Comprehensive, self-checking SystemVerilog testbench for payment_engine.sv.
//   Verifies framing, CRC integrity, bounds checking, anti-duplicate logic,
//   OBI register access, interrupts, and back-to-back stream handling.
// =============================================================================

`timescale 1ns/1ps

module tb_payment_engine;

    // Clock and Reset signals
    logic        clk;
    logic        rst_n;

    // OBI slave bus interface
    logic        req;
    logic        gnt;
    logic [31:0] addr;
    logic        we;
    logic [ 3:0] be;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        rvalid;
    logic        err;

    // UART byte stream
    logic [ 7:0] uart_data;
    logic        uart_valid;

    // Dedicated outputs to Audio Engine
    logic [31:0] amount;
    logic        txn_valid;

    // Interrupts
    logic        irq_done;
    logic        irq_fail;

    // Testbench tracking
    int pass_count = 0;
    int fail_count = 0;

    // Clock Generation: 50 MHz (20 ns period)
    initial clk = 0;
    always #10 clk = ~clk;

    // Instantiate Device Under Test (DUT)
    payment_engine #(
        .DEFAULT_MAX_AMOUNT (32'd1000000) // 1,000,000 paise = Rs 10,000.00
    ) dut (
        .clk_i        (clk),
        .rst_ni       (rst_n),
        .req_i        (req),
        .gnt_o        (gnt),
        .addr_i       (addr),
        .we_i         (we),
        .be_i         (be),
        .wdata_i      (wdata),
        .rdata_o      (rdata),
        .rvalid_o     (rvalid),
        .err_o        (err),
        .uart_data_i  (uart_data),
        .uart_valid_i (uart_valid),
        .amount_o     (amount),
        .txn_valid_o  (txn_valid),
        .irq_done_o   (irq_done),
        .irq_fail_o   (irq_fail)
    );

    // =========================================================================
    // Helper Functions & Tasks
    // =========================================================================
    function automatic [15:0] calc_crc16(
        input [7:0]  ver_len,
        input [31:0] id,
        input [31:0] amt,
        input [7:0]  flg
    );
        logic [15:0] c;
        logic [7:0]  bytes [0:9];

        bytes[0] = ver_len;
        bytes[1] = id[31:24];
        bytes[2] = id[23:16];
        bytes[3] = id[15:8];
        bytes[4] = id[7:0];
        bytes[5] = amt[31:24];
        bytes[6] = amt[23:16];
        bytes[7] = amt[15:8];
        bytes[8] = amt[7:0];
        bytes[9] = flg;

        c = 16'hFFFF;
        for (int b = 0; b < 10; b++) begin
            c = c ^ ({bytes[b], 8'h00});
            for (int i = 0; i < 8; i++) begin
                if (c[15])
                    c = (c << 1) ^ 16'h1021;
                else
                    c = (c << 1);
            end
        end
        return c;
    endfunction

    // Send single UART byte
    task automatic send_uart_byte(input [7:0] b);
        @(posedge clk);
        uart_data  <= b;
        uart_valid <= 1'b1;
        @(posedge clk);
        uart_valid <= 1'b0;
    endtask

    // Send entire 14-byte frame
    task automatic send_frame(
        input [7:0]  sof_byte,
        input [7:0]  ver_len_byte,
        input [31:0] id,
        input [31:0] amt,
        input [7:0]  flags,
        input [15:0] crc,
        input [7:0]  eof_byte
    );
        send_uart_byte(sof_byte);
        send_uart_byte(ver_len_byte);
        send_uart_byte(id[31:24]);
        send_uart_byte(id[23:16]);
        send_uart_byte(id[15:8]);
        send_uart_byte(id[7:0]);
        send_uart_byte(amt[31:24]);
        send_uart_byte(amt[23:16]);
        send_uart_byte(amt[15:8]);
        send_uart_byte(amt[7:0]);
        send_uart_byte(flags);
        send_uart_byte(crc[15:8]);
        send_uart_byte(crc[7:0]);
        send_uart_byte(eof_byte);
    endtask

    // OBI Register Read
    task automatic obi_read(input [31:0] reg_addr, output [31:0] data_out);
        @(posedge clk);
        req   <= 1'b1;
        we    <= 1'b0;
        be    <= 4'b1111;
        addr  <= reg_addr;
        wdata <= 32'd0;
        @(posedge clk);
        req   <= 1'b0;
        while (!rvalid) @(posedge clk);
        #1;
        data_out = rdata;
    endtask

    // OBI Register Write
    task automatic obi_write(input [31:0] reg_addr, input [31:0] data_in, input [3:0] byte_en = 4'b1111);
        @(posedge clk);
        req   <= 1'b1;
        we    <= 1'b1;
        be    <= byte_en;
        addr  <= reg_addr;
        wdata <= data_in;
        @(posedge clk);
        req   <= 1'b0;
        while (!rvalid) @(posedge clk);
    endtask

    // Assertion check macro
    task automatic check(input string test_name, input logic condition);
        if (condition) begin
            $display("  [PASS] %s", test_name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s", test_name);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    logic [31:0] read_reg;
    logic [15:0] good_crc;

    initial begin
        $display("=== tb_payment_engine: Starting Test Suite ===");
        uart_data  = 8'h00;
        uart_valid = 1'b0;
        req        = 1'b0;
        we         = 1'b0;
        be         = 4'h0;
        addr       = 32'h0;
        wdata      = 32'h0;

        // ---------------------------------------------------------------------
        // TEST 1: Reset Behavior & Output States
        // ---------------------------------------------------------------------
        $display("TEST 1: Reset behavior and idle states");
        rst_n = 1'b0;
        #50;
        @(posedge clk);
        #1;
        check("T1a: amount_o is 0 during reset", amount === 32'd0);
        check("T1b: txn_valid_o is 0 during reset", txn_valid === 1'b0);
        check("T1c: irq_done_o is 0 during reset", irq_done === 1'b0);
        check("T1d: irq_fail_o is 0 during reset", irq_fail === 1'b0);

        @(posedge clk);
        rst_n = 1'b1;
        #40;
        @(posedge clk);

        obi_read(32'h4000_0000, read_reg); // TXN_CTRL
        check("T1e: TXN_CTRL default enabled (bit[0]=1, bit[2]=1)", read_reg === 32'h0000_0005);
        obi_read(32'h4000_0004, read_reg); // TXN_STATUS
        check("T1f: TXN_STATUS idle and clean", read_reg === 32'd0);
        obi_read(32'h4000_001C, read_reg); // TXN_MAX_AMOUNT
        check("T1g: TXN_MAX_AMOUNT default 1,000,000 paise", read_reg === 32'd1000000);

        // ---------------------------------------------------------------------
        // TEST 2: Valid Single Transaction (e.g. ₹500.00 = 50,000 paise)
        // ---------------------------------------------------------------------
        $display("TEST 2: Valid single transaction reception and commit");
        good_crc = calc_crc16(8'h18, 32'd101, 32'd50000, 8'h01);
        send_frame(8'hAA, 8'h18, 32'd101, 32'd50000, 8'h01, good_crc, 8'h55);

        // EOF was presented at posedge clk. In the next cycle, commit occurs:
        #1;
        check("T2a: amount_o output matches committed 50,000 paise", amount === 32'd50000);
        check("T2b: txn_valid_o pulsed high for audio engine", txn_valid === 1'b1);
        check("T2c: irq_done_o pulsed high", irq_done === 1'b1);

        @(posedge clk);
        #1;
        check("T2d: txn_valid_o de-asserted next cycle (single pulse)", txn_valid === 1'b0);
        check("T2e: irq_done_o de-asserted next cycle (single pulse)", irq_done === 1'b0);

        obi_read(32'h4000_0004, read_reg); // TXN_STATUS
        check("T2f: TXN_STATUS indicates valid transaction (bit[0]=1)", read_reg[0] === 1'b1);
        obi_read(32'h4000_0008, read_reg); // TXN_AMOUNT
        check("T2g: TXN_AMOUNT register holds 50,000 paise", read_reg === 32'd50000);
        obi_read(32'h4000_000C, read_reg); // TXN_ID
        check("T2h: TXN_ID register holds 101", read_reg === 32'd101);
        obi_read(32'h4000_0018, read_reg); // TXN_ERR_CODE
        check("T2i: TXN_ERR_CODE is ERR_NONE", read_reg === 32'd0);

        // ---------------------------------------------------------------------
        // TEST 3: Multiple Sequential Valid Transactions
        // ---------------------------------------------------------------------
        $display("TEST 3: Sequential valid transactions with distinct IDs & amounts");
        good_crc = calc_crc16(8'h18, 32'd102, 32'd1250, 8'h01); // Rs 12.50
        send_frame(8'hAA, 8'h18, 32'd102, 32'd1250, 8'h01, good_crc, 8'h55);
        #1;
        check("T3a: txn_valid_o asserted for txn 102", txn_valid === 1'b1);
        check("T3b: amount_o updated to 1250 paise", amount === 32'd1250);

        #30;
        good_crc = calc_crc16(8'h18, 32'd103, 32'd99900, 8'h01); // Rs 999.00
        send_frame(8'hAA, 8'h18, 32'd103, 32'd99900, 8'h01, good_crc, 8'h55);
        #1;
        check("T3c: txn_valid_o asserted for txn 103", txn_valid === 1'b1);
        check("T3d: amount_o updated to 99900 paise", amount === 32'd99900);

        // ---------------------------------------------------------------------
        // TEST 4: Integrity / CRC Corruption (Corrupted Payload)
        // ---------------------------------------------------------------------
        $display("TEST 4: CRC mismatch / corrupted payload");
        good_crc = calc_crc16(8'h18, 32'd104, 32'd25000, 8'h01);
        // Corrupt CRC by inverting bits
        send_frame(8'hAA, 8'h18, 32'd104, 32'd25000, 8'h01, ~good_crc, 8'h55);
        #1;
        check("T4a: txn_valid_o is 0 on CRC error (NO audio trigger)", txn_valid === 1'b0);
        check("T4b: irq_fail_o pulsed high", irq_fail === 1'b1);
        obi_read(32'h4000_0004, read_reg); // TXN_STATUS
        check("T4c: TXN_STATUS indicates fail (bit[1]=1) & crc_err (bit[4]=1)", (read_reg[1] === 1'b1) && (read_reg[4] === 1'b1));
        obi_read(32'h4000_0018, read_reg); // TXN_ERR_CODE
        check("T4d: TXN_ERR_CODE indicates ERR_CRC (0x03)", read_reg[7:0] === 8'h03);
        obi_read(32'h4000_0008, read_reg); // TXN_AMOUNT
        check("T4e: Committed amount was NOT overwritten by bad txn", read_reg === 32'd99900);

        // ---------------------------------------------------------------------
        // TEST 5: Framing Violations
        // ---------------------------------------------------------------------
        $display("TEST 5: Framing violations (bad SOF, bad VER_LEN, bad EOF)");
        #30;
        // 5a: Bad VER_LEN (0x20 instead of 0x18)
        good_crc = calc_crc16(8'h20, 32'd105, 32'd5000, 8'h01);
        send_frame(8'hAA, 8'h20, 32'd105, 32'd5000, 8'h01, good_crc, 8'h55);
        #1;
        // In bad VER_LEN, failure triggers right at VER_LEN byte!
        obi_read(32'h4000_0018, read_reg);
        check("T5a: TXN_ERR_CODE is ERR_VER_LEN (0x02)", read_reg[7:0] === 8'h02);

        #30;
        // 5b: Bad EOF (0x66 instead of 0x55)
        good_crc = calc_crc16(8'h18, 32'd106, 32'd5000, 8'h01);
        send_frame(8'hAA, 8'h18, 32'd106, 32'd5000, 8'h01, good_crc, 8'h66);
        #1;
        check("T5b: bad EOF triggers irq_fail_o", irq_fail === 1'b1);
        obi_read(32'h4000_0018, read_reg);
        check("T5c: TXN_ERR_CODE is ERR_EOF (0x04)", read_reg[7:0] === 8'h04);

        // ---------------------------------------------------------------------
        // TEST 6: Amount Bounds Validation (Zero & Over-limit)
        // ---------------------------------------------------------------------
        $display("TEST 6: Amount bounds checking (zero & max_amount exceeded)");
        #30;
        // 6a: Zero amount (0 paise)
        good_crc = calc_crc16(8'h18, 32'd107, 32'd0, 8'h01);
        send_frame(8'hAA, 8'h18, 32'd107, 32'd0, 8'h01, good_crc, 8'h55);
        #1;
        check("T6a: zero amount rejected, txn_valid_o is 0", txn_valid === 1'b0);
        check("T6b: zero amount triggers irq_fail_o", irq_fail === 1'b1);
        obi_read(32'h4000_0018, read_reg);
        check("T6c: TXN_ERR_CODE is ERR_ZERO_AMT (0x05)", read_reg[7:0] === 8'h05);

        #30;
        // 6b: Amount exceeding limit (1,500,000 paise > 1,000,000 paise default)
        good_crc = calc_crc16(8'h18, 32'd108, 32'd1500000, 8'h01);
        send_frame(8'hAA, 8'h18, 32'd108, 32'd1500000, 8'h01, good_crc, 8'h55);
        #1;
        check("T6d: excessive amount rejected", txn_valid === 1'b0);
        check("T6e: excessive amount triggers irq_fail_o", irq_fail === 1'b1);
        obi_read(32'h4000_0018, read_reg);
        check("T6f: TXN_ERR_CODE is ERR_MAX_AMT (0x06)", read_reg[7:0] === 8'h06);

        // ---------------------------------------------------------------------
        // TEST 7: Duplicate Transaction Detection
        // ---------------------------------------------------------------------
        $display("TEST 7: Duplicate transaction handling");
        #30;
        // Commit txn 200
        good_crc = calc_crc16(8'h18, 32'd200, 32'd4200, 8'h01);
        send_frame(8'hAA, 8'h18, 32'd200, 32'd4200, 8'h01, good_crc, 8'h55);
        #1;
        check("T7a: initial txn 200 accepted", txn_valid === 1'b1);

        #30;
        // Resend identical txn 200 (duplicate)
        send_frame(8'hAA, 8'h18, 32'd200, 32'd4200, 8'h01, good_crc, 8'h55);
        #1;
        check("T7b: duplicate txn 200 rejected (txn_valid_o=0)", txn_valid === 1'b0);
        check("T7c: duplicate triggers irq_fail_o", irq_fail === 1'b1);
        obi_read(32'h4000_0004, read_reg);
        check("T7d: TXN_STATUS bit[3] duplicate flag set", read_reg[3] === 1'b1);
        obi_read(32'h4000_0018, read_reg);
        check("T7e: TXN_ERR_CODE is ERR_DUPLICATE (0x07)", read_reg[7:0] === 8'h07);

        #30;
        // Disable duplicate protection via register and retry
        obi_write(32'h4000_0000, 32'h0000_0001); // bit[2]=0 (allow duplicate)
        send_frame(8'hAA, 8'h18, 32'd200, 32'd4200, 8'h01, good_crc, 8'h55);
        #1;
        check("T7f: duplicate accepted when block_duplicates is disabled", txn_valid === 1'b1);

        // Re-enable duplicate protection
        obi_write(32'h4000_0000, 32'h0000_0005);

        // ---------------------------------------------------------------------
        // TEST 8: OBI Register Writes & RW1C Interrupt Clearing
        // ---------------------------------------------------------------------
        $display("TEST 8: OBI register writes & RW1C interrupt clearing");
        #30;
        // Check pending IRQ bits in TXN_IRQ_STATUS
        obi_read(32'h4000_0014, read_reg);
        check("T8a: TXN_IRQ_STATUS has pending bits set", read_reg[0] === 1'b1);

        // Write 1 to clear pending IRQ bits
        obi_write(32'h4000_0014, 32'h0000_0003);
        obi_read(32'h4000_0014, read_reg);
        check("T8b: TXN_IRQ_STATUS successfully cleared to 0 via RW1C", read_reg === 32'd0);

        // Update MAX_AMOUNT register to 2,000,000 paise (Rs 20,000.00)
        obi_write(32'h4000_001C, 32'd2000000);
        obi_read(32'h4000_001C, read_reg);
        check("T8c: TXN_MAX_AMOUNT updated to 2,000,000 paise", read_reg === 32'd2000000);

        // Send previously rejected amount (1,500,000 paise) -> Now should be accepted!
        good_crc = calc_crc16(8'h18, 32'd300, 32'd1500000, 8'h01);
        send_frame(8'hAA, 8'h18, 32'd300, 32'd1500000, 8'h01, good_crc, 8'h55);
        #1;
        check("T8d: 1,500,000 paise accepted under new higher MAX_AMOUNT threshold", txn_valid === 1'b1);

        // ---------------------------------------------------------------------
        // TEST 9: Back-to-Back Stream (Zero cycle inter-frame gap)
        // ---------------------------------------------------------------------
        $display("TEST 9: Back-to-back stream with zero inter-frame gap");
        good_crc = calc_crc16(8'h18, 32'd401, 32'd7500, 8'h01);
        send_frame(8'hAA, 8'h18, 32'd401, 32'd7500, 8'h01, good_crc, 8'h55);
        // Immediately start next frame in next cycle
        good_crc = calc_crc16(8'h18, 32'd402, 32'd8500, 8'h01);
        send_frame(8'hAA, 8'h18, 32'd402, 32'd8500, 8'h01, good_crc, 8'h55);
        #1;
        check("T9a: back-to-back frame 402 committed cleanly", amount === 32'd8500);

        // ---------------------------------------------------------------------
        // TEST 10: Soft Reset via Control Register
        // ---------------------------------------------------------------------
        $display("TEST 10: Soft reset via TXN_CTRL bit[1]");
        obi_write(32'h4000_0000, 32'h0000_0007); // bit[1]=1 (soft reset)
        #20;
        obi_read(32'h4000_0004, read_reg); // TXN_STATUS
        check("T10a: status cleared after soft reset", read_reg === 32'd0);
        obi_read(32'h4000_0018, read_reg); // TXN_ERR_CODE
        check("T10b: error code cleared after soft reset", read_reg === 32'd0);

        // ---------------------------------------------------------------------
        // SUMMARY
        // ---------------------------------------------------------------------
        $display("---------------------------------------------------------------");
        $display("  Checks passed : %0d", pass_count);
        $display("  Checks failed : %0d", fail_count);
        if (fail_count == 0) begin
            $display("  REGRESSION RESULT: PASS (tb_payment_engine)");
        end else begin
            $display("  REGRESSION RESULT: FAIL (tb_payment_engine)");
        end
        $display("---------------------------------------------------------------");

        $finish;
    end

endmodule : tb_payment_engine
