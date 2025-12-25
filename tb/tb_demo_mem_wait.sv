`timescale 1ns/1ps
`include "defines.vh"

module tb_demo_mem_wait;
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
    reg [1:0] stall_cnt;

    wire is_data = (cpu_mem_addr >= 32'h0000_0200);

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

    assign cpu_mem_rdata = mem[cpu_mem_addr[10:2]];
    assign cpu_mem_ready = (!is_data || (stall_cnt == 0)) ? 1'b1 : 1'b0;

    always @(posedge clk) begin
        if (!rst_n) begin
            stall_cnt <= 2'd0;
        end else if (cpu_mem_req && is_data && (stall_cnt == 0)) begin
            stall_cnt <= 2'd2;
            $display("data stall injected at addr 0x%08x", cpu_mem_addr);
        end else if (stall_cnt != 0) begin
            stall_cnt <= stall_cnt - 1'b1;
        end
    end

    always @(posedge clk) begin
        if (cpu_mem_req && cpu_mem_we && cpu_mem_ready) begin
            mem[cpu_mem_addr[10:2]] <= cpu_mem_wdata;
            $display("store addr=0x%08x data=0x%08x", cpu_mem_addr, cpu_mem_wdata);
        end
    end

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
        mem[0]  = 32'h20000093; // addi x1, x0, 0x200
        mem[1]  = 32'h00000013; // nop
        mem[2]  = 32'h00000013; // nop
        mem[3]  = 32'h00700113; // addi x2, x0, 7
        mem[4]  = 32'h00000013; // nop
        mem[5]  = 32'h00000013; // nop
        mem[6]  = 32'h0020A023; // sw x2, 0(x1)
        mem[7]  = 32'h00000013; // nop
        mem[8]  = 32'h00000013; // nop
        mem[9]  = 32'h0000A183; // lw x3, 0(x1)
        mem[10] = 32'h00000013; // nop
        mem[11] = 32'h00000013; // nop
        mem[12] = 32'h00000063; // beq x0, x0, 0

        // hart1 program @ 0x0000_0100
        mem[64] = 32'h00150513; // addi x10, x10, 1
        mem[65] = 32'hfe000ee3; // beq x0, x0, -4

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = 32'h0000_0100;

        repeat (300) @(posedge clk);

        $display("hart0 x1=%0d x2=%0d x3=%0d", dut.u_regfile.regs[0][1], dut.u_regfile.regs[0][2], dut.u_regfile.regs[0][3]);
        $display("hart1 x10=%0d", dut.u_regfile.regs[1][10]);
        $display("mem[0x200]=0x%08x", mem[32'h200 >> 2]);

        if (dut.u_regfile.regs[0][1] !== 32'h00000200) $fatal(1, "hart0 x1 mismatch: 0x%08x", dut.u_regfile.regs[0][1]);
        if (dut.u_regfile.regs[0][2] !== 32'd7) $fatal(1, "hart0 x2 mismatch: %0d", dut.u_regfile.regs[0][2]);
        if (dut.u_regfile.regs[0][3] !== 32'd7) $fatal(1, "hart0 x3 mismatch: %0d", dut.u_regfile.regs[0][3]);
        if (mem[32'h200 >> 2] !== 32'd7) $fatal(1, "mem[0x200] mismatch: %0d", mem[32'h200 >> 2]);
        if (dut.u_regfile.regs[1][10] < 32'd8) $fatal(1, "hart1 x10 too small: %0d", dut.u_regfile.regs[1][10]);

        $display("memory wait latency hiding demo passed");
        $finish;
    end
endmodule
