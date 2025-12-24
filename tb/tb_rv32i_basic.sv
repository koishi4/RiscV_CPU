`timescale 1ns/1ps
`include "defines.vh"

module tb_rv32i_basic;
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

    reg [`XLEN-1:0] mem[0:511];

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
    assign cpu_mem_rdata = mem[cpu_mem_addr[10:2]];

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer i;
    initial begin
        rst_n = 1'b0;
        for (i = 0; i < 512; i = i + 1) begin
            mem[i] = 32'h00000013; // NOP
        end

        // hart0 program @ 0x0000_0000
        mem[0]  = 32'h000120B7; // lui x1, 0x00012
        mem[1]  = 32'h00001117; // auipc x2, 0x1
        mem[2]  = 32'h008001EF; // jal x3, +8 -> 0x0010
        mem[3]  = 32'h00000013; // nop (skipped)
        mem[4]  = 32'h00900213; // addi x4, x0, 9
        mem[5]  = 32'h02800293; // addi x5, x0, 0x28
        mem[6]  = 32'h00000013; // nop
        mem[7]  = 32'h00000013; // nop
        mem[8]  = 32'h00028367; // jalr x6, x5, 0 -> 0x0028
        mem[9]  = 32'h00000013; // nop (skipped)
        mem[10] = 32'h03300393; // addi x7, x0, 0x33
        mem[11] = 32'h00000063; // beq x0, x0, 0

        // hart1 program @ 0x0000_0200
        mem[128] = 32'h00000063; // beq x0, x0, 0

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = 32'h0000_0200;

        repeat (300) @(posedge clk);

        $display("x1=0x%08x x2=0x%08x x3=0x%08x", dut.u_regfile.regs[0][1], dut.u_regfile.regs[0][2], dut.u_regfile.regs[0][3]);
        $display("x4=%0d x5=0x%08x x6=0x%08x x7=0x%08x", dut.u_regfile.regs[0][4], dut.u_regfile.regs[0][5], dut.u_regfile.regs[0][6], dut.u_regfile.regs[0][7]);

        if (dut.u_regfile.regs[0][1] !== 32'h00012000) $fatal("x1 mismatch: 0x%08x", dut.u_regfile.regs[0][1]);
        if (dut.u_regfile.regs[0][2] !== 32'h00001004) $fatal("x2 mismatch: 0x%08x", dut.u_regfile.regs[0][2]);
        if (dut.u_regfile.regs[0][3] !== 32'h0000000C) $fatal("x3 mismatch: 0x%08x", dut.u_regfile.regs[0][3]);
        if (dut.u_regfile.regs[0][4] !== 32'd9) $fatal("x4 mismatch: %0d", dut.u_regfile.regs[0][4]);
        if (dut.u_regfile.regs[0][5] !== 32'h00000028) $fatal("x5 mismatch: 0x%08x", dut.u_regfile.regs[0][5]);
        if (dut.u_regfile.regs[0][6] !== 32'h00000024) $fatal("x6 mismatch: 0x%08x", dut.u_regfile.regs[0][6]);
        if (dut.u_regfile.regs[0][7] !== 32'h00000033) $fatal("x7 mismatch: 0x%08x", dut.u_regfile.regs[0][7]);

        $display("rv32i basic jal/jalr/lui/auipc passed");
        $finish;
    end
endmodule
