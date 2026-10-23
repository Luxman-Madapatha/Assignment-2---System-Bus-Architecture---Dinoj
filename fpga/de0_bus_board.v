//============================================================================
// de0_bus_board.v : BOARD A  -  the bus (arbiter + decoder + muxes)
//
//  * Generates the bus clock from CLOCK_50:
//        SW[0] = 0 -> 1 MHz      SW[0] = 1 -> 4 Hz (watch every beat)
//  * Sends the INVERTED bus clock to board B. Board B therefore launches
//    and samples half a period away from board A, which gives half a clock
//    of setup and hold margin across the ribbon cable in both directions.
//    All RTL on both boards is still posedge-clocked.
//  * BUTTON[0] = system reset (also sent to board B)
//
//  Connect GPIO0 <-> GPIO0 and GPIO1 <-> GPIO1 of the two boards with
//  straight 40-pin ribbon cables. Port names follow the DE0 System Builder,
//  so its generated .qsf supplies the pin locations.
//
//  Display:  HEX1:HEX0 = byte on the slave bus (s_wdata)
//            HEX3:HEX2 = last m_rdata
//  LEDG: 0 gnt0, 1 gnt1, 2 busy, 3 dec_err, 5:4 s_sel, 6 s_valid,
//        7 m_ready, 9 slow-clock mode
//============================================================================
module de0_bus_board (
    input  wire        CLOCK_50,
    input  wire [2:0]  BUTTON,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDG,
    output wire [6:0]  HEX0_D, HEX1_D, HEX2_D, HEX3_D,
    output wire        HEX0_DP, HEX1_DP, HEX2_DP, HEX3_DP,
    inout  wire [31:0] GPIO0_D,
    inout  wire [1:0]  GPIO0_CLKOUT,
    inout  wire [31:0] GPIO1_D,
    inout  wire [1:0]  GPIO1_CLKOUT
);
    //---------------- bus clock generation ----------------
    reg [22:0] div_cnt = 23'd0;
    reg        bus_clk = 1'b0;
    wire [22:0] div_lim = SW[0] ? 23'd6_249_999 : 23'd24;  // 4 Hz : 1 MHz
    always @(posedge CLOCK_50) begin
        if (div_cnt >= div_lim) begin div_cnt <= 23'd0; bus_clk <= ~bus_clk; end
        else                          div_cnt <= div_cnt + 23'd1;
    end

    wire rst_n;
    reset_sync u_rst (.clk(bus_clk), .rst_n_in(BUTTON[0]), .rst_n_out(rst_n));

    //---------------- signals ----------------
    wire       m0_req, m0_valid, m0_gnt, m1_req, m1_valid, m1_gnt;
    wire [7:0] m0_dout, m1_dout, m_rdata, s_wdata, s0_rdata, s1_rdata, s2_rdata;
    wire       m_ready, s_valid, busy, dec_err;
    wire [1:0] s_sel;

    //---------------- inter-board wiring (A side) ----------------
    // A -> B (outputs)
    assign GPIO0_D[7:0]   = s_wdata;
    assign GPIO0_D[8]     = s_valid;
    assign GPIO0_D[10:9]  = s_sel;
    assign GPIO0_D[18:11] = m_rdata;
    assign GPIO0_D[19]    = m_ready;
    assign GPIO0_D[20]    = m0_gnt;
    assign GPIO0_D[21]    = m1_gnt;
    assign GPIO0_D[22]    = ~bus_clk;          // node clock (inverted)
    assign GPIO0_D[23]    = rst_n;             // system reset
    // B -> A (inputs, tri-stated here)
    assign GPIO0_D[31:24] = 8'bz;
    assign GPIO0_CLKOUT   = 2'bz;
    assign GPIO1_D        = 32'bz;
    assign GPIO1_CLKOUT   = 2'bz;

    assign s0_rdata = GPIO0_D[31:24];
    assign m0_req   = GPIO0_CLKOUT[0];
    assign m1_req   = GPIO0_CLKOUT[1];
    assign m0_dout  = GPIO1_D[7:0];
    assign m0_valid = GPIO1_D[8];
    assign m1_dout  = GPIO1_D[16:9];
    assign m1_valid = GPIO1_D[17];
    assign s1_rdata = GPIO1_D[25:18];
    assign s2_rdata = {GPIO1_CLKOUT[1:0], GPIO1_D[31:26]};

    //---------------- the bus ----------------
    bus_top u_bus (
        .clk(bus_clk), .rst_n(rst_n),
        .m0_req(m0_req), .m0_valid(m0_valid), .m0_dout(m0_dout), .m0_gnt(m0_gnt),
        .m1_req(m1_req), .m1_valid(m1_valid), .m1_dout(m1_dout), .m1_gnt(m1_gnt),
        .m_rdata(m_rdata), .m_ready(m_ready),
        .s_wdata(s_wdata), .s_valid(s_valid), .s_sel(s_sel),
        .s0_rdata(s0_rdata), .s1_rdata(s1_rdata), .s2_rdata(s2_rdata),
        .busy(busy), .dec_err(dec_err));

    //---------------- status display ----------------
    assign LEDG = {SW[0], 1'b0, m_ready, s_valid, s_sel, dec_err, busy, m1_gnt, m0_gnt};
    seg7 u_h0 (.hex(s_wdata[3:0]), .seg(HEX0_D));
    seg7 u_h1 (.hex(s_wdata[7:4]), .seg(HEX1_D));
    seg7 u_h2 (.hex(m_rdata[3:0]), .seg(HEX2_D));
    seg7 u_h3 (.hex(m_rdata[7:4]), .seg(HEX3_D));
    assign {HEX3_DP, HEX2_DP, HEX1_DP, HEX0_DP} = 4'b1111;
endmodule
