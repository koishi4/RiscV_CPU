module irq_router(
    input  clk,
    input  rst_n,
    input  dma_irq,
    output ext_irq
);
    // TODO: route/aggregate IRQ sources. For now, pass through DMA IRQ.

    assign ext_irq = dma_irq;
endmodule
