//============================================================================
// addr_decoder.v : 14-bit address decoder for 3 slaves
//
// This module decodes the upper address bits of a bus transaction and selects
// which slave should respond. The system address space is 14 bits wide:
//   A[13:0] = 16 KB total address space
//
// The memory map is defined as:
//   Slave 0 : 4 KB  0x0000 - 0x0FFF   A[13:12] = 00
//   Slave 1 : 4 KB  0x1000 - 0x1FFF   A[13:12] = 01
//   Slave 2 : 2 KB  0x2000 - 0x27FF   A[13:12] = 10 and A[11] = 0
//   unmapped:       0x2800 - 0x3FFF   -> hit = 0
//
// The module outputs:
//   - slave_sel : one-hot selection vector for the three slave devices
//   - sel_code  : compact 2-bit encoded select value used by the bus
//   - hit       : indicates whether the address is mapped to a valid slave
//
// Note:
//   The decoder only needs the upper address bits A[13:8], which are carried in
//   the bus HEADER beat. The lower address bits are handled by the selected slave
//   during the address-low phase of the transaction.
//============================================================================
module addr_decoder (
    input  wire [5:0] addr_hi,     // A[13:8] from the header beat

    // One-hot selection vector for slave devices.
    // bit 0 -> S0, bit 1 -> S1, bit 2 -> S2
    output reg  [2:0] slave_sel,

    // 2-bit encoded select code used by the bus.
    // 0 = no slave selected, 1 = S0, 2 = S1, 3 = S2
    output reg  [1:0] sel_code,

    // hit = 1 only if the address maps to a valid slave region.
    output wire       hit
);

    // --------------------------------------------------------------------------
    // Decode logic.
    // This is a purely combinational assignment: the output depends immediately on
    // the current value of addr_hi.
    // --------------------------------------------------------------------------
    always @(*) begin
        slave_sel = 3'b000; // Default: no slave selected
        sel_code  = 2'd0;  // Default code: no selection

        case (addr_hi[5:4]) // Decode A[13:12]
            2'b00: begin
                slave_sel = 3'b001; // S0 selected
                sel_code = 2'd1;    // encode S0 as 1
            end

            2'b01: begin
                slave_sel = 3'b010; // S1 selected
                sel_code = 2'd2;    // encode S1 as 2
            end

            2'b10: begin
                // S2 occupies only half of the 2 KB segment when A[11] = 0.
                // The address must satisfy A[11] = 0 to remain within S2.
                if (addr_hi[3] == 1'b0) begin
                    slave_sel = 3'b100; // S2 selected
                    sel_code = 2'd3;    // encode S2 as 3
                end
            end

            default: begin
                // All other address groups are unmapped.
                // Leave slave_sel and sel_code at the default values.
            end
        endcase
    end

    // A valid address is one that maps to a slave region.
    // Since the one-hot vector is all zero for unmapped regions, OR-reducing it
    // gives a hit indication.
    assign hit = |slave_sel;
endmodule
