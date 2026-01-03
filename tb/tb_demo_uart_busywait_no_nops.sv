`timescale 1ns/1ps
`include "defines.vh"

module tb_demo_uart_busywait_no_nops;
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

    localparam [`XLEN-1:0] NOP = 32'h0000_0013;
    localparam integer MEM_DEPTH = (`MEM_SIZE_BYTES / 4);
    localparam [`ADDR_W-1:0] UART_TX_ADDR = `IO_BASE_ADDR + `IO_UART_TX_OFFSET;

    integer i;
    integer tx_attempted;
    integer tx_accepted;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_attempted <= 0;
            tx_accepted <= 0;
        end else begin
            if (dut.io_mmio_req && dut.io_mmio_we && (dut.io_mmio_addr == UART_TX_ADDR)) begin
                tx_attempted <= tx_attempted + 1;
                if (dut.u_io.uart_busy) begin
                    $fatal(1, "UART write attempted while busy (attempt=%0d)", tx_attempted);
                end
                tx_accepted <= tx_accepted + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);

        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            dut.u_mem.mem[i] = NOP;
        end

        // Program @ 0x0000_0000:
        //   csrr x5, mhartid
        //   bne  x5, x0, hart1_entry
        // hart0:
        //   lui  x9, 0x40001
        //   addi x6, x0, 0x55
        //   sw   x6, 0(x9)        ; LED
        // wait:
        //   lw   x7, 8(x9)        ; UART_STAT
        //   andi x7, x7, 1
        //   bne  x7, x0, wait
        //   sw   x6, 4(x9)        ; UART_TX
        //   beq  x0, x0, wait
        // hart1_entry @ 0x0000_0100:
        //   beq  x0, x0, 0
        dut.u_mem.mem[0] = 32'hF140_22F3; // csrrs x5, mhartid, x0
        dut.u_mem.mem[1] = 32'h0E02_9E63; // bne x5, x0, +252 (to 0x100)
        dut.u_mem.mem[2] = 32'h4000_14B7; // lui x9, 0x40001
        dut.u_mem.mem[3] = 32'h0550_0313; // addi x6, x0, 0x55
        dut.u_mem.mem[4] = 32'h0064_A023; // sw x6, 0(x9)
        dut.u_mem.mem[5] = 32'h0084_A383; // lw x7, 8(x9)
        dut.u_mem.mem[6] = 32'h0013_F393; // andi x7, x7, 1
        dut.u_mem.mem[7] = 32'hFE03_9CE3; // bne x7, x0, -8
        dut.u_mem.mem[8] = 32'h0064_A223; // sw x6, 4(x9)
        dut.u_mem.mem[9] = 32'hFE00_08E3; // beq x0, x0, -16

        // hart1 idle @ 0x0000_0100
        dut.u_mem.mem[64] = 32'h0000_0063; // beq x0, x0, 0

        rst_n = 1'b1;

        repeat (120000) @(posedge clk);

        $display("tx_attempted=%0d tx_accepted=%0d led=0x%04x", tx_attempted, tx_accepted, led);
        if (tx_attempted < 2) $fatal(1, "no UART TX writes observed");
        if (tx_attempted !== tx_accepted) $fatal(1, "UART writes dropped: attempted=%0d accepted=%0d", tx_attempted, tx_accepted);

        $display("uart busy-wait no-nops demo passed");
        $finish;
    end
endmodule
