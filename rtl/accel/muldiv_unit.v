`include "defines.vh"
`include "interface.vh"

module muldiv_unit(
    input  clk,
    input  rst_n,
    `MULDIV_REQ_PORTS(input, muldiv),
    `MULDIV_RSP_PORTS(output, muldiv)
);
    // TODO: multi-cycle MUL/DIV implementation.

    assign muldiv_busy        = 1'b0;
    assign muldiv_done        = 1'b0;
    assign muldiv_result      = {`XLEN{1'b0}};
    assign muldiv_done_hart_id = {`HART_ID_W{1'b0}};
    assign muldiv_done_rd     = {`REG_ADDR_W{1'b0}};
endmodule
