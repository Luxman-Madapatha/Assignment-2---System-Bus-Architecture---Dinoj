//============================================================================
// tb_addr_decoder.v : exhaustive check of the address map
//   All 16384 addresses are decoded and compared with a range-based
//   reference model; boundary addresses are printed for the report.
//============================================================================
`timescale 1ns/1ps
module tb_addr_decoder;
    reg  [13:0] addr;
    wire [2:0]  slave_sel;
    wire [1:0]  sel_code;
    wire        hit;
    integer     a, errors = 0;
    reg  [2:0]  exp_sel;
    reg  [1:0]  exp_code;

    addr_decoder dut (.addr_hi(addr[13:8]), .slave_sel(slave_sel),
                      .sel_code(sel_code), .hit(hit));

    // reference model written from the address map, not from the RTL
    task ref_model(input [13:0] ad);
        begin
            if      (ad <= 14'h0FFF) begin exp_sel = 3'b001; exp_code = 2'd1; end
            else if (ad <= 14'h1FFF) begin exp_sel = 3'b010; exp_code = 2'd2; end
            else if (ad <= 14'h27FF) begin exp_sel = 3'b100; exp_code = 2'd3; end
            else                     begin exp_sel = 3'b000; exp_code = 2'd0; end
        end
    endtask

    task show(input [13:0] ad);
        begin
            addr = ad; #1;
            $display("  0x%04h : sel=%b code=%0d hit=%b", ad, slave_sel, sel_code, hit);
        end
    endtask

    initial begin
        $dumpfile("tb_addr_decoder.vcd");
        $dumpvars(0, tb_addr_decoder);

        $display("Boundary addresses");
        show(14'h0000); show(14'h0FFF);         // slave 0
        show(14'h1000); show(14'h1FFF);         // slave 1
        show(14'h2000); show(14'h27FF);         // slave 2
        show(14'h2800); show(14'h3FFF);         // unmapped

        $display("Exhaustive sweep of 16384 addresses");
        for (a = 0; a < 16384; a = a + 1) begin
            addr = a; #1;
            ref_model(a);
            if (slave_sel !== exp_sel || sel_code !== exp_code ||
                hit !== (|exp_sel) || ((slave_sel & (slave_sel - 3'b001)) != 3'b000)) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("  FAIL 0x%04h sel=%b code=%0d", a, slave_sel, sel_code);
            end
        end
        $display("\nADDRESS DECODER TEST %0s (%0d errors)",
                 errors ? "FAILED" : "PASSED", errors);
        $finish;
    end
endmodule
