`timescale 1ns/1ps
`include "defines.vh"

module tb_demo_muldiv;
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

    reg mem_req_d;
    reg [`ADDR_W-1:0] mem_addr_d;
    reg [`XLEN-1:0] mem_rdata_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_req_d <= 1'b0;
            mem_addr_d <= {`ADDR_W{1'b0}};
            mem_rdata_d <= {`XLEN{1'b0}};
        end else begin
            mem_req_d <= cpu_mem_req;
            mem_addr_d <= cpu_mem_addr;
            mem_rdata_d <= mem[cpu_mem_addr[10:2]];
            if (cpu_mem_req && cpu_mem_we) begin
                mem[cpu_mem_addr[10:2]] <= cpu_mem_wdata;
            end
        end
    end

    assign cpu_mem_ready = mem_req_d;
    assign cpu_mem_rdata = mem_rdata_d;

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

        // hart dispatch: mhartid -> hart1 jumps to 0x100, hart0 falls through.
        mem[0] = 32'hf14020f3; // csrrs x1, mhartid, x0
        mem[1] = 32'h00000013; // nop
        mem[2] = 32'h00000013; // nop
        mem[3] = 32'h00000013; // nop
        mem[4] = 32'h0e009863; // bne x1, x0, +0x0f0 (to 0x100)
        mem[5] = 32'h00000013; // nop
        mem[6] = 32'h00000013; // nop
        mem[7] = 32'h00000013; // nop

        // hart0 program @ 0x0000_0020
        mem[8]  = 32'h00a00093; // addi x1, x0, 10
        mem[9]  = 32'h00000013; // nop
        mem[10] = 32'h00000013; // nop
        mem[11] = 32'h00300113; // addi x2, x0, 3
        mem[12] = 32'h00000013; // nop
        mem[13] = 32'h00000013; // nop
        mem[14] = 32'h022081b3; // mul x3, x1, x2
        mem[15] = 32'h0220c233; // div x4, x1, x2
        mem[16] = 32'h0220e2b3; // rem x5, x1, x2
        mem[17] = 32'h00000063; // beq x0, x0, 0 (loop)

        // hart1 program @ 0x0000_0100
        mem[64] = 32'h00150513; // addi x10, x10, 1
        mem[65] = 32'h00000013; // nop
        mem[66] = 32'h00000013; // nop
        mem[67] = 32'hfe000ae3; // beq x0, x0, -12 (loop)

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (1000) @(posedge clk);

        $display("hart0 x3=%0d x4=%0d x5=%0d", dut.u_regfile.regs[0][3], dut.u_regfile.regs[0][4], dut.u_regfile.regs[0][5]);
        $display("hart1 x10=%0d", dut.u_regfile.regs[1][10]);

        if (dut.u_regfile.regs[0][3] !== 32'd30) $fatal(1, "hart0 x3 mismatch: %0d", dut.u_regfile.regs[0][3]);
        if (dut.u_regfile.regs[0][4] !== 32'd3) $fatal(1, "hart0 x4 mismatch: %0d", dut.u_regfile.regs[0][4]);
        if (dut.u_regfile.regs[0][5] !== 32'd1) $fatal(1, "hart0 x5 mismatch: %0d", dut.u_regfile.regs[0][5]);
        if (dut.u_regfile.regs[1][10] < 32'd8) $fatal(1, "hart1 x10 too small: %0d", dut.u_regfile.regs[1][10]);

        $display("mul/div latency hiding demo passed");
        $finish;
    end
endmodule
