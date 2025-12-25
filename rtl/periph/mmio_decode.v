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
    // Decode CPU accesses to RAM vs DMA MMIO range.

    wire is_dma = ((cpu_mem_addr & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);

    assign ram_mem_req   = cpu_mem_req && !is_dma;
    assign ram_mem_we    = cpu_mem_we && !is_dma;
    assign ram_mem_addr  = cpu_mem_addr;
    assign ram_mem_wdata = cpu_mem_wdata;

    assign dma_mmio_req   = cpu_mem_req && is_dma;
    assign dma_mmio_we    = cpu_mem_we && is_dma;
    assign dma_mmio_addr  = cpu_mem_addr;
    assign dma_mmio_wdata = cpu_mem_wdata;

    assign cpu_mem_rdata = cpu_mem_req ? (is_dma ? dma_mmio_rdata : ram_mem_rdata)
                                       : {`XLEN{1'b0}};
    assign cpu_mem_ready = cpu_mem_req && (is_dma ? dma_mmio_ready : ram_mem_ready);
endmodule
