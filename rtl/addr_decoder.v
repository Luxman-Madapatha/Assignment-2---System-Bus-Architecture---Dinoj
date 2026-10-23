//============================================================================
// addr_decoder.v : 14-bit address decoder for 3 slaves
//   Global address A[13:0] (16 KB space). The decoder only needs A[13:8],
//   which is carried in the header beat.
//
//     Slave 0 : 4 KB  0x0000 - 0x0FFF   A[13:12] = 00
//     Slave 1 : 4 KB  0x1000 - 0x1FFF   A[13:12] = 01
//     Slave 2 : 2 KB  0x2000 - 0x27FF   A[13:12] = 10 and A[11] = 0
//     unmapped:       0x2800 - 0x3FFF   -> hit = 0
//
//   Outputs a one-hot select and a 2-bit select code
//   (the code is what travels to the slave board: 0 = none).
//============================================================================
module addr_decoder (
    input  wire [5:0] addr_hi,     // A[13:8]
    output reg  [2:0] slave_sel,   // one-hot {S2,S1,S0}
    output reg  [1:0] sel_code,    // 0:none 1:S0 2:S1 3:S2
    output wire       hit          // address is mapped
);
    always @(*) begin
        slave_sel = 3'b000;
        sel_code  = 2'd0;
        case (addr_hi[5:4])                     // A[13:12]
            2'b00: begin slave_sel = 3'b001; sel_code = 2'd1; end
            2'b01: begin slave_sel = 3'b010; sel_code = 2'd2; end
            2'b10: if (addr_hi[3] == 1'b0) begin // A[11] = 0 -> 2 KB
                       slave_sel = 3'b100;  sel_code = 2'd3;
                   end
            default: ;                          // unmapped
        endcase
    end
    assign hit = |slave_sel;
endmodule
