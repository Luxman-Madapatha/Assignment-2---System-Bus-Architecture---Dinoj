//============================================================================
// master_model.v : behavioral bus master model
//
// This module models a single bus master in a very simple but realistic way.
// It accepts a command from the testbench or a higher-level controller, waits
// for bus ownership, drives the transaction sequence onto the shared bus, and
// captures the returned read data when the transfer is complete.
//
// Command sequence:
//   1. start pulse is received while the master is idle
//   2. request is asserted on the bus
//   3. bus grant is awaited
//   4. HEADER beat is driven
//   5. ADDR_LO beat is driven
//   6. for writes, WDATA beat is driven
//   7. wait for bus_ready after the slave response delay
//   8. capture read data if this is a read
//   9. release the request and return to idle
//
// Reset is asynchronous active-low. Clocking is rising-edge sensitive.
//============================================================================
module master_model (
    input  wire        clk,
    input  wire        rst_n,

    // ---- command side (UI or testbench) ----
    input  wire        start,      // one-cycle pulse accepted only when idle
    input  wire        rw,         // 1 = write, 0 = read
    input  wire [13:0] addr,       // full 14-bit address
    input  wire [7:0]  wdata,      // write data for write transactions

    // ---- status outputs ----
    output reg  [7:0]  rdata,      // last successfully read data
    output reg         done,       // one-cycle pulse when transaction completes
    output wire        busy,

    // ---- bus side ----
    output reg         req,        // request line asserted when master wants bus
    input  wire        gnt,        // grant from bus arbiter
    output reg         valid,      // indicates the bus beat is valid
    output reg  [7:0]  dout,       // bus data to drive onto the shared bus
    input  wire [7:0]  bus_rdata,  // returned data from the selected slave
    input  wire        bus_ready   // response valid signal from the bus
);

    // --------------------------------------------------------------------------
    // State machine encoding.
    // This finite-state machine models the master's expected transaction flow.
    // --------------------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0,  // waiting for a command from the testbench
                     S_REQ  = 3'd1,  // request asserted, waiting for grant
                     S_HDR  = 3'd2,  // drive HEADER beat
                     S_ALO  = 3'd3,  // drive ADDR_LO beat
                     S_DAT  = 3'd4,  // drive WDATA beat for writes
                     S_WAIT = 3'd5,  // wait for bus_ready
                     S_REL  = 3'd6;  // drop request and wait for grant release

    reg [2:0]  state;
    reg        rw_q;
    reg [13:0] addr_q;
    reg [7:0]  wdata_q;

    // --------------------------------------------------------------------------
    // Main state-machine behavior.
    // The master is responsible for generating the correct bus protocol sequence.
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset the master to a known idle state.
            state <= S_IDLE;
            req   <= 1'b0;
            valid <= 1'b0;
            dout  <= 8'h00;
            rdata <= 8'h00;
            done  <= 1'b0;
            rw_q  <= 1'b0;
            addr_q <= 14'd0;
            wdata_q <= 8'h00;
        end else begin
            done <= 1'b0; // done is a one-cycle pulse only; default is low

            case (state)
                S_IDLE: begin
                    if (start) begin
                        // Capture the command parameters before the request is sent.
                        rw_q    <= rw;
                        addr_q  <= addr;
                        wdata_q <= wdata;
                        req     <= 1'b1; // Assert bus request
                        state   <= S_REQ;
                    end
                end

                S_REQ: begin
                    if (gnt) begin
                        // Once granted, the master starts the transaction stream.
                        valid <= 1'b1;
                        dout  <= {rw_q, 1'b0, addr_q[13:8]}; // HEADER = {RW, 0, A[13:8]}
                        state <= S_HDR;
                    end
                end

                S_HDR: begin
                    // Drive the low address byte on the next bus beat.
                    dout  <= addr_q[7:0];
                    state <= S_ALO;
                end

                S_ALO: begin
                    if (rw_q) begin
                        // A write operation sends write data after the address-low beat.
                        dout  <= wdata_q;
                        state <= S_DAT;
                    end else begin
                        // A read operation does not send WDATA; the bus waits for the
                        // slave response instead.
                        valid <= 1'b0;
                        dout  <= 8'h00;
                        state <= S_WAIT;
                    end
                end

                S_DAT: begin
                    // Write transaction data phase is complete. Stop driving valid
                    // data and wait for the slave to acknowledge the transaction.
                    valid <= 1'b0;
                    dout  <= 8'h00;
                    state <= S_WAIT;
                end

                S_WAIT: begin
                    if (gnt && bus_ready) begin
                        // The bus has completed the transfer. Capture read data for
                        // read transactions and then drop the request.
                        if (!rw_q) rdata <= bus_rdata;
                        req  <= 1'b0;
                        done <= 1'b1;
                        state <= S_REL;
                    end
                end

                S_REL: begin
                    // Wait until the bus grant is released before returning to idle.
                    if (!gnt) state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // The master is considered busy while it is not in the idle state.
    assign busy = (state != S_IDLE);
endmodule
