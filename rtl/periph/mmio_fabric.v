`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module mmio_fabric(
    input  clk,
    input  rst_n,
    `MEM_REQ_PORTS(input, cpu_mem),
    `MEM_RSP_PORTS(output, cpu_mem),
    `MEM_REQ_PORTS(output, ram_mem),
    `MEM_RSP_PORTS(input, ram_mem),
    `MMIO_REQ_PORTS(output, dma_mmio),
    `MMIO_RSP_PORTS(input, dma_mmio),
    `MMIO_REQ_PORTS(output, io_mmio),
    `MMIO_RSP_PORTS(input, io_mmio)
);
    // Decode CPU accesses to RAM/DMA/IO ranges without modifying mmio_decode.
    wire is_io = ((cpu_mem_addr & `IO_ADDR_MASK) == `IO_ADDR_MATCH);

    wire cpu_req_passthru = cpu_mem_req && !is_io;
    wire cpu_we_passthru  = cpu_mem_we && !is_io;
    wire [`XLEN-1:0] cpu_mmio_rdata;
    wire cpu_mmio_ready;

    mmio_decode u_mmio (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_mem_req(cpu_req_passthru),
        .cpu_mem_we(cpu_we_passthru),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mmio_rdata),
        .cpu_mem_ready(cpu_mmio_ready),
        .ram_mem_req(ram_mem_req),
        .ram_mem_we(ram_mem_we),
        .ram_mem_addr(ram_mem_addr),
        .ram_mem_wdata(ram_mem_wdata),
        .ram_mem_rdata(ram_mem_rdata),
        .ram_mem_ready(ram_mem_ready),
        .dma_mmio_req(dma_mmio_req),
        .dma_mmio_we(dma_mmio_we),
        .dma_mmio_addr(dma_mmio_addr),
        .dma_mmio_wdata(dma_mmio_wdata),
        .dma_mmio_rdata(dma_mmio_rdata),
        .dma_mmio_ready(dma_mmio_ready)
    );

    assign io_mmio_req   = cpu_mem_req && is_io;
    assign io_mmio_we    = cpu_mem_we && is_io;
    assign io_mmio_addr  = cpu_mem_addr;
    assign io_mmio_wdata = cpu_mem_wdata;

    assign cpu_mem_rdata = cpu_mem_req ? (is_io ? io_mmio_rdata : cpu_mmio_rdata)
                                       : {`XLEN{1'b0}};
    assign cpu_mem_ready = cpu_mem_req && (is_io ? io_mmio_ready : cpu_mmio_ready);
endmodule
