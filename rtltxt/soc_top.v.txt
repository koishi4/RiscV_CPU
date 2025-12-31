`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module soc_top(
    input clk,
    input rst_n,
    output [`IO_LED_WIDTH-1:0] led,
    output [7:0] seg0,
    output [7:0] seg1,
    output [7:0] seg_an,
    input  [4:0] btn,
    output uart_tx
);
    // Interconnect wires
    `DECL_MEM_IF(cpu_mem)
    `DECL_MEM_IF(ram_mem)
    `DECL_MEM_IF(dma_mem)
    `DECL_MMIO_IF(dma_mmio)
    `DECL_MMIO_IF(io_mmio)
    `DECL_MULDIV_IF(muldiv)

    wire dma_irq;
    wire ext_irq;

    cpu_top u_cpu (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_mem_req(cpu_mem_req),
        .cpu_mem_we(cpu_mem_we),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mem_rdata),
        .cpu_mem_ready(cpu_mem_ready),
        .muldiv_start(muldiv_start),
        .muldiv_op(muldiv_op),
        .muldiv_a(muldiv_a),
        .muldiv_b(muldiv_b),
        .muldiv_hart_id(muldiv_hart_id),
        .muldiv_rd(muldiv_rd),
        .muldiv_busy(muldiv_busy),
        .muldiv_done(muldiv_done),
        .muldiv_result(muldiv_result),
        .muldiv_done_hart_id(muldiv_done_hart_id),
        .muldiv_done_rd(muldiv_done_rd),
        .ext_irq(ext_irq)
    );

    mmio_fabric u_mmio (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_mem_req(cpu_mem_req),
        .cpu_mem_we(cpu_mem_we),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mem_rdata),
        .cpu_mem_ready(cpu_mem_ready),
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
        .dma_mmio_ready(dma_mmio_ready),
        .io_mmio_req(io_mmio_req),
        .io_mmio_we(io_mmio_we),
        .io_mmio_addr(io_mmio_addr),
        .io_mmio_wdata(io_mmio_wdata),
        .io_mmio_rdata(io_mmio_rdata),
        .io_mmio_ready(io_mmio_ready)
    );

    dma_engine u_dma (
        .clk(clk),
        .rst_n(rst_n),
        .mmio_req(dma_mmio_req),
        .mmio_we(dma_mmio_we),
        .mmio_addr(dma_mmio_addr),
        .mmio_wdata(dma_mmio_wdata),
        .mmio_rdata(dma_mmio_rdata),
        .mmio_ready(dma_mmio_ready),
        .dma_mem_req(dma_mem_req),
        .dma_mem_we(dma_mem_we),
        .dma_mem_addr(dma_mem_addr),
        .dma_mem_wdata(dma_mem_wdata),
        .dma_mem_rdata(dma_mem_rdata),
        .dma_mem_ready(dma_mem_ready),
        .dma_irq(dma_irq)
    );

    irq_router u_irq (
        .clk(clk),
        .rst_n(rst_n),
        .dma_irq(dma_irq),
        .ext_irq(ext_irq)
    );

    led_uart_mmio #(
        .BTN_ACTIVE_LOW(1'b0),
        .SEG_ACTIVE_LOW(1'b0),
        .SEG_AN_ACTIVE_LOW(1'b0)
    ) u_io (
        .clk(clk),
        .rst_n(rst_n),
        .mmio_req(io_mmio_req),
        .mmio_we(io_mmio_we),
        .mmio_addr(io_mmio_addr),
        .mmio_wdata(io_mmio_wdata),
        .mmio_rdata(io_mmio_rdata),
        .mmio_ready(io_mmio_ready),
        .led_out(led),
        .seg0(seg0),
        .seg1(seg1),
        .seg_an(seg_an),
        .btn_in(btn),
        .uart_tx(uart_tx)
    );

    dualport_bram u_mem (
        .clk(clk),
        .rst_n(rst_n),
        .a_mem_req(ram_mem_req),
        .a_mem_we(ram_mem_we),
        .a_mem_addr(ram_mem_addr),
        .a_mem_wdata(ram_mem_wdata),
        .a_mem_rdata(ram_mem_rdata),
        .a_mem_ready(ram_mem_ready),
        .b_mem_req(dma_mem_req),
        .b_mem_we(dma_mem_we),
        .b_mem_addr(dma_mem_addr),
        .b_mem_wdata(dma_mem_wdata),
        .b_mem_rdata(dma_mem_rdata),
        .b_mem_ready(dma_mem_ready)
    );

    muldiv_unit u_muldiv (
        .clk(clk),
        .rst_n(rst_n),
        .muldiv_start(muldiv_start),
        .muldiv_op(muldiv_op),
        .muldiv_a(muldiv_a),
        .muldiv_b(muldiv_b),
        .muldiv_hart_id(muldiv_hart_id),
        .muldiv_rd(muldiv_rd),
        .muldiv_busy(muldiv_busy),
        .muldiv_done(muldiv_done),
        .muldiv_result(muldiv_result),
        .muldiv_done_hart_id(muldiv_done_hart_id),
        .muldiv_done_rd(muldiv_done_rd)
    );
endmodule
