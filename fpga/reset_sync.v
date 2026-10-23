// reset_sync.v : asynchronous assert, synchronous de-assert
module reset_sync (
    input  wire clk,
    input  wire rst_n_in,
    output wire rst_n_out
);
    reg [1:0] sync;
    always @(posedge clk or negedge rst_n_in)
        if (!rst_n_in) sync <= 2'b00;
        else           sync <= {sync[0], 1'b1};
    assign rst_n_out = sync[1];
endmodule
