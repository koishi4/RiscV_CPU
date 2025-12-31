`timescale 1ns/1ps
`include "defines.vh"

module tb_uart_seq_imm;
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

    localparam [`XLEN-1:0] NOP = 32'h00000013;
    localparam integer MEM_DEPTH = (`MEM_SIZE_BYTES / 4);
    localparam integer UART_BYTES = 16;
    localparam integer MAX_CYCLES = 100000;
    localparam [`ADDR_W-1:0] UART_TX_ADDR = `IO_BASE_ADDR + `IO_UART_TX_OFFSET;

    reg [7:0] uart_bytes[0:UART_BYTES-1];
    integer uart_count;

    wire uart_write = dut.u_io.mmio_req &&
                      dut.u_io.mmio_we &&
                      (dut.u_io.mmio_addr == UART_TX_ADDR);
    wire uart_accept = uart_write && dut.u_io.mmio_ready;

    function automatic [7:0] exp_byte(input integer idx);
        exp_byte = (idx * 8'h11) & 8'hFF;
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            uart_count <= 0;
        end else if (uart_write && dut.u_io.uart_busy && dut.u_io.mmio_ready) begin
            $fatal(1, "UART write accepted while busy: wdata=0x%02x",
                   dut.u_io.mmio_wdata[7:0]);
        end else if (uart_accept) begin
            if (uart_count < UART_BYTES) begin
                uart_bytes[uart_count] <= dut.u_io.mmio_wdata[7:0];
                if (dut.u_io.mmio_wdata[7:0] !== exp_byte(uart_count)) begin
                    $fatal(1, "UART byte[%0d] mismatch: got 0x%02x expected 0x%02x",
                           uart_count, dut.u_io.mmio_wdata[7:0], exp_byte(uart_count));
                end
            end
            $display("uart[%0d]=0x%02x", uart_count, dut.u_io.mmio_wdata[7:0]);
            uart_count <= uart_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer i;
    initial begin
        rst_n = 1'b0;
        btn = 5'b00000;
        sw = 8'h00;

        repeat (2) @(posedge clk);
        @(negedge clk);

        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            dut.u_mem.mem[i] = NOP;
        end

        // UART seq imm program @ 0x0000_0000
        dut.u_mem.mem[0]  = 32'h400014B7;
        dut.u_mem.mem[1]  = 32'h0084A383;
        dut.u_mem.mem[2]  = 32'h0013F393;
        dut.u_mem.mem[3]  = 32'hFE039CE3;
        dut.u_mem.mem[4]  = 32'h00000313;
        dut.u_mem.mem[5]  = 32'h0064A223;
        dut.u_mem.mem[6]  = 32'h0084A383;
        dut.u_mem.mem[7]  = 32'h0013F393;
        dut.u_mem.mem[8]  = 32'hFE039CE3;
        dut.u_mem.mem[9]  = 32'h01100313;
        dut.u_mem.mem[10] = 32'h0064A223;
        dut.u_mem.mem[11] = 32'h0084A383;
        dut.u_mem.mem[12] = 32'h0013F393;
        dut.u_mem.mem[13] = 32'hFE039CE3;
        dut.u_mem.mem[14] = 32'h02200313;
        dut.u_mem.mem[15] = 32'h0064A223;
        dut.u_mem.mem[16] = 32'h0084A383;
        dut.u_mem.mem[17] = 32'h0013F393;
        dut.u_mem.mem[18] = 32'hFE039CE3;
        dut.u_mem.mem[19] = 32'h03300313;
        dut.u_mem.mem[20] = 32'h0064A223;
        dut.u_mem.mem[21] = 32'h0084A383;
        dut.u_mem.mem[22] = 32'h0013F393;
        dut.u_mem.mem[23] = 32'hFE039CE3;
        dut.u_mem.mem[24] = 32'h04400313;
        dut.u_mem.mem[25] = 32'h0064A223;
        dut.u_mem.mem[26] = 32'h0084A383;
        dut.u_mem.mem[27] = 32'h0013F393;
        dut.u_mem.mem[28] = 32'hFE039CE3;
        dut.u_mem.mem[29] = 32'h05500313;
        dut.u_mem.mem[30] = 32'h0064A223;
        dut.u_mem.mem[31] = 32'h0084A383;
        dut.u_mem.mem[32] = 32'h0013F393;
        dut.u_mem.mem[33] = 32'hFE039CE3;
        dut.u_mem.mem[34] = 32'h06600313;
        dut.u_mem.mem[35] = 32'h0064A223;
        dut.u_mem.mem[36] = 32'h0084A383;
        dut.u_mem.mem[37] = 32'h0013F393;
        dut.u_mem.mem[38] = 32'hFE039CE3;
        dut.u_mem.mem[39] = 32'h07700313;
        dut.u_mem.mem[40] = 32'h0064A223;
        dut.u_mem.mem[41] = 32'h0084A383;
        dut.u_mem.mem[42] = 32'h0013F393;
        dut.u_mem.mem[43] = 32'hFE039CE3;
        dut.u_mem.mem[44] = 32'h08800313;
        dut.u_mem.mem[45] = 32'h0064A223;
        dut.u_mem.mem[46] = 32'h0084A383;
        dut.u_mem.mem[47] = 32'h0013F393;
        dut.u_mem.mem[48] = 32'hFE039CE3;
        dut.u_mem.mem[49] = 32'h09900313;
        dut.u_mem.mem[50] = 32'h0064A223;
        dut.u_mem.mem[51] = 32'h0084A383;
        dut.u_mem.mem[52] = 32'h0013F393;
        dut.u_mem.mem[53] = 32'hFE039CE3;
        dut.u_mem.mem[54] = 32'h0AA00313;
        dut.u_mem.mem[55] = 32'h0064A223;
        dut.u_mem.mem[56] = 32'h0084A383;
        dut.u_mem.mem[57] = 32'h0013F393;
        dut.u_mem.mem[58] = 32'hFE039CE3;
        dut.u_mem.mem[59] = 32'h0BB00313;
        dut.u_mem.mem[60] = 32'h0064A223;
        dut.u_mem.mem[61] = 32'h0084A383;
        dut.u_mem.mem[62] = 32'h0013F393;
        dut.u_mem.mem[63] = 32'hFE039CE3;
        dut.u_mem.mem[64] = 32'h0CC00313;
        dut.u_mem.mem[65] = 32'h0064A223;
        dut.u_mem.mem[66] = 32'h0084A383;
        dut.u_mem.mem[67] = 32'h0013F393;
        dut.u_mem.mem[68] = 32'hFE039CE3;
        dut.u_mem.mem[69] = 32'h0DD00313;
        dut.u_mem.mem[70] = 32'h0064A223;
        dut.u_mem.mem[71] = 32'h0084A383;
        dut.u_mem.mem[72] = 32'h0013F393;
        dut.u_mem.mem[73] = 32'hFE039CE3;
        dut.u_mem.mem[74] = 32'h0EE00313;
        dut.u_mem.mem[75] = 32'h0064A223;
        dut.u_mem.mem[76] = 32'h0084A383;
        dut.u_mem.mem[77] = 32'h0013F393;
        dut.u_mem.mem[78] = 32'hFE039CE3;
        dut.u_mem.mem[79] = 32'h0FF00313;
        dut.u_mem.mem[80] = 32'h0064A223;
        dut.u_mem.mem[81] = 32'h00000063;

        // hart1 loop @ 0x0000_0200
        dut.u_mem.mem[128] = 32'h00000063;

        rst_n = 1'b1;
        @(negedge clk);
        dut.u_cpu.pc[1] = 32'h0000_0200;

        for (i = 0; i < MAX_CYCLES && uart_count < UART_BYTES; i = i + 1) begin
            @(posedge clk);
        end

        if (uart_count < UART_BYTES) begin
            $fatal(1, "UART accepted only %0d bytes within %0d cycles", uart_count, MAX_CYCLES);
        end

        $display("uart seq imm full check passed");
        $finish;
    end
endmodule
