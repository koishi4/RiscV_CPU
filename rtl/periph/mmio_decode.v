`include "defines.vh"
`include "interface.vh"

module mmio_decode(
    input  clk,
    input  rst_n,
    `MEM_REQ_PORTS(input, cpu_mem),
    `MEM_RSP_PORTS(output, cpu_mem),
    `MEM_REQ_PORTS(output, ram_mem),
    `MEM_RSP_PORTS(input, ram_mem),
    `MMIO_REQ_PORTS(output, dma_mmio),
    `MMIO_RSP_PORTS(input, dma_mmio)
);
    // TODO: decode CPU accesses to RAM vs DMA MMIO range.

    assign cpu_mem_rdata = {`XLEN{1'b0}};
    assign cpu_mem_ready = 1'b0;

    assign ram_mem_req   = 1'b0;
    assign ram_mem_we    = 1'b0;
    assign ram_mem_addr  = {`ADDR_W{1'b0}};
    assign ram_mem_wdata = {`XLEN{1'b0}};

    assign dma_mmio_req   = 1'b0;
    assign dma_mmio_we    = 1'b0;
    assign dma_mmio_addr  = {`ADDR_W{1'b0}};
    assign dma_mmio_wdata = {`XLEN{1'b0}};
endmodule
