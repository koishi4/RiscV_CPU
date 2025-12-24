`timescale 1ns/1ps
`include "defines.vh"

module tb_top;
    reg clk;
    reg rst_n;

    soc_top dut (
        .clk(clk),
        .rst_n(rst_n)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // TODO: load program memory, run tests, and check results.
        repeat (100) @(posedge clk);
        $finish;
    end
endmodule
