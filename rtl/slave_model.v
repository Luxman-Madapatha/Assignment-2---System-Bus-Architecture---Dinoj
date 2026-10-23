//============================================================================
// master_model.v : behavioral bus master model
//
// Functional summary:
//   - Generates bus requests and transaction commands.
//   - Drives the HEADER, ADDR_LO, and optionally WDATA beats.
//   - Captures the returned read data when bus_ready is asserted.
//   - Models one transaction per command cycle.
//
// Timing model:
//   - Rising-edge clocking.
//   - Asynchronous active-low reset.
//   - start is accepted only when the master is idle.
//============================================================================
module master_model (
    input  wire        clk,
    input  wire        rst_n,

    // --------------------------------------------------------------------------
    // Command input interface.
    // These signals originate from a testbench or higher-level control logic.
    // --------------------------------------------------------------------------
    input  wire        start,      // one-cycle pulse accepted only when idle
    input  wire        rw,         // 1 = write, 0 = read
    input  wire [13:0] addr,       // full 14-bit address
    input  wire [7:0]  wdata,      // write data for write transactions

    // --------------------------------------------------------------------------
    // Status output interface.
    // --------------------------------------------------------------------------
    output reg  [7:0]  rdata,      // last successfully read data
    output reg         done,       // one-cycle pulse when transaction completes
    output wire        busy,

    // --------------------------------------------------------------------------
    // Bus-side interface.
    // --------------------------------------------------------------------------
    output reg         req,        // request line asserted when the master wants bus
    input  wire        gnt,        // grant from bus arbiter
    output reg         valid,      // indicates the bus beat is valid
    output reg  [7:0]  dout,       // data driven onto the shared bus
    input  wire [7:0]  bus_rdata,  // returned data from the selected slave
    input  wire        bus_ready   // response valid signal from the bus
);

    // --------------------------------------------------------------------------
    // State encoding.
    // Each state describes the master phase in the bus transaction sequence.
    // --------------------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0,  // waiting for a command from the testbench
                     S_REQ  = 3'd1,  // request asserted, waiting for grant
                     S_HDR  = 3'd2,  // drive HEADER beat
                     S_ALO  = 3'd3,  // drive ADDR_LO beat
                     S_DAT  = 3'd4,  // drive WDATA beat for writes
                     S_WAIT = 3'd5,  // wait for bus_ready
                     S_REL  = 3'd6;  // drop request and wait until grant is released

    reg [2:0]  state;
    reg        rw_q;
    reg [13:0] addr_q;
    reg [7:0]  wdata_q;

    // --------------------------------------------------------------------------
    // Block: Transaction State Machine
    // --------------------------------------------------------------------------
    // Protocol timing annotations:
    //   - S_IDLE -> S_REQ : on start pulse, request is asserted
    //   - S_REQ  -> S_HDR : when gnt is high, HEADER beat is driven
    //   - S_HDR  -> S_ALO : next beat drives lower address byte
    //   - S_ALO  -> S_DAT : for write transfers, WDATA is driven
    //   - S_ALO  -> S_WAIT: for read transfers, no write data is driven
    //   - S_DAT  -> S_WAIT: WDATA beat complete, now wait for slave response
    //   - S_WAIT -> S_REL : when gnt && bus_ready is true
    //   - S_REL  -> S_IDLE: once gnt goes low, request is released
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset state: return the master to an idle and quiescent condition.
            state   <= S_IDLE;
            req     <= 1'b0;
            valid   <= 1'b0;
            dout    <= 8'h00;
            rdata   <= 8'h00;
            done    <= 1'b0;
            rw_q    <= 1'b0;
            addr_q  <= 14'd0;
            wdata_q <= 8'h00;
        end else begin
            done <= 1'b0; // done is a one-cycle pulse; default is low until completion

            case (state)
                S_IDLE: begin
                    if (start) begin
                        // Timing: at the active clock edge, capture command and assert req.
                        rw_q    <= rw;
                        addr_q  <= addr;
                        wdata_q <= wdata;
                        req     <= 1'b1; // Protocol: request is now active
                        state   <= S_REQ;
                    end
                end

                S_REQ: begin
                    if (gnt) begin
                        // Timing: on the cycle when the grant arrives, the master begins the
                        // bus transaction by sending the HEADER beat.
                        valid <= 1'b1;
                        dout  <= {rw_q, 1'b0, addr_q[13:8]}; // HEADER = {RW, 0, A[13:8]}
                        state <= S_HDR;
                    end
                end

                S_HDR: begin
                    // Timing: next bus beat carries the low byte of the address.
                    dout  <= addr_q[7:0];
                    state <= S_ALO;
                end

                S_ALO: begin
                    if (rw_q) begin
                        // Timing: write transfer continues to WDATA beat.
                        dout  <= wdata_q;
                        state <= S_DAT;
                    end else begin
                        // Timing: read transfer ends address phase and waits for response.
                        valid <= 1'b0;
                        dout  <= 8'h00;
                        state <= S_WAIT;
                    end
                end

                S_DAT: begin
                    // Timing: WDATA beat is complete; the master is now waiting for the
                    // slave response and the bus to finish processing the write.
                    valid <= 1'b0;
                    dout  <= 8'h00;
                    state <= S_WAIT;
                end

                S_WAIT: begin
                    if (gnt && bus_ready) begin
                        // Timing: response is valid at bus_ready; capture the read data.
                        if (!rw_q) rdata <= bus_rdata;
                        req  <= 1'b0; // Protocol: release the request after completion
                        done <= 1'b1; // One-cycle completion pulse
                        state <= S_REL;
                    end
                end

                S_REL: begin
                    // Timing: wait until the grant is released before returning to idle.
                    if (!gnt) state <= S_IDLE;
                end

                default: begin
                    // Safety: unexpected state values return to idle.
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // --------------------------------------------------------------------------
    // Block: Busy Status
    // --------------------------------------------------------------------------
    assign busy = (state != S_IDLE);
endmodule
