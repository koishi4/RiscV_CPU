`timescale 1ns/1ps
`include "defines.vh"

module tb_ifetch_bram_align;
    reg clk;
    reg rst_n;
    wire [`IO_LED_WIDTH-1:0] led;
    wire uart_tx;

    soc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .led(led),
        .uart_tx(uart_tx)
    );

    localparam integer MEM_DEPTH = (`MEM_SIZE_BYTES / 4);
    localparam [`XLEN-1:0] NOP = 32'h00000013;

    integer i;
    integer fetch_count;
    reg pending_check;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        fetch_count = 0;
        pending_check = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);

        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            dut.u_mem.mem[i] = NOP;
        end

        // Unique, valid op-imm instructions to make fetch order obvious.
        dut.u_mem.mem[0] = 32'h00100013; // addi x0, x0, 1
        dut.u_mem.mem[1] = 32'h00200013; // addi x0, x0, 2
        dut.u_mem.mem[2] = 32'h00300013; // addi x0, x0, 3
        dut.u_mem.mem[3] = 32'h00400013; // addi x0, x0, 4
        dut.u_mem.mem[4] = 32'h00500013; // addi x0, x0, 5
        dut.u_mem.mem[5] = 32'h00600013; // addi x0, x0, 6

        // Park hart1.
        dut.u_mem.mem[128] = 32'h00000063; // beq x0, x0, 0

        rst_n = 1'b1;
        @(negedge clk);
        dut.u_cpu.pc[1] = 32'h0000_0200;

        repeat (400) @(posedge clk);
        $fatal(1, "No IF mismatch observed; check testbench wiring");
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            fetch_count <= 0;
            pending_check <= 1'b0;
        end else begin
            pending_check <= 1'b0;
            if (dut.u_cpu.exec_hart == 0 && dut.u_cpu.if_inst_valid) begin
                fetch_count <= fetch_count + 1;
                pending_check <= 1'b1;
            end
        end
    end

    always @(negedge clk) begin
        integer exp_idx;
        reg [31:0] exp_inst;
        if (pending_check && fetch_count >= 2) begin
            exp_idx = dut.u_cpu.ifid_pc[0] >> 2;
            exp_inst = dut.u_mem.mem[exp_idx];
            if (dut.u_cpu.ifid_inst[0] !== exp_inst) begin
                $display("IF mismatch: pc=0x%08x inst=0x%08x exp=0x%08x",
                         dut.u_cpu.ifid_pc[0],
                         dut.u_cpu.ifid_inst[0],
                         exp_inst);
                $fatal(1, "IFetch pc/inst mismatch (BRAM ready/rdata misalignment)");
            end
        end
    end
endmodule
