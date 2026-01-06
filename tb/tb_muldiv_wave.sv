`timescale 1ns/1ps
`include "defines.vh"

module tb_muldiv_wave;
    logic clk;
    logic rst_n;

    logic muldiv_start;
    logic [2:0] muldiv_op;
    logic [`XLEN-1:0] muldiv_a;
    logic [`XLEN-1:0] muldiv_b;
    logic [`HART_ID_W-1:0] muldiv_hart_id;
    logic [`REG_ADDR_W-1:0] muldiv_rd;

    logic muldiv_busy;
    logic muldiv_done;
    logic [`XLEN-1:0] muldiv_result;
    logic [`HART_ID_W-1:0] muldiv_done_hart_id;
    logic [`REG_ADDR_W-1:0] muldiv_done_rd;

    muldiv_unit dut (
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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

`ifdef DUMP_VCD
    initial begin
        $dumpfile("muldiv_wave.vcd");
        $dumpvars(0, tb_muldiv_wave);
    end
`endif

    initial begin
        rst_n = 1'b0;
        muldiv_start = 1'b0;
        muldiv_op = `MULDIV_OP_MUL;
        muldiv_a = {`XLEN{1'b0}};
        muldiv_b = {`XLEN{1'b0}};
        muldiv_hart_id = {`HART_ID_W{1'b0}};
        muldiv_rd = {`REG_ADDR_W{1'b0}};

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        muldiv_op = `MULDIV_OP_MUL;
        muldiv_a = 32'h00001234;
        muldiv_b = 32'h00005678;
        muldiv_start = 1'b1;
        @(negedge clk);
        muldiv_start = 1'b0;

        wait (muldiv_done);
        $display("mul result=0x%08x busy=%0d", muldiv_result, muldiv_busy);
        repeat (4) @(posedge clk);
        $finish;
    end
endmodule
