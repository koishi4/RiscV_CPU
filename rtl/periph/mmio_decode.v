`timescale 1ns/1ps
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
    // MMIO Decode：在非 IO 通路内，把 CPU 访问拆成 RAM 与 DMA MMIO。
    // - DMA 命中：送到 DMA 寄存器（SRC/DST/LEN/CTRL/STAT/CLR）。
    // - 非 DMA：进入普通 RAM。
    // 本模块只做地址判断与转发，不引入等待或缓存。

    wire is_dma = ((cpu_mem_addr & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);

    // RAM 通路：地址未命中 DMA 时直通 RAM。
    // ram_mem_* 接到 dualport_bram 的 A 端口。
    assign ram_mem_req   = cpu_mem_req && !is_dma;
    assign ram_mem_we    = cpu_mem_we && !is_dma;
    assign ram_mem_addr  = cpu_mem_addr;
    assign ram_mem_wdata = cpu_mem_wdata;

    // DMA 通路：地址命中 DMA MMIO 区间。
    // dma_mmio_* 接到 dma_engine 的 MMIO 端口。
    assign dma_mmio_req   = cpu_mem_req && is_dma;
    assign dma_mmio_we    = cpu_mem_we && is_dma;
    assign dma_mmio_addr  = cpu_mem_addr;
    assign dma_mmio_wdata = cpu_mem_wdata;

    // CPU 返回：按命中选择 DMA 或 RAM 的返回数据/ready。
    assign cpu_mem_rdata = cpu_mem_req ? (is_dma ? dma_mmio_rdata : ram_mem_rdata)
                                       : {`XLEN{1'b0}};
    assign cpu_mem_ready = cpu_mem_req && (is_dma ? dma_mmio_ready : ram_mem_ready);
endmodule
