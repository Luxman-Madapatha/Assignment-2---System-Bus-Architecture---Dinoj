//============================================================================
// bus_top.v : top-level shared bus controller for 2 masters and 3 slaves
//
// Functional summary:
//   - Coordinates bus ownership between M0 and M1.
//   - Multiplies the granted master's data onto the shared bus.
//   - Decodes the target slave during the HEADER beat.
//   - Tracks beat progression across a transaction.
//   - Returns read data and ready signal at transaction completion.
//   - Prevents bus deadlock for unmapped addresses.
//
// Transaction protocol:
//   beat 0 : HEADER  = {RW, 1'b0, A[13:8]}
//   beat 1 : ADDR_LO = A[7:0]
//   beat 2 : WDATA   (write transactions only)
//   response: m_ready pulse and m_rdata for read transactions
//
// Timing model:
//   - Asynchronous active-low reset.
//   - Rising-edge clocking.
//   - Fixed-latency read response.
//============================================================================
module bus_top #(
    parameter [7:0] UNMAPPED_RDATA = 8'hEE
)(
    input  wire       clk,
    input  wire       rst_n,

    // --------------------------------------------------------------------------
    // Master 0 interface.
    // --------------------------------------------------------------------------
    input  wire       m0_req,
    input  wire       m0_valid,
    input  wire [7:0] m0_dout,
    output wire       m0_gnt,

    // --------------------------------------------------------------------------
    // Master 1 interface.
    // --------------------------------------------------------------------------
    input  wire       m1_req,
    input  wire       m1_valid,
    input  wire [7:0] m1_dout,
    output wire       m1_gnt,

    // --------------------------------------------------------------------------
    // Shared response interface.
    // These outputs are returned to the active master as the bus transaction is
    // completed.
    // --------------------------------------------------------------------------
    output reg  [7:0] m_rdata,
    output reg        m_ready,

    // --------------------------------------------------------------------------
    // Broadcast slave interface.
    // Every slave sees the same bus beat, and each slave decides whether it is the
    // destination using s_sel and s_valid.
    // --------------------------------------------------------------------------
    output reg  [7:0] s_wdata,
    output reg        s_valid,
    output reg  [1:0] s_sel,

    // --------------------------------------------------------------------------
    // Slave read-data inputs.
    // --------------------------------------------------------------------------
    input  wire [7:0] s0_rdata,
    input  wire [7:0] s1_rdata,
    input  wire [7:0] s2_rdata,

    // --------------------------------------------------------------------------
    // Status outputs.
    // --------------------------------------------------------------------------
    output wire       busy,
    output reg        dec_err
);

    // --------------------------------------------------------------------------
    // Block: Arbiter Instance
    // --------------------------------------------------------------------------
    // The arbiter decides which master owns the bus at the current clock cycle.
    // --------------------------------------------------------------------------
    wire gnt0, gnt1;
    arbiter u_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .req0(m0_req),
        .req1(m1_req),
        .gnt0(gnt0),
        .gnt1(gnt1),
        .busy(busy)
    );
    assign m0_gnt = gnt0;
    assign m1_gnt = gnt1;
    wire granted = gnt0 | gnt1; // bus is active if either grant is high

    // --------------------------------------------------------------------------
    // Block: Master-to-Bus Multiplexing
    // --------------------------------------------------------------------------
    // The active master's data is routed onto the shared bus by the grant signal.
    // The non-selected master is ignored.
    // --------------------------------------------------------------------------
    wire       mux_valid = gnt0 ? m0_valid : (gnt1 ? m1_valid : 1'b0);
    wire [7:0] mux_data  = gnt0 ? m0_dout  : (gnt1 ? m1_dout  : 8'h00);

    // --------------------------------------------------------------------------
    // Block: Address Decoder Instance
    // --------------------------------------------------------------------------
    // The upper address bits are sampled from the HEADER beat and decoded to a
    // selected slave target. This is a combinational block.
    // --------------------------------------------------------------------------
    wire [2:0] dec_onehot;
    wire [1:0] dec_code;
    wire       dec_hit;
    addr_decoder u_decoder (
        .addr_hi(mux_data[5:0]),
        .slave_sel(dec_onehot),
        .sel_code(dec_code),
        .hit(dec_hit)
    );

    // --------------------------------------------------------------------------
    // Block: Transaction Tracking Registers
    // --------------------------------------------------------------------------
    // beat      : tracks the current transfer beat within a transaction
    // rw_q      : stores the direction of the present transaction
    // hit_q     : stores whether the address maps to a legal slave
    // resp_pipe : delay pipeline used to time the read response
    //
    // Protocol timing:
    //   - beat = 0 : HEADER beat
    //   - beat = 1 : ADDR_LO beat
    //   - beat = 2 : WDATA beat (write only)
    //   - after completion: m_ready pulse generated and state resets
    // --------------------------------------------------------------------------
    reg  [1:0] beat;        // 0..3 transaction beat counter
    reg        rw_q;        // rw_q = 1 => write, 0 => read
    reg        hit_q;       // decode result from the header beat
    reg  [1:0] resp_pipe;   // response delay pipeline

    // hdr_beat is true only during the HEADER beat of the active transaction.
    wire hdr_beat = mux_valid & (beat == 2'd0);

    // last_beat marks the final beat of the current transfer.
    // For a read, the final beat is ADDR_LO.
    // For a write, the final beat is WDATA.
    wire last_beat = mux_valid & ((~rw_q & (beat == 2'd1)) |
                                  ( rw_q & (beat == 2'd2)));

    // --------------------------------------------------------------------------
    // Block: Slave Read-Data Multiplexer
    // --------------------------------------------------------------------------
    // The selected slave data is forwarded onto the response bus only after the
    // read operation completes.
    // --------------------------------------------------------------------------
    reg [7:0] s_rdata_mux;
    always @(*) begin
        case (s_sel)
            2'd1:    s_rdata_mux = s0_rdata;
            2'd2:    s_rdata_mux = s1_rdata;
            2'd3:    s_rdata_mux = s2_rdata;
            default: s_rdata_mux = 8'h00; // No valid slave selected
        endcase
    end

    // --------------------------------------------------------------------------
    // Block: Main Bus Control Logic
    // --------------------------------------------------------------------------
    // State progression:
    //   - At reset: all outputs are cleared and bus is idle.
    //   - On HEADER beat: decode and latch transfer metadata.
    //   - On ADDR_LO beat: the address is finalized.
    //   - On WDATA beat: write data is transferred.
    //   - On completion: m_ready is asserted and transaction is cleared.
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset state: clear bus data, ready, beat counter, and decode result.
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
            // ------------------------------------------------------------------
            // Default update: broadcast the current bus beat to all slaves.
            // ------------------------------------------------------------------
            s_wdata   <= mux_data;
            s_valid   <= mux_valid;
            m_ready   <= 1'b0;
            resp_pipe <= {resp_pipe[0], last_beat};

            if (hdr_beat) begin
                // Timing: HEADER beat at cycle N -> decode and latch transaction info.
                // Protocol: capture read/write direction and valid slave selection.
                rw_q    <= mux_data[7];      // bit 7 = 1 for write, 0 for read
                hit_q   <= dec_hit;          // decoded validity of target address
                s_sel   <= dec_code;         // selected slave code is latched here
                dec_err <= ~dec_hit;         // error if address is unmapped
                beat    <= 2'd1;             // move to ADDR_LO phase on next cycle
            end else if (mux_valid && beat != 2'd3) begin
                // Timing: each subsequent valid bus beat increments the beat counter.
                // Protocol: ADDR_LO -> WDATA -> response completion.
                beat <= beat + 2'd1;
            end

            if (resp_pipe[1]) begin
                // Timing: response pipeline completes after the fixed slave latency.
                // Protocol: m_ready pulse is generated, and read data is returned.
                m_ready <= 1'b1;
                m_rdata <= rw_q ? 8'h00 :
                           hit_q ? s_rdata_mux : UNMAPPED_RDATA;
                s_sel   <= 2'd0; // Clear slave selection after completion
                beat    <= 2'd0; // Return to idle beat state
            end

            if (!granted) begin
                // Timing: if no master is granted, the bus must be considered idle.
                // This clears stale select and beat information.
                s_sel     <= 2'd0;
                beat      <= 2'd0;
                resp_pipe <= 2'b00;
            end
        end
    end
endmodule
