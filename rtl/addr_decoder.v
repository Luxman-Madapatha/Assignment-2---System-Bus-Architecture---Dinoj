//============================================================================
// arbiter.v : Fixed-priority, non-preemptive arbiter for 2 masters
//
// Functional summary:
//   - M0 has higher priority than M1.
//   - Only one master is granted access at any time.
//   - The grant remains active until the current request is released.
//   - No mid-transaction preemption is allowed.
//   - The bus is idle when no master requests ownership.
//
// Timing model:
//   - Rising-edge clocked state machine.
//   - Asynchronous active-low reset (rst_n).
//   - Grant outputs are directly driven from the state register.
//============================================================================
module arbiter (
    input  wire clk,
    input  wire rst_n,

    // --------------------------------------------------------------------------
    // Input request interfaces.
    // Each master asserts reqN when it wants exclusive access to the shared bus.
    // --------------------------------------------------------------------------
    input  wire req0,
    input  wire req1,

    // --------------------------------------------------------------------------
    // Grant outputs.
    // Exactly one grant may be asserted at any time.
    // --------------------------------------------------------------------------
    output wire gnt0,
    output wire gnt1,

    // --------------------------------------------------------------------------
    // Busy flag.
    // busy = 1 indicates that the bus is currently owned by M0 or M1.
    // --------------------------------------------------------------------------
    output wire busy
);

    // --------------------------------------------------------------------------
    // State encoding.
    // The state value is also the grant vector, which keeps the logic compact and
    // ensures glitch-free grant outputs.
    // --------------------------------------------------------------------------
    localparam [1:0] IDLE = 2'b00,
                     M0   = 2'b01,
                     M1   = 2'b10;

    // --------------------------------------------------------------------------
    // State and next-state registers.
    // state represents the current bus owner.
    // next_state is computed combinationally before the next clock edge.
    // --------------------------------------------------------------------------
    reg [1:0] state, next_state;

    // --------------------------------------------------------------------------
    // Block: Next-State Logic
    // --------------------------------------------------------------------------
    // Priority policy:
    //   1. If M0 requests, M0 wins immediately.
    //   2. Else if M1 requests, M1 wins.
    //   3. Else the bus becomes idle.
    //
    // Timing semantics:
    //   - IDLE -> M0 when req0 is high at the clock edge.
    //   - IDLE -> M1 when req1 is high and req0 is low.
    //   - M0 -> M0 while req0 remains high.
    //   - M0 -> M1 when req0 drops and req1 is high.
    //   - M1 -> M1 while req1 remains high.
    //   - M1 -> M0 when req1 drops and req0 is high.
    // --------------------------------------------------------------------------
    always @(*) begin
        case (state)
            IDLE: begin
                if      (req0) next_state = M0;     // Timing: M0 request is granted at next active edge
                else if (req1) next_state = M1;     // Timing: M1 request is granted at next active edge
                else           next_state = IDLE;   // Timing: bus remains idle, no active grant
            end

            M0: begin
                if      (req0) next_state = M0;     // Timing: hold grant while M0 keeps req0 asserted
                else if (req1) next_state = M1;     // Timing: M1 gains grant after M0 releases the bus
                else           next_state = IDLE;   // Timing: grant is released when req0 goes low
            end

            M1: begin
                if      (req1) next_state = M1;     // Timing: hold grant while M1 keeps req1 asserted
                else if (req0) next_state = M0;     // Timing: M0 regains grant when M1 releases the bus
                else           next_state = IDLE;   // Timing: no request -> bus is idle
            end

            default: next_state = IDLE; // Safe fail-safe state for unknown condition
        endcase
    end

    // --------------------------------------------------------------------------
    // Block: State Register Update
    // --------------------------------------------------------------------------
    // The arbiter state changes only on the rising clock edge. This ensures a
    // synchronous state machine and clean grant transitions.
    // --------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; // Timing: reset clears bus ownership immediately
        end else begin
            state <= next_state; // Timing: next state is loaded at the next active edge
        end
    end

    // --------------------------------------------------------------------------
    // Block: Output Generation
    // --------------------------------------------------------------------------
    assign gnt0 = state[0]; // state = M0 -> gnt0 = 1, otherwise 0
    assign gnt1 = state[1]; // state = M1 -> gnt1 = 1, otherwise 0
    assign busy = |state;   // busy = 1 when in M0 or M1 grant states
endmodule
