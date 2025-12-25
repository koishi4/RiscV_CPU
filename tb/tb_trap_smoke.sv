`timescale 1ns/1ps
`include "defines.vh"

module tb_trap_smoke;
    reg clk;
    reg rst_n;
    reg ext_irq;

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
        .ext_irq(ext_irq)
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
        ext_irq = 1'b0;
        for (i = 0; i < 512; i = i + 1) begin
            mem[i] = 32'h00000013; // NOP
        end

        // hart0 program @ 0x0000_0000
        mem[0]  = 32'h10000093; // addi x1, x0, 0x100
        mem[1]  = 32'h00000013; // nop
        mem[2]  = 32'h30509073; // csrrw x0, mtvec, x1
        mem[3]  = 32'h00800113; // addi x2, x0, 8
        mem[4]  = 32'h00000013; // nop
        mem[5]  = 32'h30012073; // csrrs x0, mstatus, x2
        mem[6]  = 32'h80000113; // addi x2, x0, 0x800
        mem[7]  = 32'h00000013; // nop
        mem[8]  = 32'h30412073; // csrrs x0, mie, x2
        mem[9]  = 32'hf1401373; // csrrw x6, mhartid, x0
        mem[10] = 32'h00000013; // nop
        mem[11] = 32'h00118193; // addi x3, x3, 1
        mem[12] = 32'hfe000ee3; // beq x0, x0, -4

        // ISR @ 0x0000_0100
        mem[64] = 32'h00100293; // addi x5, x0, 1
        mem[65] = 32'h30200073; // mret
        mem[66] = 32'h00000063; // beq x0, x0, 0

        // hart1 program @ 0x0000_0200
        mem[128] = 32'h00000063; // beq x0, x0, 0

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = 32'h0000_0200;

        repeat (80) @(posedge clk);
        ext_irq = 1'b1;
        $display("ext_irq asserted");
        repeat (10) @(posedge clk);
        ext_irq = 1'b0;
        $display("ext_irq deasserted");

        repeat (200) @(posedge clk);

        $display("hart0 x5=%0d (ISR flag)", dut.u_regfile.regs[0][5]);
        $display("hart0 x6=%0d (mhartid)", dut.u_regfile.regs[0][6]);
        $display("hart0 mepc=0x%08x mcause=0x%08x", dut.u_csr.mepc[0], dut.u_csr.mcause[0]);

        if (dut.u_regfile.regs[0][5] !== 32'd1) $fatal(1, "ISR flag not set: x5=%0d", dut.u_regfile.regs[0][5]);
        if (dut.u_regfile.regs[0][6] !== 32'd0) $fatal(1, "mhartid mismatch: x6=%0d", dut.u_regfile.regs[0][6]);
        if (dut.u_csr.mcause[0] !== 32'h8000000B) $fatal(1, "mcause mismatch: 0x%08x", dut.u_csr.mcause[0]);
        if (dut.u_csr.mepc[0] == 32'h00000000 || dut.u_csr.mepc[0] >= 32'h00000100) begin
            $fatal(1, "mepc out of range: 0x%08x", dut.u_csr.mepc[0]);
        end

        $display("trap smoke passed");
        $finish;
    end
endmodule
