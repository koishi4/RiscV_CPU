`timescale 1ns/1ps
`include "defines.vh"

module tb_addi_dual;
    reg clk;
    reg rst_n;

    wire cpu_mem_req;
    wire cpu_mem_we;
    wire [`ADDR_W-1:0] cpu_mem_addr;
    wire [`XLEN-1:0] cpu_mem_wdata;
    wire [`XLEN-1:0] cpu_mem_rdata;
    wire cpu_mem_ready;

    wire muldiv_start;
    wire [2:0] muldiv_op;
    wire [`XLEN-1:0] muldiv_a;
    wire [`XLEN-1:0] muldiv_b;
    wire [`HART_ID_W-1:0] muldiv_hart_id;
    wire [`REG_ADDR_W-1:0] muldiv_rd;
    wire muldiv_busy;
    wire muldiv_done;
    wire [`XLEN-1:0] muldiv_result;
    wire [`HART_ID_W-1:0] muldiv_done_hart_id;
    wire [`REG_ADDR_W-1:0] muldiv_done_rd;

    reg [`XLEN-1:0] mem[0:255];

    cpu_top dut (
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
        .ext_irq(1'b0)
    );

    assign cpu_mem_ready = 1'b1;
    assign cpu_mem_rdata = mem[cpu_mem_addr[9:2]];

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer i;
    initial begin
        rst_n = 1'b0;
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 32'h00000013; // NOP
        end

        // hart0 program @ 0x0000_0000
        mem[0] = 32'h00100093; // addi x1, x0, 1
        mem[1] = 32'h00000013; // nop
        mem[2] = 32'h00208113; // addi x2, x1, 2
        mem[3] = 32'h00000013; // nop
        mem[4] = 32'h00310193; // addi x3, x2, 3
        mem[5] = 32'h00000063; // beq x0, x0, 0 (loop)

        // hart1 program @ 0x0000_0100
        mem[64] = 32'h00500093; // addi x1, x0, 5
        mem[65] = 32'h00000013; // nop
        mem[66] = 32'h00608113; // addi x2, x1, 6
        mem[67] = 32'h00000013; // nop
        mem[68] = 32'h00710193; // addi x3, x2, 7
        mem[69] = 32'h00000063; // beq x0, x0, 0 (loop)

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = 32'h0000_0100;

        repeat (200) @(posedge clk);

        $display("hart0 x1=%0d x2=%0d x3=%0d", dut.u_regfile.regs[0][1], dut.u_regfile.regs[0][2], dut.u_regfile.regs[0][3]);
        $display("hart1 x1=%0d x2=%0d x3=%0d", dut.u_regfile.regs[1][1], dut.u_regfile.regs[1][2], dut.u_regfile.regs[1][3]);

        if (dut.u_regfile.regs[0][1] !== 32'd1) $fatal("hart0 x1 mismatch: %0d", dut.u_regfile.regs[0][1]);
        if (dut.u_regfile.regs[0][2] !== 32'd3) $fatal("hart0 x2 mismatch: %0d", dut.u_regfile.regs[0][2]);
        if (dut.u_regfile.regs[0][3] !== 32'd6) $fatal("hart0 x3 mismatch: %0d", dut.u_regfile.regs[0][3]);

        if (dut.u_regfile.regs[1][1] !== 32'd5) $fatal("hart1 x1 mismatch: %0d", dut.u_regfile.regs[1][1]);
        if (dut.u_regfile.regs[1][2] !== 32'd11) $fatal("hart1 x2 mismatch: %0d", dut.u_regfile.regs[1][2]);
        if (dut.u_regfile.regs[1][3] !== 32'd18) $fatal("hart1 x3 mismatch: %0d", dut.u_regfile.regs[1][3]);

        $display("dual-hart addi demo passed");
        $finish;
    end
endmodule
