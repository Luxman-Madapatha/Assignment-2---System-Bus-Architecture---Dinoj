//============================================================================
// bus_top.v : 8-bit multiplexed parallel bus  (2 masters, 3 slaves)
//
// Transaction (all beats use the same 8 data lines):
//   beat 0  HEADER  = {RW, 1'b0, A[13:8]}    RW: 1 = write, 0 = read
//   beat 1  ADDR_LO = A[7:0]
//   beat 2  WDATA   (write only)
//   -> bus returns m_ready (1-cycle pulse) with m_rdata for reads
//
// Contents:
//   * arbiter       : fixed priority, M0 > M1, non-preemptive
//   * master mux    : routes the granted master's beats
//   * addr_decoder  : decodes the header beat, select latched per transaction
//   * slave read-data mux + response generator
//
// Slave interface is fixed latency (no slave ready wire, to fit the DE0
// header pin budget): a slave's read data is valid on sN_rdata from one
// clock after it samples the ADDR_LO beat and is held until its next read.
// The bus returns m_ready two clocks after the last beat.
// Unmapped addresses still complete (no bus lock-up): reads return
// UNMAPPED_RDATA and dec_err is set.
//
// Asynchronous active-low reset, rising-edge clock.
//============================================================================
module bus_top #(
    parameter [7:0] UNMAPPED_RDATA = 8'hEE
)(
    input  wire       clk,
    input  wire       rst_n,
    // ---- Master 0 ----
    input  wire       m0_req,
    input  wire       m0_valid,
    input  wire [7:0] m0_dout,
    output wire       m0_gnt,
    // ---- Master 1 ----
    input  wire       m1_req,
    input  wire       m1_valid,
    input  wire [7:0] m1_dout,
    output wire       m1_gnt,
    // ---- Response to masters (shared, qualified by own gnt) ----
    output reg  [7:0] m_rdata,
    output reg        m_ready,
    // ---- To slaves (broadcast data/valid + select code) ----
    output reg  [7:0] s_wdata,
    output reg        s_valid,
    output reg  [1:0] s_sel,
    // ---- From slaves ----
    input  wire [7:0] s0_rdata,
    input  wire [7:0] s1_rdata,
    input  wire [7:0] s2_rdata,
    // ---- Status ----
    output wire       busy,
    output reg        dec_err
);
    //------------------------------------------------------------------
    // Arbiter
    //------------------------------------------------------------------
    wire gnt0, gnt1;
    arbiter u_arbiter (
        .clk(clk), .rst_n(rst_n),
        .req0(m0_req), .req1(m1_req),
        .gnt0(gnt0), .gnt1(gnt1), .busy(busy)
    );
    assign m0_gnt = gnt0;
    assign m1_gnt = gnt1;
    wire granted  = gnt0 | gnt1;

    //------------------------------------------------------------------
    // Master -> bus multiplexer (controlled by the grants)
    //------------------------------------------------------------------
    wire       mux_valid = gnt0 ? m0_valid : (gnt1 ? m1_valid : 1'b0);
    wire [7:0] mux_data  = gnt0 ? m0_dout  : (gnt1 ? m1_dout  : 8'h00);

    //------------------------------------------------------------------
    // Address decoder (combinational on the header beat)
    //------------------------------------------------------------------
    wire [2:0] dec_onehot;
    wire [1:0] dec_code;
    wire       dec_hit;
    addr_decoder u_decoder (
        .addr_hi(mux_data[5:0]),
        .slave_sel(dec_onehot), .sel_code(dec_code), .hit(dec_hit)
    );

    //------------------------------------------------------------------
    // Transaction tracking
    //------------------------------------------------------------------
    reg  [1:0] beat;        // beats received in the current transaction
    reg        rw_q;        // latched RW bit
    reg        hit_q;       // latched decode result
    reg  [1:0] resp_pipe;   // response delay line (slave latency)

    wire hdr_beat  = mux_valid & (beat == 2'd0);
    wire last_beat = mux_valid & ((~rw_q & (beat == 2'd1)) |
                                  ( rw_q & (beat == 2'd2)));

    // Slave -> bus read-data multiplexer (by latched select code)
    reg [7:0] s_rdata_mux;
    always @(*) begin
        case (s_sel)
            2'd1:    s_rdata_mux = s0_rdata;
            2'd2:    s_rdata_mux = s1_rdata;
            2'd3:    s_rdata_mux = s2_rdata;
            default: s_rdata_mux = 8'h00;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_wdata   <= 8'h00;
            s_valid   <= 1'b0;
            s_sel     <= 2'd0;
            m_rdata   <= 8'h00;
            m_ready   <= 1'b0;
            beat      <= 2'd0;
            rw_q      <= 1'b0;
            hit_q     <= 1'b0;
            resp_pipe <= 2'b00;
            dec_err   <= 1'b0;
        end else begin
            // forward the granted master's beat to all slaves (registered)
            s_wdata   <= mux_data;
            s_valid   <= mux_valid;
            m_ready   <= 1'b0;
            resp_pipe <= {resp_pipe[0], last_beat};

            if (hdr_beat) begin                 // decode + latch select
                rw_q    <= mux_data[7];
                hit_q   <= dec_hit;
                s_sel   <= dec_code;            // aligned with the header beat
                dec_err <= ~dec_hit;
                beat    <= 2'd1;
            end else if (mux_valid && beat != 2'd3) begin
                beat    <= beat + 2'd1;
            end

            if (resp_pipe[1]) begin             // complete the transaction
                m_ready <= 1'b1;
                m_rdata <= rw_q  ? 8'h00 :
                           hit_q ? s_rdata_mux : UNMAPPED_RDATA;
                s_sel   <= 2'd0;
                beat    <= 2'd0;
            end

            if (!granted) begin                 // safety: bus released
                s_sel     <= 2'd0;
                beat      <= 2'd0;
                resp_pipe <= 2'b00;
            end
        end
    end
endmodule
