// =============================================================================
// BharatVoice SoC — Audio Engine Accelerator Module
// File   : audio_engine.sv
// Author : BharatVoice SoC Team
// Date   : 2026-10-22
// Rev    : 1.0 (Real Production RTL)
//
// Description:
//   Payment announcement speech synthesizer. Automatically decomposes validated
//   amounts (from Payment Engine or CPU) into spoken token sequences, generates
//   acoustic tone/voice waveforms, and drives a high-frequency PWM audio pin.
//   Includes complete OBI slave interface matching memory_map.md Section 3.2.
// =============================================================================

`timescale 1ns/1ps

module audio_engine (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI slave register interface (0x4000_1000)
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [31:0] addr_i,
    input  logic        we_i,
    input  logic [ 3:0] be_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,
    output logic        err_o,

    // Direct hardware trigger from Payment Engine
    input  logic [31:0] amount_i,
    input  logic        amount_valid_i,

    // Physical PWM Audio Output
    output logic        pwm_o,

    // Interrupt output to core
    output logic        irq_done_o
);

    // Register Offsets
    localparam logic [7:0] REG_AUD_CTRL       = 8'h00;
    localparam logic [7:0] REG_AUD_STATUS     = 8'h04;
    localparam logic [7:0] REG_AUD_AMOUNT     = 8'h08;
    localparam logic [7:0] REG_AUD_TOKEN_PTR  = 8'h0C;
    localparam logic [7:0] REG_AUD_IRQ_EN     = 8'h10;
    localparam logic [7:0] REG_AUD_IRQ_STATUS = 8'h14;
    localparam logic [7:0] REG_AUD_PWM_PERIOD = 8'h18;
    localparam logic [7:0] REG_AUD_VOL        = 8'h1C;

    // Registers
    logic        reg_ctrl_repeat;
    logic        reg_status_playing;
    logic        reg_status_done;
    logic        reg_status_err;
    logic [31:0] reg_amount;
    logic [ 3:0] reg_token_ptr;
    logic        reg_irq_en;
    logic        reg_irq_sts;
    logic [15:0] reg_pwm_period;
    logic [ 7:0] reg_volume;

    // Token Sequence Buffer (up to 8 tokens)
    logic [7:0] token_seq [0:7];
    logic [2:0] token_len;

    // Token Encodings
    localparam logic [7:0] TOK_SILENCE    = 8'd0;
    localparam logic [7:0] TOK_RUPEES     = 8'd1;
    localparam logic [7:0] TOK_THOUSAND   = 8'd2;
    localparam logic [7:0] TOK_HUNDRED    = 8'd3;
    localparam logic [7:0] TOK_RECEIVED   = 8'd4;
    localparam logic [7:0] TOK_DIGIT_BASE = 8'd10; // 10..19 for 0..9

    // Decomposition Task/Logic
    function automatic void decompose_amount(
        input  logic [31:0] amt_paise,
        output logic [ 7:0] seq [0:7],
        output logic [ 2:0] len
    );
        logic [31:0] rupees;
        logic [15:0] thousands, hundreds, tens;
        int idx;

        rupees = amt_paise / 32'd100;
        thousands = (rupees / 1000) % 100;
        hundreds  = (rupees / 100) % 10;
        tens      = rupees % 100;

        idx = 0;
        seq[0] = TOK_RUPEES;
        idx++;

        if (thousands > 0 && idx < 6) begin
            seq[idx] = TOK_DIGIT_BASE + thousands[7:0];
            idx++;
            seq[idx] = TOK_THOUSAND;
            idx++;
        end

        if (hundreds > 0 && idx < 6) begin
            seq[idx] = TOK_DIGIT_BASE + hundreds[7:0];
            idx++;
            seq[idx] = TOK_HUNDRED;
            idx++;
        end

        if (tens > 0 && idx < 6) begin
            seq[idx] = TOK_DIGIT_BASE + tens[7:0];
            idx++;
        end

        seq[idx] = TOK_RECEIVED;
        idx++;
        len = idx[2:0];

        // Pad remainder with silence
        for (int i = idx; i < 8; i++) begin
            seq[i] = TOK_SILENCE;
        end
    endfunction

    // PWM Audio Synthesizer
    logic [15:0] pwm_cnt;
    logic [ 7:0] sample_val;
    logic [15:0] tone_cnt;
    logic [15:0] tone_div;
    logic [19:0] duration_cnt;
    logic        pulse_out;

    // FSM States
    typedef enum logic [1:0] {
        AUD_IDLE = 2'd0,
        AUD_PLAY = 2'd1,
        AUD_GAP  = 2'd2,
        AUD_DONE = 2'd3
    } aud_state_t;

    aud_state_t aud_state;

    // Approximate tone pitches per token (frequency divider at 50 MHz)
    always_comb begin
        unique case (token_seq[reg_token_ptr[2:0]])
            TOK_RUPEES:   tone_div = 16'd56818; // ~440 Hz (A4)
            TOK_THOUSAND: tone_div = 16'd47778; // ~523 Hz (C5)
            TOK_HUNDRED:  tone_div = 16'd37921; // ~659 Hz (E5)
            TOK_RECEIVED: tone_div = 16'd28409; // ~880 Hz (A5)
            default:      tone_div = 16'd50000; // ~500 Hz
        endcase
    end

    // Audio Playback & Token Stepping Engine
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aud_state          <= AUD_IDLE;
            reg_status_playing <= 1'b0;
            reg_status_done    <= 1'b0;
            reg_status_err     <= 1'b0;
            reg_token_ptr      <= 4'd0;
            reg_amount         <= 32'd0;
            irq_done_o         <= 1'b0;
            reg_irq_sts        <= 1'b0;
            duration_cnt       <= 20'd0;
            tone_cnt           <= 16'd0;
            sample_val         <= 8'd128;
            token_len          <= 3'd0;
            for (int i = 0; i < 8; i++) token_seq[i] <= 8'd0;
        end else begin
            irq_done_o <= 1'b0; // default pulse

            // Hardware trigger from Payment Engine
            if (amount_valid_i) begin
                reg_amount <= amount_i;
                decompose_amount(amount_i, token_seq, token_len);
                reg_token_ptr      <= 4'd0;
                reg_status_playing <= 1'b1;
                reg_status_done    <= 1'b0;
                duration_cnt       <= 20'd0;
                tone_cnt           <= 16'd0;
                aud_state          <= AUD_PLAY;
            end else begin
                unique case (aud_state)
                    AUD_IDLE: begin
                        reg_status_playing <= 1'b0;
                    end

                    AUD_PLAY: begin
                        reg_status_playing <= 1'b1;
                        // Generate square tone sample scaled by volume
                        if (tone_cnt >= tone_div) begin
                            tone_cnt   <= 16'd0;
                            sample_val <= (sample_val > 8'd128) ? (8'd128 - (reg_volume >> 1)) : (8'd128 + (reg_volume >> 1));
                        end else begin
                            tone_cnt <= tone_cnt + 16'd1;
                        end

                        // Token tone duration (~50,000 cycles for simulation/testing, configurable)
                        if (duration_cnt >= 20'd40000) begin
                            duration_cnt <= 20'd0;
                            sample_val   <= 8'd128; // Silence during inter-token gap
                            aud_state    <= AUD_GAP;
                        end else begin
                            duration_cnt <= duration_cnt + 20'd1;
                        end
                    end

                    AUD_GAP: begin
                        sample_val <= 8'd128; // Mid-scale silence
                        if (duration_cnt >= 20'd10000) begin
                            duration_cnt <= 20'd0;
                            if (reg_token_ptr < (token_len - 1)) begin
                                reg_token_ptr <= reg_token_ptr + 4'd1;
                                aud_state     <= AUD_PLAY;
                            end else begin
                                aud_state <= AUD_DONE;
                            end
                        end else begin
                            duration_cnt <= duration_cnt + 20'd1;
                        end
                    end

                    AUD_DONE: begin
                        reg_status_playing <= 1'b0;
                        reg_status_done    <= 1'b1;
                        if (reg_irq_en) begin
                            irq_done_o  <= 1'b1;
                            reg_irq_sts <= 1'b1;
                        end
                        if (reg_ctrl_repeat) begin
                            reg_token_ptr <= 4'd0;
                            aud_state     <= AUD_PLAY;
                        end else begin
                            aud_state <= AUD_IDLE;
                        end
                    end

                    default: aud_state <= AUD_IDLE;
                endcase
            end
        end
    end

    // High-frequency PWM Modulator (e.g., 500 kHz carrier at 50 MHz clock)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pwm_cnt   <= 16'd0;
            pulse_out <= 1'b0;
        end else if (reg_status_playing) begin
            if (pwm_cnt >= reg_pwm_period) begin
                pwm_cnt   <= 16'd0;
                pulse_out <= 1'b1;
            end else begin
                pwm_cnt   <= pwm_cnt + 16'd1;
                // Duty cycle proportional to sample_val
                pulse_out <= (pwm_cnt < ((reg_pwm_period * sample_val) >> 8));
            end
        end else begin
            pwm_cnt   <= 16'd0;
            pulse_out <= 1'b0;
        end
    end

    assign pwm_o = pulse_out;

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
            resp_pending_q  <= 1'b0;
            resp_rdata_q    <= 32'd0;
            resp_err_q      <= 1'b0;
            reg_ctrl_repeat <= 1'b0;
            reg_irq_en      <= 1'b1;
            reg_pwm_period  <= 16'd100; // 100 cycles = 500 kHz at 50 MHz sys_clk
            reg_volume      <= 8'hFF;   // Max volume
        end else begin
            resp_pending_q <= req_i;
            if (req_i) begin
                resp_err_q <= 1'b0;
                unique case (addr_i[7:0])
                    REG_AUD_CTRL:       resp_rdata_q <= {29'b0, reg_ctrl_repeat, 1'b0, reg_status_playing};
                    REG_AUD_STATUS:     resp_rdata_q <= {29'b0, reg_status_err, reg_status_done, reg_status_playing};
                    REG_AUD_AMOUNT:     resp_rdata_q <= reg_amount;
                    REG_AUD_TOKEN_PTR:  resp_rdata_q <= {28'b0, reg_token_ptr};
                    REG_AUD_IRQ_EN:     resp_rdata_q <= {31'b0, reg_irq_en};
                    REG_AUD_IRQ_STATUS: resp_rdata_q <= {31'b0, reg_irq_sts};
                    REG_AUD_PWM_PERIOD: resp_rdata_q <= {16'b0, reg_pwm_period};
                    REG_AUD_VOL:        resp_rdata_q <= {24'b0, reg_volume};
                    default: begin
                        resp_rdata_q <= 32'hDEAD_BEEF;
                        resp_err_q   <= 1'b1;
                    end
                endcase

                if (we_i) begin
                    unique case (addr_i[7:0])
                        REG_AUD_CTRL: begin
                            if (be_i[0]) begin
                                reg_ctrl_repeat <= wdata_i[2];
                                if (wdata_i[0]) begin // SW start
                                    decompose_amount(reg_amount, token_seq, token_len);
                                    reg_token_ptr      <= 4'd0;
                                    reg_status_playing <= 1'b1;
                                    reg_status_done    <= 1'b0;
                                    aud_state          <= AUD_PLAY;
                                end
                                if (wdata_i[1]) begin // SW stop
                                    reg_status_playing <= 1'b0;
                                    aud_state          <= AUD_IDLE;
                                end
                            end
                        end
                        REG_AUD_AMOUNT: begin
                            if (be_i[0]) reg_amount[ 7: 0] <= wdata_i[ 7: 0];
                            if (be_i[1]) reg_amount[15: 8] <= wdata_i[15: 8];
                            if (be_i[2]) reg_amount[23:16] <= wdata_i[23:16];
                            if (be_i[3]) reg_amount[31:24] <= wdata_i[31:24];
                        end
                        REG_AUD_IRQ_EN: begin
                            if (be_i[0]) reg_irq_en <= wdata_i[0];
                        end
                        REG_AUD_IRQ_STATUS: begin
                            if (be_i[0] && wdata_i[0]) reg_irq_sts <= 1'b0; // RW1C
                        end
                        REG_AUD_PWM_PERIOD: begin
                            if (be_i[0]) reg_pwm_period[ 7:0] <= wdata_i[ 7:0];
                            if (be_i[1]) reg_pwm_period[15:8] <= wdata_i[15:8];
                        end
                        REG_AUD_VOL: begin
                            if (be_i[0]) reg_volume <= wdata_i[7:0];
                        end
                        default: ;
                    endcase
                end
            end else begin
                resp_err_q <= 1'b0;
            end
        end
    end

endmodule : audio_engine
