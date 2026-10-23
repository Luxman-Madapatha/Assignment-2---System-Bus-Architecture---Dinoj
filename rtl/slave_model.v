//============================================================================
// slave_model.v : memory slave (byte wide, 2^ADDR_W bytes)
//   SLAVE_ID : select code this slave answers to (1, 2 or 3)
//   ADDR_W   : 12 -> 4 KB, 11 -> 2 KB   (local address = A[ADDR_W-1:0])
//
//   beat 0 (HEADER)  : latch RW and the upper local address bits
//   beat 1 (ADDR_LO) : form address; read -> RAM read now
//   beat 2 (WDATA)   : write -> RAM write
//   Read data is valid on s_rdata one clock after ADDR_LO and is held
//   until the next read (fixed-latency slave).
//   Memory is a synchronous RAM so Quartus maps it to M9K block RAM.
//   Control logic: asynchronous active-low reset, rising-edge clock.
//============================================================================
module slave_model #(
    parameter [1:0] SLAVE_ID = 2'd1,
    parameter       ADDR_W   = 12
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] s_sel,
    input  wire       s_valid,
    input  wire [7:0] s_wdata,
    output wire [7:0] s_rdata
);
    localparam DEPTH = 1 << ADDR_W;
    localparam HI_W  = ADDR_W - 8;          // address bits in the header

    reg [7:0]        mem [0:DEPTH-1];
    reg [7:0]        rd_q;
    reg [1:0]        beat;
    reg              rw_q;
    reg [HI_W-1:0]   addr_hi_q;
    reg [ADDR_W-1:0] addr_q;

    wire              selected = (s_sel == SLAVE_ID);
    wire              beat_en  = selected & s_valid;
    wire [ADDR_W-1:0] cur_addr = {addr_hi_q, s_wdata};
    wire              mem_we   = beat_en & (beat == 2'd2) &  rw_q;
    wire              mem_re   = beat_en & (beat == 2'd1) & ~rw_q;

    // ---- synchronous RAM (no reset on the array, as for block RAM) ----
    always @(posedge clk) begin
        if (mem_we) mem[addr_q] <= s_wdata;
        if (mem_re) rd_q        <= mem[cur_addr];
    end
    assign s_rdata = rd_q;

    // ---- beat sequencer ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat <= 2'd0; rw_q <= 1'b0; addr_hi_q <= {HI_W{1'b0}};
            addr_q <= {ADDR_W{1'b0}};
        end else if (!selected) begin
            beat <= 2'd0;
        end else if (s_valid) begin
            case (beat)
                2'd0: begin
                          rw_q      <= s_wdata[7];
                          addr_hi_q <= s_wdata[HI_W-1:0];
                          beat      <= 2'd1;
                      end
                2'd1: begin
                          addr_q <= cur_addr;
                          beat   <= rw_q ? 2'd2 : 2'd0;
                      end
                default: beat <= 2'd0;
            endcase
        end
    end

    // simulation only: start with a cleared memory
    // synthesis translate_off
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 8'h00;
        rd_q = 8'h00;
    end
    // synthesis translate_on
endmodule
