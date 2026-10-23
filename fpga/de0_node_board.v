//============================================================================
// de0_node_board.v : BOARD B  -  2 masters + 3 slaves (4K, 4K, 2K)
//
//  Clock and reset come from board A over the ribbon cable.
//
//  User interface (both masters share the switches):
//    SW[9]   : 1 = write, 0 = read
//    SW[8:7] : target  00 = S0 (0x0000)  01 = S1 (0x1000)
//                      10 = S2 (0x2000)  11 = unmapped (0x3000)
//    SW[6:0] : address offset, also the write data
//              M0 writes {0,SW[6:0]}, M1 writes {1,SW[6:0]}
//    BUTTON[0] : start Master 0
//    BUTTON[1] : start Master 1
//    BUTTON[2] : start BOTH in the same clock (arbitration demo)
//    (in 4 Hz mode hold a button until its req LED lights)
//
//  Display:  HEX1:HEX0 = M0 last read data, HEX3:HEX2 = M1 last read data
//  LEDG: 0 m0_req, 1 m0_gnt, 2 m0_busy, 4 m1_req, 5 m1_gnt, 6 m1_busy,
//        9 out of reset
//============================================================================
module de0_node_board (
    input  wire        CLOCK_50,      // unused: clock comes from board A
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
    //---------------- clock / reset from board A ----------------
    wire node_clk = GPIO0_D[22];
    wire rst_n;
    reset_sync u_rst (.clk(node_clk), .rst_n_in(GPIO0_D[23]), .rst_n_out(rst_n));

    //---------------- signals ----------------
    wire       m0_req, m0_valid, m0_gnt, m1_req, m1_valid, m1_gnt;
    wire [7:0] m0_dout, m1_dout, m_rdata, s_wdata, s0_rdata, s1_rdata, s2_rdata;
    wire       m_ready, s_valid;
    wire [1:0] s_sel;

    //---------------- inter-board wiring (B side, mirror of A) ----------------
    // A -> B (inputs here)
    assign GPIO0_D[23:0] = 24'bz;
    assign s_wdata = GPIO0_D[7:0];
    assign s_valid = GPIO0_D[8];
    assign s_sel   = GPIO0_D[10:9];
    assign m_rdata = GPIO0_D[18:11];
    assign m_ready = GPIO0_D[19];
    assign m0_gnt  = GPIO0_D[20];
    assign m1_gnt  = GPIO0_D[21];
    // B -> A (outputs)
    assign GPIO0_D[31:24]   = s0_rdata;
    assign GPIO0_CLKOUT[0]  = m0_req;
    assign GPIO0_CLKOUT[1]  = m1_req;
    assign GPIO1_D[7:0]     = m0_dout;
    assign GPIO1_D[8]       = m0_valid;
    assign GPIO1_D[16:9]    = m1_dout;
    assign GPIO1_D[17]      = m1_valid;
    assign GPIO1_D[25:18]   = s1_rdata;
    assign GPIO1_D[31:26]   = s2_rdata[5:0];
    assign GPIO1_CLKOUT     = s2_rdata[7:6];

    //---------------- user interface ----------------
    // DE0 push-buttons are active low; synchronise and edge-detect
    reg [2:0] b_s1, b_s2, b_s3;
    always @(posedge node_clk or negedge rst_n) begin
        if (!rst_n) begin b_s1 <= 3'b0; b_s2 <= 3'b0; b_s3 <= 3'b0; end
        else        begin b_s1 <= ~BUTTON; b_s2 <= b_s1; b_s3 <= b_s2; end
    end
    wire [2:0] press    = b_s2 & ~b_s3;
    wire       m0_start = press[0] | press[2];
    wire       m1_start = press[1] | press[2];

    reg [13:0] base;
    always @(*) begin
        case (SW[8:7])
            2'b00: base = 14'h0000;
            2'b01: base = 14'h1000;
            2'b10: base = 14'h2000;
            default: base = 14'h3000;
        endcase
    end
    wire [13:0] addr = base | {7'd0, SW[6:0]};

    //---------------- masters ----------------
    wire [7:0] m0_rd, m1_rd;
    wire       m0_done, m1_done, m0_busy, m1_busy;

    master_model u_m0 (
        .clk(node_clk), .rst_n(rst_n),
        .start(m0_start), .rw(SW[9]), .addr(addr), .wdata({1'b0, SW[6:0]}),
        .rdata(m0_rd), .done(m0_done), .busy(m0_busy),
        .req(m0_req), .gnt(m0_gnt), .valid(m0_valid), .dout(m0_dout),
        .bus_rdata(m_rdata), .bus_ready(m_ready));

    master_model u_m1 (
        .clk(node_clk), .rst_n(rst_n),
        .start(m1_start), .rw(SW[9]), .addr(addr), .wdata({1'b1, SW[6:0]}),
        .rdata(m1_rd), .done(m1_done), .busy(m1_busy),
        .req(m1_req), .gnt(m1_gnt), .valid(m1_valid), .dout(m1_dout),
        .bus_rdata(m_rdata), .bus_ready(m_ready));

    //---------------- slaves ----------------
    slave_model #(.SLAVE_ID(2'd1), .ADDR_W(12)) u_s0 (.clk(node_clk), .rst_n(rst_n),
        .s_sel(s_sel), .s_valid(s_valid), .s_wdata(s_wdata), .s_rdata(s0_rdata));
    slave_model #(.SLAVE_ID(2'd2), .ADDR_W(12)) u_s1 (.clk(node_clk), .rst_n(rst_n),
        .s_sel(s_sel), .s_valid(s_valid), .s_wdata(s_wdata), .s_rdata(s1_rdata));
    slave_model #(.SLAVE_ID(2'd3), .ADDR_W(11)) u_s2 (.clk(node_clk), .rst_n(rst_n),
        .s_sel(s_sel), .s_valid(s_valid), .s_wdata(s_wdata), .s_rdata(s2_rdata));

    //---------------- display ----------------
    assign LEDG = {rst_n, 2'b00, m1_busy, m1_gnt, m1_req, 1'b0, m0_busy, m0_gnt, m0_req};
    seg7 u_h0 (.hex(m0_rd[3:0]), .seg(HEX0_D));
    seg7 u_h1 (.hex(m0_rd[7:4]), .seg(HEX1_D));
    seg7 u_h2 (.hex(m1_rd[3:0]), .seg(HEX2_D));
    seg7 u_h3 (.hex(m1_rd[7:4]), .seg(HEX3_D));
    assign {HEX3_DP, HEX2_DP, HEX1_DP, HEX0_DP} = 4'b1111;
endmodule
