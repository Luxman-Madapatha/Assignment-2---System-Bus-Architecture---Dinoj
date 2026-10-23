//============================================================================
// arbiter.v : Fixed-priority, non-preemptive arbiter for 2 masters
//
// The bus is a shared resource. Only one master may be granted ownership at a
// time. This arbiter implements a simple static-priority policy:
//   - Master 0 has the highest priority.
//   - Master 1 has the lower priority.
//   - Once a master is granted the bus, it retains ownership until it releases
//     its request.
//   - The arbiter is non-preemptive; it does not interrupt an ongoing transfer.
//
// State encoding:
//   IDLE = 2'b00   -> no bus owner
//   M0   = 2'b01   -> grant to master 0
//   M1   = 2'b10   -> grant to master 1
//
// The state bit ordering is intentionally chosen to match the grant outputs:
//   state[0] -> gnt0
//   state[1] -> gnt1
//
// A synchronous rising-edge clock is used, with an asynchronous active-low
// reset (rst_n) to bring the state machine back to IDLE.
//============================================================================
module arbiter (
    input  wire clk,
    input  wire rst_n,

    // Request lines from the two masters.
    // A request is asserted when the master wants to use the shared bus.
    input  wire req0,
    input  wire req1,

    // Grant lines to the masters.
    // Exactly one grant may be high at any given time.
    output wire gnt0,
    output wire gnt1,

    // busy is asserted whenever the arbiter is in an active grant state.
    output wire busy
);

    // State encoding matches the required grant outputs.
    localparam [1:0] IDLE = 2'b00,
                     M0   = 2'b01,
                     M1   = 2'b10;

    // State and next-state registers.
    // The current state is the actual grant state of the arbiter.
    reg [1:0] state, next_state;

    // --------------------------------------------------------------------------
    // Next-state generation.
    // The arbiter gives priority to M0 whenever it requests the bus.
    // If M0 is not active, M1 is granted when it requests the bus.
    // If neither master requests the bus, the arbiter returns to IDLE.
    // Once a grant is active, the bus remains owned by that master until the
    // request is removed. This is non-preemptive arbitration.
    // --------------------------------------------------------------------------
    always @(*) begin
        case (state)
            IDLE: begin
                if      (req0) next_state = M0;     // Highest-priority request wins
                else if (req1) next_state = M1;     // Lower-priority request wins next
                else           next_state = IDLE;   // No request: bus idle
            end

            M0: begin
                if      (req0) next_state = M0;     // M0 remains master while it keeps req0 high
                else if (req1) next_state = M1;     // Allow handoff when M0 releases bus
                else           next_state = IDLE;   // No active request: release bus
            end

            M1: begin
                if      (req1) next_state = M1;     // M1 keeps ownership while it requests
                else if (req0) next_state = M0;     // M0 can grab bus when M1 releases it
                else           next_state = IDLE;   // No request: clear bus ownership
            end

            default: next_state = IDLE; // Safe default for unknown state values
        endcase
    end

    // --------------------------------------------------------------------------
    // State register update.
    // Synchronous state machine: the new state is loaded on each rising clock
    // edge. The active-low reset returns the logic to IDLE immediately.
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; // Reset clears bus ownership
        end else begin
            state <= next_state; // Advance to next arbitration state
        end
    end

    // --------------------------------------------------------------------------
    // Grant outputs and busy flag.
    // The state register itself is the grant vector. This keeps the implementation
    // simple and avoids extra grant decoding logic.
    // --------------------------------------------------------------------------
    assign gnt0 = state[0]; // state = M0 -> gnt0 = 1
    assign gnt1 = state[1]; // state = M1 -> gnt1 = 1
    assign busy = |state;    // busy = 1 when in M0 or M1 state
endmodule
