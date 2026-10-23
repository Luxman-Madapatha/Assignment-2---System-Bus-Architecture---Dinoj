//============================================================================
// addr_decoder.v : 14-bit address decoder for 3 slaves
//
// Functional summary:
//   - Decodes A[13:8] from the HEADER beat.
//   - Selects the correct slave for the current address range.
//   - Produces a one-hot select output and compact selection code.
//   - Generates hit = 1 only for valid mapped addresses.
//
// Address map:
//   S0 : 0x0000 - 0x0FFF  -> A[13:12] = 00
//   S1 : 0x1000 - 0x1FFF  -> A[13:12] = 01
//   S2 : 0x2000 - 0x27FF  -> A[13:12] = 10 and A[11] = 0
//   Unmapped: 0x2800 - 0x3FFF -> no valid slave selected
//
// Timing model:
//   - This is a purely combinational decoder.
//   - Outputs update immediately with addr_hi.
//============================================================================
module addr_decoder (
    input  wire [5:0] addr_hi,  // A[13:8] from the HEADER beat

    // --------------------------------------------------------------------------
    // Output: one-hot slave selection vector.
    // bit 0 -> S0, bit 1 -> S1, bit 2 -> S2
    // --------------------------------------------------------------------------
    output reg  [2:0] slave_sel,

    // --------------------------------------------------------------------------
    // Output: compact code for bus-level slave selection.
    // 0 = no slave selected, 1 = S0, 2 = S1, 3 = S2
    // --------------------------------------------------------------------------
    output reg  [1:0] sel_code,

    // --------------------------------------------------------------------------
    // Output: hit indicator.
    // hit = 1 only if the address is mapped to a valid slave device.
    // --------------------------------------------------------------------------
    output wire       hit
);

    // --------------------------------------------------------------------------
    // Block: Decode Logic
    // --------------------------------------------------------------------------
    // The decoder operates on A[13:12] and one additional bit for the S2 range.
    // The decode is fully combinational so the slave selection is available in the
    // same cycle that addr_hi changes.
    // --------------------------------------------------------------------------
    always @(*) begin
        slave_sel = 3'b000; // Default: no valid slave selected
        sel_code  = 2'd0;  // Default code: no slave selected

        case (addr_hi[5:4]) // Decode A[13:12]
            2'b00: begin
                slave_sel = 3'b001; // Protocol: S0 selected for 0x0000 - 0x0FFF
                sel_code = 2'd1;    // Signal code for S0
            end

            2'b01: begin
                slave_sel = 3'b010; // Protocol: S1 selected for 0x1000 - 0x1FFF
                sel_code = 2'd2;    // Signal code for S1
            end

            2'b10: begin
                // S2 occupies only a restricted region in the address map.
                // A[11] must be 0 to keep the address inside the 2 KB S2 block.
                if (addr_hi[3] == 1'b0) begin
                    slave_sel = 3'b100; // Protocol: S2 selected for 0x2000 - 0x27FF
                    sel_code = 2'd3;    // Signal code for S2
                end
            end

            default: begin
                // Unmapped address region: leave outputs in their default reset state.
            end
        endcase
    end

    // --------------------------------------------------------------------------
    // Block: Validity Check
    // --------------------------------------------------------------------------
    // A valid address maps to one of the supported slave windows.
    // If all one-hot bits are zero, the region is unmapped and hit = 0.
    // --------------------------------------------------------------------------
    assign hit = |slave_sel;
endmodule
