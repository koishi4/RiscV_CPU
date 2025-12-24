`include "defines.vh"
`include "interface.vh"

module cpu_top(
    input  clk,
    input  rst_n,
    `MEM_REQ_PORTS(output, cpu_mem),
    `MEM_RSP_PORTS(input, cpu_mem),
    `MULDIV_REQ_PORTS(output, muldiv),
    `MULDIV_RSP_PORTS(input, muldiv),
    input  ext_irq
);
    // TODO: implement 2-hart RV32 core, CSR/trap, and muldiv integration.

    assign cpu_mem_req   = 1'b0;
    assign cpu_mem_we    = 1'b0;
    assign cpu_mem_addr  = {`ADDR_W{1'b0}};
    assign cpu_mem_wdata = {`XLEN{1'b0}};

    assign muldiv_start   = 1'b0;
    assign muldiv_op      = 3'd0;
    assign muldiv_a       = {`XLEN{1'b0}};
    assign muldiv_b       = {`XLEN{1'b0}};
    assign muldiv_hart_id = {`HART_ID_W{1'b0}};
    assign muldiv_rd      = {`REG_ADDR_W{1'b0}};
endmodule
