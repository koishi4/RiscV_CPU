`timescale 1ns/1ps
`include "defines.vh"

module tb_forwarding;
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

    assign muldiv_busy = 1'b0;
    assign muldiv_done = 1'b0;
    assign muldiv_result = {`XLEN{1'b0}};
    assign muldiv_done_hart_id = {`HART_ID_W{1'b0}};
    assign muldiv_done_rd = {`REG_ADDR_W{1'b0}};

    always @(posedge clk) begin
        if (cpu_mem_req && cpu_mem_we && cpu_mem_ready) begin
            mem[cpu_mem_addr[10:2]] <= cpu_mem_wdata;
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

        // hart0 program @ 0x0000_0000 (no NOPs between dependencies)
        mem[0] = 32'h00500093; // addi x1, x0, 5
        mem[1] = 32'h00308113; // addi x2, x1, 3
        mem[2] = 32'h001101b3; // add  x3, x2, x1
        mem[3] = 32'h00218233; // add  x4, x3, x2
        mem[4] = 32'h20000293; // addi x5, x0, 0x200
        mem[5] = 32'h0042a023; // sw   x4, 0(x5)
        mem[6] = 32'h0002a303; // lw   x6, 0(x5)
        mem[7] = 32'h001303b3; // add  x7, x6, x1
        mem[8] = 32'h00000063; // beq  x0, x0, 0

        // hart1 program @ 0x0000_0100
        mem[64] = 32'h00000063; // beq x0, x0, 0

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = 32'h0000_0100;

        repeat (300) @(posedge clk);

        $display("x1=%0d x2=%0d x3=%0d x4=%0d x5=0x%08x x6=%0d x7=%0d",
                 dut.u_regfile.regs[0][1], dut.u_regfile.regs[0][2],
                 dut.u_regfile.regs[0][3], dut.u_regfile.regs[0][4],
                 dut.u_regfile.regs[0][5], dut.u_regfile.regs[0][6],
                 dut.u_regfile.regs[0][7]);
        $display("mem[0x200]=%0d", mem[32'h200 >> 2]);

        if (dut.u_regfile.regs[0][1] !== 32'd5) $fatal(1, "x1 mismatch: %0d", dut.u_regfile.regs[0][1]);
        if (dut.u_regfile.regs[0][2] !== 32'd8) $fatal(1, "x2 mismatch: %0d", dut.u_regfile.regs[0][2]);
        if (dut.u_regfile.regs[0][3] !== 32'd13) $fatal(1, "x3 mismatch: %0d", dut.u_regfile.regs[0][3]);
        if (dut.u_regfile.regs[0][4] !== 32'd21) $fatal(1, "x4 mismatch: %0d", dut.u_regfile.regs[0][4]);
        if (dut.u_regfile.regs[0][5] !== 32'h00000200) $fatal(1, "x5 mismatch: 0x%08x", dut.u_regfile.regs[0][5]);
        if (dut.u_regfile.regs[0][6] !== 32'd21) $fatal(1, "x6 mismatch: %0d", dut.u_regfile.regs[0][6]);
        if (dut.u_regfile.regs[0][7] !== 32'd26) $fatal(1, "x7 mismatch: %0d", dut.u_regfile.regs[0][7]);
        if (mem[32'h200 >> 2] !== 32'd21) $fatal(1, "mem[0x200] mismatch: %0d", mem[32'h200 >> 2]);

        $display("forwarding demo passed");
        $finish;
    end
endmodule
