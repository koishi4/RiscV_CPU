`include "defines.vh"
`include "interface.vh"

module dma_engine(
    input  clk,
    input  rst_n,
    `MMIO_REQ_PORTS(input, mmio),
    `MMIO_RSP_PORTS(output, mmio),
    `MEM_REQ_PORTS(output, dma_mem),
    `MEM_RSP_PORTS(input, dma_mem),
    output dma_irq
);
    // TODO: MMIO registers + DMA copy FSM + IRQ generation.

    assign mmio_rdata  = {`XLEN{1'b0}};
    assign mmio_ready  = 1'b0;

    assign dma_mem_req   = 1'b0;
    assign dma_mem_we    = 1'b0;
    assign dma_mem_addr  = {`ADDR_W{1'b0}};
    assign dma_mem_wdata = {`XLEN{1'b0}};

    assign dma_irq = 1'b0;
endmodule
