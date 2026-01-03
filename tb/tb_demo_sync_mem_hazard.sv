`timescale 1ns/1ps
`include "defines.vh"

module tb_demo_sync_mem_hazard;
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

    reg req_d1;
    reg [`ADDR_W-1:0] req_d1_addr;
    reg [`XLEN-1:0] req_d1_wdata;
    reg req_d1_we;
    reg [`HART_ID_W-1:0] req_d1_hart;
    reg req_d1_is_data;
    reg [`XLEN-1:0] rdata_reg;
    reg ready_reg;

    localparam [`ADDR_W-1:0] SRC0_ADDR = 32'h0000_0200;
    localparam [`ADDR_W-1:0] SRC1_ADDR = 32'h0000_0204;
    localparam [`ADDR_W-1:0] DST0_ADDR = 32'h0000_0300;
    localparam [`ADDR_W-1:0] DST1_ADDR = 32'h0000_0304;

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

    // 1-cycle latency memory model: ready/data return on the cycle after request.
    always @(posedge clk) begin
        if (!rst_n) begin
            req_d1 <= 1'b0;
            req_d1_addr <= {`ADDR_W{1'b0}};
            req_d1_wdata <= {`XLEN{1'b0}};
            req_d1_we <= 1'b0;
            req_d1_hart <= {`HART_ID_W{1'b0}};
            req_d1_is_data <= 1'b0;
            rdata_reg <= {`XLEN{1'b0}};
            ready_reg <= 1'b0;
        end else begin
            ready_reg <= req_d1;
            if (req_d1) begin
                if (req_d1_we) begin
                    mem[req_d1_addr[10:2]] <= req_d1_wdata;
                end else begin
                    rdata_reg <= mem[req_d1_addr[10:2]];
                end
            end
            req_d1 <= cpu_mem_req;
            if (cpu_mem_req) begin
                req_d1_addr <= cpu_mem_addr;
                req_d1_wdata <= cpu_mem_wdata;
                req_d1_we <= cpu_mem_we;
                req_d1_hart <= dut.exec_hart;
                req_d1_is_data <= dut.mem_is_data;
            end
        end
    end

    assign cpu_mem_rdata = rdata_reg;
    assign cpu_mem_ready = ready_reg && cpu_mem_req;

    always @(*) begin
        if (ready_reg) begin
            if (!cpu_mem_req) begin
                $fatal(1, "mem response dropped: no cpu_mem_req");
            end
            if (cpu_mem_addr !== req_d1_addr) begin
                $fatal(1, "mem addr mismatch: req=0x%08x resp=0x%08x",
                       cpu_mem_addr, req_d1_addr);
            end
            if (dut.exec_hart !== req_d1_hart) begin
                $fatal(1, "hart mismatch: cur=%0d resp=%0d", dut.exec_hart, req_d1_hart);
            end
            if (dut.mem_is_data !== req_d1_is_data) begin
                $fatal(1, "req type mismatch: cur=%0d resp=%0d", dut.mem_is_data, req_d1_is_data);
            end
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
        mem[0] = 32'h20000093; // addi x1, x0, 0x200
        mem[1] = 32'h0000A103; // lw x2, 0(x1)
        mem[2] = 32'h30000193; // addi x3, x0, 0x300
        mem[3] = 32'h0021A023; // sw x2, 0(x3)
        mem[4] = 32'h00000063; // beq x0, x0, 0

        // hart1 program @ 0x0000_0100 (no data memory ops)
        mem[64] = 32'h00150513; // addi x10, x10, 1
        mem[65] = 32'h00258593; // addi x11, x11, 2
        mem[66] = 32'hfe000ee3; // beq x0, x0, -4

        // data init
        mem[SRC0_ADDR[10:2]] = 32'h11111111;
        mem[DST0_ADDR[10:2]] = 32'h00000000;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = 32'h0000_0100;

        repeat (200) @(posedge clk);

        $display("dst0=0x%08x", mem[DST0_ADDR[10:2]]);
        $display("hart0 x1=0x%08x x2=0x%08x x3=0x%08x",
                 dut.u_regfile.regs[0][1], dut.u_regfile.regs[0][2], dut.u_regfile.regs[0][3]);
        $display("hart1 x10=%0d x11=%0d", dut.u_regfile.regs[1][10], dut.u_regfile.regs[1][11]);

        if (mem[DST0_ADDR[10:2]] !== 32'h11111111) begin
            $fatal(1, "dst0 mismatch: 0x%08x", mem[DST0_ADDR[10:2]]);
        end
        if (dut.u_regfile.regs[0][1] !== SRC0_ADDR) begin
            $fatal(1, "hart0 x1 mismatch: 0x%08x", dut.u_regfile.regs[0][1]);
        end
        if (dut.u_regfile.regs[0][2] !== 32'h11111111) begin
            $fatal(1, "hart0 x2 mismatch: 0x%08x", dut.u_regfile.regs[0][2]);
        end
        if (dut.u_regfile.regs[0][3] !== DST0_ADDR) begin
            $fatal(1, "hart0 x3 mismatch: 0x%08x", dut.u_regfile.regs[0][3]);
        end
        if (dut.u_regfile.regs[1][10] < 32'd8) begin
            $fatal(1, "hart1 x10 too small: %0d", dut.u_regfile.regs[1][10]);
        end

        $display("sync mem hazard demo passed");
        $finish;
    end
endmodule
