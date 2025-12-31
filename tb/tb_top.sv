`timescale 1ns/1ps
`include "defines.vh"

module tb_top;
    reg clk;
    reg rst_n;
    wire [`IO_LED_WIDTH-1:0] led;
    wire [7:0] seg0;
    wire [7:0] seg1;
    wire [7:0] seg_an;
    reg [4:0] btn;
    reg [7:0] sw;
    wire uart_tx;

    soc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .led(led),
        .seg0(seg0),
        .seg1(seg1),
        .seg_an(seg_an),
        .btn(btn),
        .sw(sw),
        .uart_tx(uart_tx)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        btn = 5'b00000;
        sw = 8'h00;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // TODO: load program memory, run tests, and check results.
        repeat (100) @(posedge clk);
        $finish;
    end
endmodule
