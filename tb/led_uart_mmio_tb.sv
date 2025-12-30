`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module led_uart_mmio_tb;
    reg clk;
    reg rst_n;

    reg mmio_req;
    reg mmio_we;
    reg [`ADDR_W-1:0] mmio_addr;
    reg [`XLEN-1:0] mmio_wdata;
    wire [`XLEN-1:0] mmio_rdata;
    wire mmio_ready;
    wire [`IO_LED_WIDTH-1:0] led_out;
    wire [7:0] seg0;
    wire [7:0] seg1;
    wire [7:0] seg_an;
    reg [4:0] btn_in;
    wire uart_tx;

    localparam [`ADDR_W-1:0] LED_ADDR = `IO_BASE_ADDR + `IO_LED_OFFSET;
    localparam [`ADDR_W-1:0] UART_TX_ADDR = `IO_BASE_ADDR + `IO_UART_TX_OFFSET;
    localparam [`ADDR_W-1:0] UART_STAT_ADDR = `IO_BASE_ADDR + `IO_UART_STAT_OFFSET;
    localparam integer UART_DIV_TB = 8;

    led_uart_mmio #(
        .UART_DIV(UART_DIV_TB)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .mmio_req(mmio_req),
        .mmio_we(mmio_we),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready),
        .led_out(led_out),
        .seg0(seg0),
        .seg1(seg1),
        .seg_an(seg_an),
        .btn_in(btn_in),
        .uart_tx(uart_tx)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic mmio_write;
        input [`ADDR_W-1:0] addr;
        input [`XLEN-1:0] data;
        begin
            @(negedge clk);
            mmio_req <= 1'b1;
            mmio_we <= 1'b1;
            mmio_addr <= addr;
            mmio_wdata <= data;
            @(negedge clk);
            mmio_req <= 1'b0;
            mmio_we <= 1'b0;
            mmio_addr <= {`ADDR_W{1'b0}};
            mmio_wdata <= {`XLEN{1'b0}};
        end
    endtask

    task automatic mmio_read;
        input [`ADDR_W-1:0] addr;
        output [`XLEN-1:0] data;
        begin
            @(negedge clk);
            mmio_req <= 1'b1;
            mmio_we <= 1'b0;
            mmio_addr <= addr;
            mmio_wdata <= {`XLEN{1'b0}};
            @(negedge clk);
            data = mmio_rdata;
            mmio_req <= 1'b0;
            mmio_addr <= {`ADDR_W{1'b0}};
        end
    endtask

    integer i;
    reg [`XLEN-1:0] rd_data;
    reg [`IO_LED_WIDTH-1:0] led_exp;
    initial begin
        rst_n = 1'b0;
        mmio_req = 1'b0;
        mmio_we = 1'b0;
        mmio_addr = {`ADDR_W{1'b0}};
        mmio_wdata = {`XLEN{1'b0}};
        btn_in = 5'b00000;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Directed LED write/read.
        mmio_write(LED_ADDR, 32'h0000_A5A5);
        mmio_read(LED_ADDR, rd_data);
        if (rd_data[`IO_LED_WIDTH-1:0] !== 16'hA5A5) $fatal(1, "LED readback mismatch: %h", rd_data);
        if (led_out !== 16'hA5A5) $fatal(1, "LED output mismatch: %h", led_out);

        // Random LED patterns.
        for (i = 0; i < 20; i = i + 1) begin
            led_exp = $urandom;
            mmio_write(LED_ADDR, {{(`XLEN-`IO_LED_WIDTH){1'b0}}, led_exp});
            mmio_read(LED_ADDR, rd_data);
            if (rd_data[`IO_LED_WIDTH-1:0] !== led_exp) $fatal(1, "LED random mismatch: %h != %h", rd_data, led_exp);
            if (led_out !== led_exp) $fatal(1, "LED random output mismatch: %h != %h", led_out, led_exp);
        end

        // UART TX: busy should assert and then clear.
        mmio_write(UART_TX_ADDR, 32'h0000_0055);
        mmio_read(UART_STAT_ADDR, rd_data);
        if (rd_data[`IO_UART_STAT_BUSY_BIT] !== 1'b1) $fatal(1, "UART busy not set");

        repeat ((10 * UART_DIV_TB) + 4) @(posedge clk);
        mmio_read(UART_STAT_ADDR, rd_data);
        if (rd_data[`IO_UART_STAT_BUSY_BIT] !== 1'b0) $fatal(1, "UART busy not cleared");
        if (uart_tx !== 1'b1) $fatal(1, "UART TX not idle high");

        $display("led_uart_mmio_tb PASS led=0x%04x uart_tx=%0b", led_out, uart_tx);
        $finish;
    end
endmodule
