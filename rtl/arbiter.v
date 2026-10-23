//============================================================================
// arbiter.v : Fixed-priority, non-preemptive arbiter for 2 masters
//   - Master 0 has the HIGHER priority, Master 1 the lower
//   - Once granted, a master keeps the bus until it drops its req
//     (no preemption in the middle of a transaction)
//   - On release, the arbiter re-arbitrates in the same clock
//     (direct M0 -> M1 hand-over, no idle cycle)
//   - Asynchronous active-low reset, rising-edge clock
//   - The state register IS the grant vector {gnt1,gnt0}, so the
//     grants come straight from flip-flops (glitch free)
//============================================================================
module arbiter (
    input  wire clk,
    input  wire rst_n,
    input  wire req0,     // request from master 0 (high priority)
    input  wire req1,     // request from master 1 (low priority)
    output wire gnt0,     // grant to master 0
    output wire gnt1,     // grant to master 1
    output wire busy      // bus is owned by some master
);
    localparam [1:0] IDLE = 2'b00,
                     M0   = 2'b01,
                     M1   = 2'b10;

    reg [1:0] state, next_state;

    // next-state logic
    always @(*) begin
        case (state)
            IDLE   : if      (req0) next_state = M0;     // priority: M0 first
                     else if (req1) next_state = M1;
                     else           next_state = IDLE;
            M0     : if      (req0) next_state = M0;     // hold until release
                     else if (req1) next_state = M1;
                     else           next_state = IDLE;
            M1     : if      (req1) next_state = M1;     // no preemption
                     else if (req0) next_state = M0;
                     else           next_state = IDLE;
            default:                next_state = IDLE;
        endcase
    end

    // state register: async reset, posedge clock
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    assign gnt0 = state[0];
    assign gnt1 = state[1];
    assign busy = |state;
endmodule
