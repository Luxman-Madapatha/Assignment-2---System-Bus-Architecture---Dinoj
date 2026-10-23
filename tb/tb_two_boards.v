// tb_two_boards.v : connects the two DE0 wrappers as the ribbon cables do
// and runs a write/read and a two-master request through the real wrappers.
`timescale 1ns/1ps
module tb_two_boards;
    reg        clk50 = 0;  always #10 clk50 = ~clk50;
    reg  [2:0] btnA = 3'b111, btnB = 3'b111;
    reg  [9:0] swA  = 10'd0,  swB  = 10'd0;
    wire [31:0] g0, g1;  wire [1:0] c0, c1;      // the two ribbon cables
    wire [9:0] ledA, ledB;
    wire [6:0] a0,a1,a2,a3,b0,b1,b2,b3; wire [3:0] adp, bdp;
    integer errors = 0;

    de0_bus_board  A (.CLOCK_50(clk50), .BUTTON(btnA), .SW(swA), .LEDG(ledA),
        .HEX0_D(a0), .HEX1_D(a1), .HEX2_D(a2), .HEX3_D(a3),
        .HEX0_DP(adp[0]), .HEX1_DP(adp[1]), .HEX2_DP(adp[2]), .HEX3_DP(adp[3]),
        .GPIO0_D(g0), .GPIO0_CLKOUT(c0), .GPIO1_D(g1), .GPIO1_CLKOUT(c1));
    de0_node_board B (.CLOCK_50(clk50), .BUTTON(btnB), .SW(swB), .LEDG(ledB),
        .HEX0_D(b0), .HEX1_D(b1), .HEX2_D(b2), .HEX3_D(b3),
        .HEX0_DP(bdp[0]), .HEX1_DP(bdp[1]), .HEX2_DP(bdp[2]), .HEX3_DP(bdp[3]),
        .GPIO0_D(g0), .GPIO0_CLKOUT(c0), .GPIO1_D(g1), .GPIO1_CLKOUT(c1));

    task press(input [2:0] mask);
        begin btnB = ~mask; #8000; btnB = 3'b111; #20000; end
    endtask

    initial begin
        btnA[0] = 0; #5000; btnA[0] = 1; #10000;
        if (^g0 === 1'bx || ^g1 === 1'bx) begin errors=errors+1; $display("FAIL: X/Z on cable"); end
        swB = {1'b1, 2'b01, 7'h2A};  press(3'b001);       // M0 write 0x2A -> 0x102A
        swB = {1'b0, 2'b01, 7'h2A};  press(3'b001);       // M0 read
        if (B.u_m0.rdata !== 8'h2A) begin errors=errors+1; $display("FAIL M0 rd %h", B.u_m0.rdata); end
        swB = {1'b1, 2'b10, 7'h05};  press(3'b100);       // both write 0x2005
        swB = {1'b0, 2'b10, 7'h05};  press(3'b010);       // M1 read
        if (B.u_m1.rdata !== 8'h85) begin errors=errors+1; $display("FAIL M1 rd %h", B.u_m1.rdata); end
        swB = {1'b0, 2'b11, 7'h00};  press(3'b001);       // unmapped read
        if (B.u_m0.rdata !== 8'hEE || !A.dec_err) begin errors=errors+1; $display("FAIL unmapped"); end
        $display("TWO-BOARD TEST %0s (%0d errors)", errors ? "FAILED" : "PASSED", errors);
        $finish;
    end
endmodule
