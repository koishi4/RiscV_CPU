`include "defines.vh"

module barrel_sched(
    input  clk,
    input  rst_n,
    input  [`HART_NUM-1:0] blocked,
    output [`HART_ID_W-1:0] cur_hart,
    output cur_valid
);
    // TODO: round-robin scheduler that skips blocked harts.

    assign cur_hart  = {`HART_ID_W{1'b0}};
    assign cur_valid = 1'b0;
endmodule
