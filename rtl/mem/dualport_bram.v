`include "defines.vh"
`include "interface.vh"

module dualport_bram(
    input  clk,
    input  rst_n,
    `MEM_REQ_PORTS(input, a_mem),
    `MEM_RSP_PORTS(output, a_mem),
    `MEM_REQ_PORTS(input, b_mem),
    `MEM_RSP_PORTS(output, b_mem)
);
    // TODO: implement true dual-port memory.

    assign a_mem_rdata = {`XLEN{1'b0}};
    assign a_mem_ready = 1'b1;

    assign b_mem_rdata = {`XLEN{1'b0}};
    assign b_mem_ready = 1'b1;
endmodule
