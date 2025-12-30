`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module tb_led_uart_mmio_seg_btn;
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

    localparam [`ADDR_W-1:0] LED_ADDR  = `IO_BASE_ADDR + `IO_LED_OFFSET;
    localparam [`ADDR_W-1:0] SEG_ADDR  = `IO_BASE_ADDR + `IO_SEG_OFFSET;
    localparam [`ADDR_W-1:0] BTN_ADDR  = `IO_BASE_ADDR + `IO_BTN_OFFSET;

    led_uart_mmio #(
        .BTN_ACTIVE_LOW(1'b0),
        .SEG_ACTIVE_LOW(1'b0),
        .SEG_SCAN_EN(1'b0)
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

    function automatic [6:0] hex_to_seg(input [3:0] nibble);
        begin
            case (nibble)
                4'h0: hex_to_seg = 7'b1111110;
                4'h1: hex_to_seg = 7'b0110000;
                4'h2: hex_to_seg = 7'b1101101;
                4'h3: hex_to_seg = 7'b1111001;
                4'h4: hex_to_seg = 7'b0110011;
                4'h5: hex_to_seg = 7'b1011011;
                4'h6: hex_to_seg = 7'b1011111;
                4'h7: hex_to_seg = 7'b1110000;
                4'h8: hex_to_seg = 7'b1111111;
                4'h9: hex_to_seg = 7'b1111011;
                4'hA: hex_to_seg = 7'b1110111;
                4'hB: hex_to_seg = 7'b0011111;
                4'hC: hex_to_seg = 7'b1001110;
                4'hD: hex_to_seg = 7'b0111101;
                4'hE: hex_to_seg = 7'b1001111;
                4'hF: hex_to_seg = 7'b1000111;
                default: hex_to_seg = 7'b0000001;
            endcase
        end
    endfunction

    task automatic mmio_write(input [`ADDR_W-1:0] addr, input [`XLEN-1:0] data);
        begin
            @(posedge clk);
            mmio_req <= 1'b1;
            mmio_we <= 1'b1;
            mmio_addr <= addr;
            mmio_wdata <= data;
            @(posedge clk);
            mmio_req <= 1'b0;
            mmio_we <= 1'b0;
            mmio_addr <= {`ADDR_W{1'b0}};
            mmio_wdata <= {`XLEN{1'b0}};
        end
    endtask

    task automatic mmio_read(input [`ADDR_W-1:0] addr, output [`XLEN-1:0] data);
        begin
            @(posedge clk);
            mmio_req <= 1'b1;
            mmio_we <= 1'b0;
            mmio_addr <= addr;
            @(posedge clk);
            data = mmio_rdata;
            @(posedge clk);
            mmio_req <= 1'b0;
            mmio_addr <= {`ADDR_W{1'b0}};
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer i;
    reg [`XLEN-1:0] rdata;
    reg [7:0] val;
    initial begin
        rst_n = 1'b0;
        mmio_req = 1'b0;
        mmio_we = 1'b0;
        mmio_addr = {`ADDR_W{1'b0}};
        mmio_wdata = {`XLEN{1'b0}};
        btn_in = 5'b00000;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // Directed LED write/readback.
        mmio_write(LED_ADDR, 32'h0000_00A5);
        if (led_out !== 16'h00A5) begin
            $fatal(1, "LED write mismatch: got 0x%04x", led_out);
        end

        // Directed SEG write.
        val = 8'h3C;
        mmio_write(SEG_ADDR, {24'b0, val});
        if (seg0[6:0] !== hex_to_seg(val[3:0])) begin
            $fatal(1, "SEG0 decode mismatch");
        end
        if (seg1[6:0] !== hex_to_seg(val[7:4])) begin
            $fatal(1, "SEG1 decode mismatch");
        end

        // Button readback.
        btn_in = 5'b10101;
        mmio_read(BTN_ADDR, rdata);
        if (rdata[4:0] !== btn_in) begin
            $fatal(1, "BTN readback mismatch: got 0x%02x", rdata[4:0]);
        end

        // Randomized SEG tests.
        for (i = 0; i < 20; i = i + 1) begin
            val = $urandom;
            mmio_write(SEG_ADDR, {24'b0, val});
            if (seg0[6:0] !== hex_to_seg(val[3:0])) begin
                $fatal(1, "SEG0 decode mismatch on iter %0d", i);
            end
            if (seg1[6:0] !== hex_to_seg(val[7:4])) begin
                $fatal(1, "SEG1 decode mismatch on iter %0d", i);
            end
        end

        $display("tb_led_uart_mmio_seg_btn passed");
        $finish;
    end
endmodule
