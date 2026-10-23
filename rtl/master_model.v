//============================================================================
// bus_top.v : top-level shared bus controller for 2 masters and 3 slaves
//
// This module is the central bus controller. It combines the following blocks:
//   - arbiter       : selects the active master
//   - master mux    : routes the granted master's bus beats onto the shared bus
//   - addr_decoder  : determines which slave should respond
//   - transaction tracking : counts bus beats during each transfer
//   - response logic : generates m_ready and m_rdata on completion
//
// Transaction format:
//   beat 0  HEADER  = {RW, 1'b0, A[13:8]}  ; RW=1 for write, RW=0 for read
//   beat 1  ADDR_LO = A[7:0]
//   beat 2  WDATA   (only used for write transactions)
//   response: bus returns m_ready and m_rdata for read operations
//
// Notes on timing:
//   - The slave interface uses fixed latency; there is no explicit slave ready.
//   - A slave read data is valid a short time after the ADDR_LO beat.
//   - The top-level bus returns m_ready after the response delay.
//   - Invalid/unmapped addresses still complete safely and do not lock the bus.
//
// Reset and clock semantics:
//   - asynchronous active-low reset
//   - rising-edge clocking
//============================================================================
module bus_top #(
    parameter [7:0] UNMAPPED_RDATA = 8'hEE
)(
    input  wire       clk,
    input  wire       rst_n,

    // -------------------------- Master 0 interface --------------------------
    input  wire       m0_req,
    input  wire       m0_valid,
    input  wire [7:0] m0_dout,
    output wire       m0_gnt,

    // -------------------------- Master 1 interface --------------------------
    input  wire       m1_req,
    input  wire       m1_valid,
    input  wire [7:0] m1_dout,
    output wire       m1_gnt,

    // --------------------- Shared response interface ------------------------
    // These outputs are returned to the active master based on the granted ID.
    output reg  [7:0] m_rdata,
    output reg        m_ready,

    // ----------------------- Broadcast to all slaves ------------------------
    // The selected bus beat is forwarded to every slave; the slave decode logic
    // determines whether that slave should respond.
    output reg  [7:0] s_wdata,
    output reg        s_valid,
    output reg  [1:0] s_sel,

    // --------------------- Slave read-data inputs ---------------------------
    input  wire [7:0] s0_rdata,
    input  wire [7:0] s1_rdata,
    input  wire [7:0] s2_rdata,

    // ---------------------------- Status outputs ----------------------------
    output wire       busy,
    output reg        dec_err
);

    //--------------------------------------------------------------------------
    // Arbiter instance.
    // The arbiter decides which master currently owns the bus.
    //--------------------------------------------------------------------------
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
    wire granted  = gnt0 | gnt1; // bus is active if either grant is asserted

    //--------------------------------------------------------------------------
    // Master-to-bus multiplexing.
    // A master is selected based on its grant. The data from the granted master is
    // forwarded to the bus, while the non-selected master's data is ignored.
    //--------------------------------------------------------------------------
    wire       mux_valid = gnt0 ? m0_valid : (gnt1 ? m1_valid : 1'b0);
    wire [7:0] mux_data  = gnt0 ? m0_dout  : (gnt1 ? m1_dout  : 8'h00);

    //--------------------------------------------------------------------------
    // Address decoder instance.
    // The upper address bits are sampled from the header beat, and the selected
    // slave is identified combinationally.
    //--------------------------------------------------------------------------
    wire [2:0] dec_onehot;
    wire [1:0] dec_code;
    wire       dec_hit;
    addr_decoder u_decoder (
        .addr_hi(mux_data[5:0]),
        .slave_sel(dec_onehot),
        .sel_code(dec_code),
        .hit(dec_hit)
    );

    //--------------------------------------------------------------------------
    // Transaction tracking registers.
    // The system time-shares the same 8 data lines across multiple bus beats.
    // 'beat' tracks how far a transaction has progressed.
    // 'rw_q' stores the direction of the current transfer.
    // 'hit_q' stores whether the address was mapped to a valid slave.
    // 'resp_pipe' introduces a short delay before the transaction is completed.
    //--------------------------------------------------------------------------
    reg  [1:0] beat;        // 0..3 transaction beat counter
    reg        rw_q;        // 1=write, 0=read
    reg        hit_q;       // decode result from header beat
    reg  [1:0] resp_pipe;   // response delay pipeline

    // hdr_beat is true when the current bus beat is the HEADER beat.
    wire hdr_beat  = mux_valid & (beat == 2'd0);

    // last_beat indicates the final operand beat for the current transaction.
    // For reads, the final beat is ADDR_LO.
    // For writes, the final beat is WDATA.
    wire last_beat = mux_valid & ((~rw_q & (beat == 2'd1)) |
                                  ( rw_q & (beat == 2'd2)));

    // --------------------------------------------------------------------------
    // Slave read-data multiplexer.
    // When a read transaction completes, the bus returns the selected slave's
    // data. This multiplexer selects the proper slave read port based on s_sel.
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
    // Main bus control FSM.
    // The bus updates on every rising edge. Response logic is generated after a
    // small delay to emulate the fixed-latency slave behavior.
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all control and status signals to a safe idle state.
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
            // Default operation: broadcast the active master's current bus beat to
            // all slave devices and hold ready low until completion.
            s_wdata   <= mux_data;
            s_valid   <= mux_valid;
            m_ready   <= 1'b0;
            resp_pipe <= {resp_pipe[0], last_beat};

            if (hdr_beat) begin
                // Header beat: latch the transfer direction and decode result.
                // This is the point at which the destination slave is determined.
                rw_q    <= mux_data[7];      // bit 7 = RW: 1 for write, 0 for read
                hit_q   <= dec_hit;         // whether the address maps to a valid slave
                s_sel   <= dec_code;        // pass selected slave code to slave devices
                dec_err <= ~dec_hit;        // error if address is not mapped
                beat    <= 2'd1;            // move to address-low beat
            end else if (mux_valid && beat != 2'd3) begin
                // Advance to the next transaction beat when a valid beat is still
                // being transferred and the maximum transaction depth has not been
                // reached.
                beat <= beat + 2'd1;
            end

            if (resp_pipe[1]) begin
                // Transaction complete: assert m_ready and return valid data for
                // reads, or zero for writes.
                m_ready <= 1'b1;
                m_rdata <= rw_q ? 8'h00 :
                           hit_q ? s_rdata_mux : UNMAPPED_RDATA;
                s_sel   <= 2'd0; // Clear slave selection after completion
                beat    <= 2'd0; // Return to idle beat state
            end

            if (!granted) begin
                // If no master is currently granted, clear the state to prevent
                // stale selects or old bus phase information from lingering.
                s_sel     <= 2'd0;
                beat      <= 2'd0;
                resp_pipe <= 2'b00;
            end
        end
    end
endmodule
