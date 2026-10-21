// ============================================================================
// spi_master.sv -- Independent, synthesizable SPI master (modes 0-3)
// BharatVoice SoC | owner: Hrdya VR
//
// PORTS
//   clk       in  1          System clock. All logic is on posedge clk.
//   rst_n     in  1          Active-low reset, ASYNCHRONOUS assert, deassert
//                            should be synchronised to clk by the integrator.
//   start     in  1          Start request, LEVEL-sampled every clk while the
//                            core is not busy. Drive as a 1-cycle pulse; if held
//                            high it launches a new transfer as soon as the
//                            previous one completes.
//   tx_data   in  DATA_W     Data to send, RIGHT-ALIGNED: bit [xfer_len-1] is
//                            sent first (MSB-first); upper bits are ignored.
//   xfer_len  in  LEN_W      Number of bits, valid 1..DATA_W.  (LEN_W = clog2(DATA_W+1))
//   clk_div   in  CLK_DIV_W  SCLK half-period in clk cycles, valid >= 1.
//                            f_sclk = f_clk / (2*clk_div).  (clk_div=1 -> clk/2)
//   cpol      in  1          Idle level of SCLK.
//   cpha      in  1          0: sample on leading edge, shift on trailing edge
//                            1: shift on leading edge, sample on trailing edge
//                            Mode = {cpol,cpha}. Leading edge = idle->active.
//   busy      out 1          High from the cycle after an accepted start until
//                            the cycle in which done pulses (inclusive of cs_n low).
//   done      out 1          1-cycle pulse; rises in the same cycle busy falls and
//                            cs_n rises. rx_data is valid in that cycle.
//   err_cfg   out 1          1-cycle pulse: start rejected (xfer_len==0,
//                            xfer_len>DATA_W or clk_div==0). Nothing is started.
//   err_busy  out 1          1-cycle pulse: start asserted while busy. IGNORED;
//                            the running transfer is unaffected.
//   rx_data   out DATA_W     Received data, RIGHT-ALIGNED (first bit received ends
//                            up in bit [xfer_len-1]); upper bits 0. Valid when done
//                            pulses; stable until next accepted start (which clears it).
//   sclk      out 1          SPI clock (idle = cpol; = 0 during reset).
//   mosi      out 1          Master-out. Idle/reset value 0.
//   miso      in  1          Master-in (sampled directly, no synchroniser).
//   cs_n      out 1          Active-low chip select (idle/reset = 1).
//
// CONFIG SAMPLING: tx_data, xfer_len, clk_div, cpol, cpha are latched on the
//   accepting clock edge; changing them during a transfer has no effect.
//   Keep cpol stable >=1 clk before start (SCLK idle level follows cpol while idle).
//
// TIMING (T = clk period, D = clk_div, N = xfer_len, A0 = accepting clk edge)
//   cs_n falls, busy rises (and mosi = first bit for cpha=0)  at A0
//   SCLK edge k (k = 0 .. 2N-1; even = leading, odd = trailing) at A0 + (k+1)*D*T
//   cs_n rises, busy falls, done pulses                        at A0 + (2N+1)*D*T
//   => CS setup = D*T before first SCLK edge, CS hold = D*T after the last one.
//   cs_n stays high for >= 1 clk between transfers (start may be asserted in
//   the done cycle for the tightest back-to-back).
//
// RESET DURING TRANSFER: async; immediately cs_n=1, busy=0, done=0, sclk=0,
//   mosi=0, rx_data=0. The transfer is abandoned (slave sees truncated frame);
//   no done pulse. The core is immediately usable again after reset release.
//
// LIMITATIONS: single CS; no MISO synchroniser/late-sampling (OK for on-chip
//   or slow-SCLK use; add sampling delay for fast external devices);
//   DATA_W >= 2; no CS-high minimum-time option.
// ============================================================================
`timescale 1ns/1ps

module spi_master #(
    parameter int unsigned DATA_W    = 32,   // max bits per transfer (>= 2)
    parameter int unsigned CLK_DIV_W = 16
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         start,
    input  logic [DATA_W-1:0]            tx_data,
    input  logic [$clog2(DATA_W+1)-1:0]  xfer_len,
    input  logic [CLK_DIV_W-1:0]         clk_div,
    input  logic                         cpol,
    input  logic                         cpha,
    output logic                         busy,
    output logic                         done,
    output logic                         err_cfg,
    output logic                         err_busy,
    output logic [DATA_W-1:0]            rx_data,
    output logic                         sclk,
    output logic                         mosi,
    input  logic                         miso,
    output logic                         cs_n
);

    localparam int unsigned LEN_W  = $clog2(DATA_W+1);
    localparam int unsigned EDGE_W = LEN_W + 1;      // edges 0 .. 2*DATA_W-1

    typedef enum logic [1:0] {S_IDLE = 2'd0, S_XFER = 2'd1, S_HOLD = 2'd2} state_t;
    state_t state;

    logic [DATA_W-1:0]    tx_shift, rx_shift;
    logic [CLK_DIV_W-1:0] div_r, cnt;
    logic [LEN_W-1:0]     len_r;
    logic [EDGE_W-1:0]    edge_cnt;
    logic                 cpol_r, cpha_r;
    logic                 sclk_r, mosi_r, cs_n_r, busy_r, done_r, errc_r, errb_r;

    assign sclk     = sclk_r;
    assign mosi     = mosi_r;
    assign cs_n     = cs_n_r;
    assign busy     = busy_r;
    assign done     = done_r;
    assign err_cfg  = errc_r;
    assign err_busy = errb_r;
    assign rx_data  = rx_shift;

    // configuration check (on the live inputs, used only when accepting start)
    wire cfg_bad = (xfer_len == '0) || (xfer_len > DATA_W) || (clk_div == '0);

    // per-edge decode (edge_cnt even = leading edge)
    wire is_lead      = ~edge_cnt[0];
    wire is_last_edge = (edge_cnt == ({len_r, 1'b0} - 1'b1));   // edge 2N-1
    wire do_sample    = cpha_r ? ~is_lead : is_lead;
    wire do_shift     = cpha_r ?  is_lead : (~is_lead & ~is_last_edge);

    // left-align tx so that the first bit is always tx_aligned[DATA_W-1]
    wire [DATA_W-1:0] tx_aligned = tx_data << (DATA_W - xfer_len);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            sclk_r   <= 1'b0;
            mosi_r   <= 1'b0;
            cs_n_r   <= 1'b1;
            busy_r   <= 1'b0;
            done_r   <= 1'b0;
            errc_r   <= 1'b0;
            errb_r   <= 1'b0;
            tx_shift <= '0;
            rx_shift <= '0;
            div_r    <= '0;
            cnt      <= '0;
            len_r    <= '0;
            edge_cnt <= '0;
            cpol_r   <= 1'b0;
            cpha_r   <= 1'b0;
        end else begin
            // pulse outputs default low
            done_r <= 1'b0;
            errc_r <= 1'b0;
            errb_r <= 1'b0;

            case (state)
                // -------------------------------------------------------
                S_IDLE: begin
                    sclk_r <= cpol;                       // idle level tracks cpol
                    if (start) begin
                        if (cfg_bad) begin
                            errc_r <= 1'b1;               // reject, stay idle
                        end else begin
                            div_r    <= clk_div;
                            len_r    <= xfer_len;
                            cpol_r   <= cpol;
                            cpha_r   <= cpha;
                            cnt      <= clk_div - 1'b1;   // first edge after D cycles
                            edge_cnt <= '0;
                            rx_shift <= '0;
                            cs_n_r   <= 1'b0;
                            busy_r   <= 1'b1;
                            state    <= S_XFER;
                            if (!cpha) begin              // mode 0/2: bit0 out at CS fall
                                mosi_r   <= tx_aligned[DATA_W-1];
                                tx_shift <= {tx_aligned[DATA_W-2:0], 1'b0};
                            end else begin                // mode 1/3: bit0 out at 1st leading edge
                                mosi_r   <= 1'b0;
                                tx_shift <= tx_aligned;
                            end
                        end
                    end
                end
                // -------------------------------------------------------
                S_XFER: begin
                    if (start) errb_r <= 1'b1;
                    if (cnt == '0) begin
                        sclk_r <= ~sclk_r;
                        if (do_sample)
                            rx_shift <= {rx_shift[DATA_W-2:0], miso};
                        if (do_shift) begin
                            mosi_r   <= tx_shift[DATA_W-1];
                            tx_shift <= {tx_shift[DATA_W-2:0], 1'b0};
                        end
                        cnt <= div_r - 1'b1;
                        if (is_last_edge) state    <= S_HOLD;
                        else              edge_cnt <= edge_cnt + 1'b1;
                    end else begin
                        cnt <= cnt - 1'b1;
                    end
                end
                // -------------------------------------------------------
                S_HOLD: begin
                    if (start) errb_r <= 1'b1;
                    if (cnt == '0) begin
                        cs_n_r <= 1'b1;
                        busy_r <= 1'b0;
                        done_r <= 1'b1;
                        mosi_r <= 1'b0;
                        state  <= S_IDLE;
                    end else begin
                        cnt <= cnt - 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
