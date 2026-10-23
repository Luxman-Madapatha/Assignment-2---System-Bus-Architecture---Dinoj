//============================================================================
// tb_arbiter.v : self-checking testbench for the priority arbiter
//   T1 Idle                       : no requests -> no grant
//   T2 Single request (M0)        : gnt0 after one clock, release -> idle
//   T3 Single request (M1)
//   T4 Two simultaneous requests  : M0 wins, M1 gets bus when M0 releases
//   T5 M0 requests while M1 owns  : no preemption, hand-over on release
//   T6 Async reset while granted  : grant clears without a clock edge
//   Monitor: gnt0 and gnt1 are never high together
//============================================================================
`timescale 1ns/1ps
module tb_arbiter;
    reg  clk = 1'b0, rst_n = 1'b0, req0 = 1'b0, req1 = 1'b0;
    wire gnt0, gnt1, busy;
    integer errors = 0;

    arbiter dut (.clk(clk), .rst_n(rst_n), .req0(req0), .req1(req1),
                 .gnt0(gnt0), .gnt1(gnt1), .busy(busy));

    always #10 clk = ~clk;                      // 50 MHz

    task check(input exp0, input exp1, input [8*40-1:0] msg);
        begin
            if (gnt0 !== exp0 || gnt1 !== exp1) begin
                errors = errors + 1;
                $display("  FAIL @%0t %0s : gnt0=%b gnt1=%b (exp %b %b)",
                         $time, msg, gnt0, gnt1, exp0, exp1);
            end else
                $display("  pass @%0t %0s : gnt0=%b gnt1=%b",
                         $time, msg, gnt0, gnt1);
        end
    endtask

    always @(posedge clk)
        if (gnt0 & gnt1) begin
            errors = errors + 1;
            $display("  FAIL @%0t both grants high", $time);
        end

    initial begin
        $dumpfile("tb_arbiter.vcd");
        $dumpvars(0, tb_arbiter);

        $display("T0 Reset");
        #25 check(0, 0, "during reset");
        rst_n = 1'b1;

        $display("T1 Idle");
        repeat (5) @(negedge clk);
        check(0, 0, "idle, no requests");

        $display("T2 Single request M0");
        req0 = 1;  @(negedge clk); check(1, 0, "req0 -> gnt0");
        repeat (3) @(negedge clk); check(1, 0, "M0 holds bus");
        req0 = 0;  @(negedge clk); check(0, 0, "release -> idle");

        $display("T3 Single request M1");
        req1 = 1;  @(negedge clk); check(0, 1, "req1 -> gnt1");
        req1 = 0;  @(negedge clk); check(0, 0, "release -> idle");

        $display("T4 Two simultaneous requests");
        req0 = 1; req1 = 1; @(negedge clk); check(1, 0, "both -> M0 wins");
        repeat (2) @(negedge clk);          check(1, 0, "M1 waits");
        req0 = 0;           @(negedge clk); check(0, 1, "hand-over to M1");
        req1 = 0;           @(negedge clk); check(0, 0, "release -> idle");

        $display("T5 No preemption");
        req1 = 1;           @(negedge clk); check(0, 1, "M1 granted");
        req0 = 1;           @(negedge clk); check(0, 1, "M0 req, M1 keeps bus");
        @(negedge clk);                     check(0, 1, "still M1");
        req1 = 0;           @(negedge clk); check(1, 0, "hand-over to M0");
        req0 = 0;           @(negedge clk); check(0, 0, "release -> idle");

        $display("T6 Asynchronous reset");
        req0 = 1;           @(negedge clk); check(1, 0, "M0 granted");
        #3 rst_n = 0; #1                    check(0, 0, "async reset (no edge)");
        @(negedge clk);                     check(0, 0, "held in reset");
        rst_n = 1; req0 = 0; @(negedge clk);check(0, 0, "after reset");

        $display("\nARBITER TEST %0s (%0d errors)",
                 errors ? "FAILED" : "PASSED", errors);
        $finish;
    end
endmodule
