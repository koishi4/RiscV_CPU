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
    // MMIO Fabric：把 CPU 的访问拆分为 RAM/DMA/IO 三条通路。
    // - IO 命中：直接发送到 IO 外设（LED/UART/数码管等）。
    // - 非 IO：交由 mmio_decode 再区分 RAM 与 DMA。
    // 注意：这里只做地址判断与转发，不引入队列/缓存。
    wire is_io = ((cpu_mem_addr & `IO_ADDR_MASK) == `IO_ADDR_MATCH);

    // 非 IO 访问的请求/写使能透传给 mmio_decode。
    wire cpu_req_passthru = cpu_mem_req && !is_io;
    wire cpu_we_passthru  = cpu_mem_we && !is_io;
    // 来自 mmio_decode 的读数据与 ready（RAM 或 DMA）。
    wire [`XLEN-1:0] cpu_mmio_rdata;
    wire cpu_mmio_ready;

    // RAM/DMA 分流：非 IO 区间访问交给 mmio_decode 处理。
    // 端口含义：
    // - cpu_mem_*：来自 CPU 的访存请求（仅非 IO）。
    // - ram_mem_*：送往 RAM 的普通内存访问。
    // - dma_mmio_*：送往 DMA 寄存器的 MMIO 访问。
    // - cpu_mem_rdata/ready：返回给 CPU 的读数据与握手。
    mmio_decode u_mmio (
        .clk(clk),                        // 时钟
        .rst_n(rst_n),                    // 复位
        .cpu_mem_req(cpu_req_passthru),   // CPU 请求（非 IO）
        .cpu_mem_we(cpu_we_passthru),     // CPU 写使能（非 IO）
        .cpu_mem_addr(cpu_mem_addr),      // CPU 地址
        .cpu_mem_wdata(cpu_mem_wdata),    // CPU 写数据
        .cpu_mem_rdata(cpu_mmio_rdata),   // 返回给 CPU 的读数据
        .cpu_mem_ready(cpu_mmio_ready),   // 返回给 CPU 的 ready
        .ram_mem_req(ram_mem_req),        // RAM 请求
        .ram_mem_we(ram_mem_we),          // RAM 写使能
        .ram_mem_addr(ram_mem_addr),      // RAM 地址
        .ram_mem_wdata(ram_mem_wdata),    // RAM 写数据
        .ram_mem_rdata(ram_mem_rdata),    // RAM 读数据
        .ram_mem_ready(ram_mem_ready),    // RAM ready
        .dma_mmio_req(dma_mmio_req),      // DMA MMIO 请求
        .dma_mmio_we(dma_mmio_we),        // DMA MMIO 写使能
        .dma_mmio_addr(dma_mmio_addr),    // DMA MMIO 地址
        .dma_mmio_wdata(dma_mmio_wdata),  // DMA MMIO 写数据
        .dma_mmio_rdata(dma_mmio_rdata),  // DMA MMIO 读数据
        .dma_mmio_ready(dma_mmio_ready)   // DMA MMIO ready
    );

    // IO 通路：IO 区间直接进外设。
    assign io_mmio_req   = cpu_mem_req && is_io;
    assign io_mmio_we    = cpu_mem_we && is_io;
    assign io_mmio_addr  = cpu_mem_addr;
    assign io_mmio_wdata = cpu_mem_wdata;

    // CPU 返回：根据命中 IO 或 RAM/DMA 返回读数据与 ready。
    assign cpu_mem_rdata = cpu_mem_req ? (is_io ? io_mmio_rdata : cpu_mmio_rdata)
                                       : {`XLEN{1'b0}};
    assign cpu_mem_ready = cpu_mem_req && (is_io ? io_mmio_ready : cpu_mmio_ready);
endmodule
