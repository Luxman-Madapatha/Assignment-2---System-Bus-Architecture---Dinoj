//============================================================================
// master_model.v : bus master (one read or write per command)
//   start pulse -> req -> wait gnt -> HEADER, ADDR_LO, [WDATA] beats
//   -> wait bus_ready -> capture rdata, drop req -> wait gnt low -> idle
// Asynchronous active-low reset, rising-edge clock.
//============================================================================
module master_model (
    input  wire        clk,
    input  wire        rst_n,
    // ---- command side (UI or testbench) ----
    input  wire        start,      // 1-cycle pulse, accepted when idle
    input  wire        rw,         // 1 = write, 0 = read
    input  wire [13:0] addr,
    input  wire [7:0]  wdata,
    output reg  [7:0]  rdata,      // data of the last read
    output reg         done,       // 1-cycle pulse when complete
    output wire        busy,
    // ---- bus side ----
    output reg         req,
    input  wire        gnt,
    output reg         valid,
    output reg  [7:0]  dout,
    input  wire [7:0]  bus_rdata,
    input  wire        bus_ready
);
    localparam [2:0] S_IDLE = 3'd0,  // waiting for a command
                     S_REQ  = 3'd1,  // req asserted, waiting for gnt
                     S_HDR  = 3'd2,  // header beat on the bus
                     S_ALO  = 3'd3,  // address-low beat on the bus
                     S_DAT  = 3'd4,  // write-data beat on the bus
                     S_WAIT = 3'd5,  // waiting for bus_ready
                     S_REL  = 3'd6;  // req dropped, waiting gnt release

    reg [2:0]  state;
    reg        rw_q;
    reg [13:0] addr_q;
    reg [7:0]  wdata_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; req <= 1'b0; valid <= 1'b0; dout <= 8'h00;
            rdata <= 8'h00;  done <= 1'b0;
            rw_q  <= 1'b0;   addr_q <= 14'd0; wdata_q <= 8'h00;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                            rw_q <= rw; addr_q <= addr; wdata_q <= wdata;
                            req  <= 1'b1;
                            state <= S_REQ;
                        end
                S_REQ:  if (gnt) begin
                            valid <= 1'b1;
                            dout  <= {rw_q, 1'b0, addr_q[13:8]};
                            state <= S_HDR;
                        end
                S_HDR:  begin
                            dout  <= addr_q[7:0];
                            state <= S_ALO;
                        end
                S_ALO:  if (rw_q) begin
                            dout  <= wdata_q;
                            state <= S_DAT;
                        end else begin
                            valid <= 1'b0; dout <= 8'h00;
                            state <= S_WAIT;
                        end
                S_DAT:  begin
                            valid <= 1'b0; dout <= 8'h00;
                            state <= S_WAIT;
                        end
                S_WAIT: if (gnt && bus_ready) begin
                            if (!rw_q) rdata <= bus_rdata;
                            req   <= 1'b0;
                            done  <= 1'b1;
                            state <= S_REL;
                        end
                S_REL:  if (!gnt) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = (state != S_IDLE);
endmodule
