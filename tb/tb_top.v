//============================================================================
// tb_top.v : top-level system verification
//   bus_top + 2 x master_model + 3 x slave_model (4K, 4K, 2K)
//   a) Reset test        : outputs clear, async reset during a transfer
//   b) Idle condition    : no activity while nobody requests
//   c) One master request: writes/reads to every slave, boundaries,
//                          unmapped address (no lock-up), both masters
//   d) Two master requests: simultaneous (priority), and no preemption
//
//   NODE_CLK_INV = 1 clocks the masters/slaves on the inverted clock,
//   which is how the two-board demo is wired (see fpga/de0_bus_board.v).
//============================================================================
`timescale 1ns/1ps
module tb_top;
    parameter NODE_CLK_INV = 0;

    reg clk = 1'b0, rst_n = 1'b0;
    always #10 clk = ~clk;
    wire node_clk = NODE_CLK_INV ? ~clk : clk;

    // ---- master command interfaces ----
    reg         m0_start = 0, m0_rw = 0, m1_start = 0, m1_rw = 0;
    reg  [13:0] m0_addr = 0, m1_addr = 0;
    reg  [7:0]  m0_wdata = 0, m1_wdata = 0;
    wire [7:0]  m0_rd, m1_rd;
    wire        m0_done, m1_done, m0_busy, m1_busy;

    // ---- bus wires ----
    wire        m0_req, m0_valid, m0_gnt, m1_req, m1_valid, m1_gnt;
    wire [7:0]  m0_dout, m1_dout, m_rdata, s_wdata, s0_rd, s1_rd, s2_rd;
    wire        m_ready, s_valid, busy, dec_err;
    wire [1:0]  s_sel;

    bus_top u_bus (
        .clk(clk), .rst_n(rst_n),
        .m0_req(m0_req), .m0_valid(m0_valid), .m0_dout(m0_dout), .m0_gnt(m0_gnt),
        .m1_req(m1_req), .m1_valid(m1_valid), .m1_dout(m1_dout), .m1_gnt(m1_gnt),
        .m_rdata(m_rdata), .m_ready(m_ready),
        .s_wdata(s_wdata), .s_valid(s_valid), .s_sel(s_sel),
        .s0_rdata(s0_rd), .s1_rdata(s1_rd), .s2_rdata(s2_rd),
        .busy(busy), .dec_err(dec_err));

    master_model u_m0 (
        .clk(node_clk), .rst_n(rst_n),
        .start(m0_start), .rw(m0_rw), .addr(m0_addr), .wdata(m0_wdata),
        .rdata(m0_rd), .done(m0_done), .busy(m0_busy),
        .req(m0_req), .gnt(m0_gnt), .valid(m0_valid), .dout(m0_dout),
        .bus_rdata(m_rdata), .bus_ready(m_ready));

    master_model u_m1 (
        .clk(node_clk), .rst_n(rst_n),
        .start(m1_start), .rw(m1_rw), .addr(m1_addr), .wdata(m1_wdata),
        .rdata(m1_rd), .done(m1_done), .busy(m1_busy),
        .req(m1_req), .gnt(m1_gnt), .valid(m1_valid), .dout(m1_dout),
        .bus_rdata(m_rdata), .bus_ready(m_ready));

    slave_model #(.SLAVE_ID(2'd1), .ADDR_W(12)) u_s0 (.clk(node_clk), .rst_n(rst_n),
        .s_sel(s_sel), .s_valid(s_valid), .s_wdata(s_wdata), .s_rdata(s0_rd));
    slave_model #(.SLAVE_ID(2'd2), .ADDR_W(12)) u_s1 (.clk(node_clk), .rst_n(rst_n),
        .s_sel(s_sel), .s_valid(s_valid), .s_wdata(s_wdata), .s_rdata(s1_rd));
    slave_model #(.SLAVE_ID(2'd3), .ADDR_W(11)) u_s2 (.clk(node_clk), .rst_n(rst_n),
        .s_sel(s_sel), .s_valid(s_valid), .s_wdata(s_wdata), .s_rdata(s2_rd));

    //------------------------------------------------------------------
    // checking helpers
    //------------------------------------------------------------------
    integer errors = 0;
    integer m0_done_t, m1_done_t;
    always @(posedge node_clk) begin
        if (m0_done) m0_done_t = $time;
        if (m1_done) m1_done_t = $time;
    end

    task fail(input [8*60-1:0] msg);
        begin errors = errors + 1; $display("  FAIL @%0t %0s", $time, msg); end
    endtask

    // protocol monitor
    always @(posedge clk) if (rst_n) begin
        if (m0_gnt & m1_gnt) fail("both masters granted");
        if (m_ready & ~(m0_gnt | m1_gnt)) fail("m_ready without a grant");
    end

    // start a command on a master (drive away from the active edge)
    task issue(input integer m, input rw, input [13:0] a, input [7:0] d);
        begin
            if (m == 0) begin m0_rw = rw; m0_addr = a; m0_wdata = d; m0_start = 1; end
            else        begin m1_rw = rw; m1_addr = a; m1_wdata = d; m1_start = 1; end
        end
    endtask
    task release_start;
        begin @(negedge node_clk); m0_start = 0; m1_start = 0; end
    endtask

    task wait_idle(input integer m);
        integer n;
        begin
            n = 0;
            @(negedge node_clk);
            while ((m == 0 ? m0_busy : m1_busy) && n < 200) begin
                @(negedge node_clk); n = n + 1;
            end
            if (n >= 200) fail("timeout waiting for master");
        end
    endtask

    task write(input integer m, input [13:0] a, input [7:0] d);
        begin
            @(negedge node_clk); issue(m, 1'b1, a, d); release_start; wait_idle(m);
            $display("  M%0d WRITE 0x%04h <= 0x%02h", m, a, d);
        end
    endtask

    task read_check(input integer m, input [13:0] a, input [7:0] exp);
        reg [7:0] got;
        begin
            @(negedge node_clk); issue(m, 1'b0, a, 8'h00); release_start; wait_idle(m);
            got = (m == 0) ? m0_rd : m1_rd;
            if (got !== exp) begin
                fail("read data mismatch");
                $display("        M%0d READ 0x%04h = 0x%02h (exp 0x%02h)", m, a, got, exp);
            end else
                $display("  M%0d READ  0x%04h => 0x%02h  ok", m, a, got);
        end
    endtask

    task check_quiet(input integer cycles);
        integer k;
        begin
            for (k = 0; k < cycles; k = k + 1) begin
                @(negedge clk);
                if (m0_gnt | m1_gnt | s_valid | (s_sel != 0) | m_ready | busy)
                    fail("activity on an idle bus");
            end
        end
    endtask

    //------------------------------------------------------------------
    // test sequence
    //------------------------------------------------------------------
    initial begin
        if (NODE_CLK_INV) $dumpfile("tb_top_inv.vcd"); else $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
        $display("=== tb_top  (NODE_CLK_INV=%0d) ===", NODE_CLK_INV);

        // ---------------- a) Reset test ----------------
        $display("a) Reset test");
        #35;
        if (m0_gnt | m1_gnt | s_valid | (s_sel != 0) | m_ready | m0_req | m1_req)
            fail("outputs not cleared in reset");
        else $display("  outputs cleared while rst_n = 0");
        @(negedge clk) rst_n = 1;
        // async reset in the middle of a write
        @(negedge node_clk); issue(0, 1'b1, 14'h0100, 8'h55); release_start;
        repeat (3) @(posedge clk);
        #4 rst_n = 0; #1;
        if (m0_gnt | s_valid | (s_sel != 0) | m0_req)
            fail("async reset did not clear the bus immediately");
        else $display("  async reset mid-transfer cleared gnt/valid/sel at once");
        #30 @(negedge clk) rst_n = 1;
        read_check(0, 14'h0100, 8'h00);         // aborted write did not land

        // ---------------- b) Idle condition ----------------
        $display("b) Idle condition");
        check_quiet(20);
        $display("  20 idle cycles: no grant, no valid, no select");

        // ---------------- c) One master request ----------------
        $display("c) One master request");
        write(0, 14'h0000, 8'hA5);  read_check(0, 14'h0000, 8'hA5);   // S0 first
        write(0, 14'h0FFF, 8'h5A);  read_check(0, 14'h0FFF, 8'h5A);   // S0 last
        write(0, 14'h1000, 8'h3C);  read_check(0, 14'h1000, 8'h3C);   // S1 first
        write(1, 14'h1FFF, 8'hC3);  read_check(1, 14'h1FFF, 8'hC3);   // S1 last (M1)
        write(1, 14'h2000, 8'h96);  read_check(1, 14'h2000, 8'h96);   // S2 first
        write(1, 14'h27FF, 8'h69);  read_check(1, 14'h27FF, 8'h69);   // S2 last
        read_check(0, 14'h0000, 8'hA5);                               // no aliasing
        read_check(0, 14'h1000, 8'h3C);
        // unmapped: must complete with 0xEE and dec_err
        read_check(0, 14'h2800, 8'hEE);
        if (!dec_err) fail("dec_err not set for unmapped address");
        else $display("  unmapped 0x2800: completed, dec_err = 1");
        write(1, 14'h3FFF, 8'h11);               // unmapped write must not hang
        read_check(1, 14'h27FF, 8'h69);           // and must not corrupt S2

        // ---------------- d) Two master requests ----------------
        $display("d) Two master requests (simultaneous)");
        @(negedge node_clk);
        issue(0, 1'b1, 14'h1234, 8'h01);   // M0 -> S1
        issue(1, 1'b1, 14'h2345, 8'h02);   // M1 -> S2
        release_start;
        @(posedge clk); @(negedge clk);
        if (!(m0_gnt && !m1_gnt)) fail("M0 should win the first arbitration");
        else $display("  both requested -> gnt0 first (priority)");
        wait_idle(0); wait_idle(1);
        if (!(m0_done_t < m1_done_t)) fail("M1 finished before M0");
        else $display("  M0 done @%0t, M1 done @%0t", m0_done_t, m1_done_t);
        read_check(0, 14'h1234, 8'h01);
        read_check(1, 14'h2345, 8'h02);

        $display("d) Two masters, same address (order check)");
        @(negedge node_clk);
        issue(0, 1'b1, 14'h0042, 8'h2A);
        issue(1, 1'b1, 14'h0042, 8'hAA);
        release_start; wait_idle(0); wait_idle(1);
        read_check(0, 14'h0042, 8'hAA);           // M1 wrote last

        $display("d) M1 owns bus, M0 requests (no preemption)");
        @(negedge node_clk); issue(1, 1'b1, 14'h0800, 8'h77); release_start;
        while (!m1_gnt) @(negedge clk);
        @(negedge node_clk); issue(0, 1'b0, 14'h0800, 8'h00); release_start;
        @(negedge clk);
        if (m0_gnt) fail("M0 preempted M1");
        wait_idle(1); wait_idle(0);
        if (!(m1_done_t < m0_done_t)) fail("order wrong without preemption");
        else $display("  M1 kept the bus, M0 served next");
        if (m0_rd !== 8'h77) fail("M0 did not read M1's data");
        else $display("  M0 READ 0x0800 => 0x77 ok");

        check_quiet(5);
        $display("\nTOP-LEVEL TEST %0s (%0d errors)",
                 errors ? "FAILED" : "PASSED", errors);
        $finish;
    end

    initial begin #200000; $display("GLOBAL TIMEOUT"); $finish; end
endmodule
