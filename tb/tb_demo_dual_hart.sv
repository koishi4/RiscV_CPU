`timescale 1ns/1ps
`include "defines.vh"

module tb_demo_dual_hart;
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

    localparam [`XLEN-1:0] NOP = 32'h00000013;
    localparam [`ADDR_W-1:0] SUM_ADDR = 32'h0000_0100;
    localparam [`ADDR_W-1:0] FIB_ADDR = 32'h0000_0200;
    localparam [`ADDR_W-1:0] HART1_BASE = 32'h0000_0300;
    localparam integer SUM_IDX = SUM_ADDR >> 2;
    localparam integer FIB_IDX = FIB_ADDR >> 2;
    localparam integer HART1_IDX = HART1_BASE >> 2;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer i;
    initial begin
        rst_n = 1'b0;
        for (i = 0; i < 512; i = i + 1) begin
            mem[i] = NOP;
        end

        // hart0 program @ 0x0000_0000
        mem[0]  = 32'h00000093; // addi x1, x0, 0
        mem[1]  = 32'h00100113; // addi x2, x0, 1
        mem[2]  = 32'h00b00193; // addi x3, x0, 11
        mem[3]  = 32'h10000293; // addi x5, x0, 0x100
        mem[4]  = 32'h002080b3; // add  x1, x1, x2
        mem[5]  = NOP;
        mem[6]  = NOP;
        mem[7]  = 32'h00110113; // addi x2, x2, 1
        mem[8]  = NOP;
        mem[9]  = NOP;
        mem[10] = 32'hfe3114e3; // bne  x2, x3, loop
        mem[11] = 32'h0012a023; // sw   x1, 0(x5)
        mem[12] = 32'h00000063; // beq  x0, x0, 0

        // hart1 program @ 0x0000_0300
        mem[HART1_IDX + 0]  = 32'h00000093; // addi x1, x0, 0
        mem[HART1_IDX + 1]  = 32'h00100113; // addi x2, x0, 1
        mem[HART1_IDX + 2]  = 32'h00800193; // addi x3, x0, 8
        mem[HART1_IDX + 3]  = 32'h20000293; // addi x5, x0, 0x200
        mem[HART1_IDX + 4]  = 32'h00208233; // add  x4, x1, x2
        mem[HART1_IDX + 5]  = NOP;
        mem[HART1_IDX + 6]  = NOP;
        mem[HART1_IDX + 7]  = 32'h00010093; // addi x1, x2, 0
        mem[HART1_IDX + 8]  = NOP;
        mem[HART1_IDX + 9]  = NOP;
        mem[HART1_IDX + 10] = 32'h00020113; // addi x2, x4, 0
        mem[HART1_IDX + 11] = NOP;
        mem[HART1_IDX + 12] = NOP;
        mem[HART1_IDX + 13] = 32'hfff18193; // addi x3, x3, -1
        mem[HART1_IDX + 14] = NOP;
        mem[HART1_IDX + 15] = NOP;
        mem[HART1_IDX + 16] = 32'hfc0198e3; // bne  x3, x0, loop
        mem[HART1_IDX + 17] = 32'h0022a023; // sw   x2, 0(x5)
        mem[HART1_IDX + 18] = 32'h00000063; // beq  x0, x0, 0

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = HART1_BASE;

        repeat (1200) @(posedge clk);

        $display("sum[0x100]=%0d fib[0x200]=%0d", mem[SUM_IDX], mem[FIB_IDX]);

        if (mem[SUM_IDX] !== 32'd55) $fatal(1, "hart0 sum mismatch: %0d", mem[SUM_IDX]);
        if (mem[FIB_IDX] !== 32'd34) $fatal(1, "hart1 fib mismatch: %0d", mem[FIB_IDX]);

        $display("dual-hart correctness demo passed");
        $finish;
    end
endmodule
