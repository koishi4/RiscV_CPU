`timescale 1ns/1ps
`include "defines.vh"

module tb_demo_dma_irq;
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

    localparam [`ADDR_W-1:0] DMA_SRC_ADDR  = 32'h0000_0200;
    localparam [`ADDR_W-1:0] DMA_DST_ADDR  = 32'h0000_0300;
    localparam [`XLEN-1:0]   DMA_LEN_BYTES = 32'h0000_0010;
    localparam [`ADDR_W-1:0] FLAG_ADDR     = 32'h0000_0400;

    localparam integer SRC_IDX  = DMA_SRC_ADDR >> 2;
    localparam integer DST_IDX  = DMA_DST_ADDR >> 2;
    localparam integer FLAG_IDX = FLAG_ADDR >> 2;

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

        // hart0 program @ 0x0000_0000
        dut.u_mem.mem[0]  = 32'h10000093; // addi x1, x0, 0x100 (mtvec)
        dut.u_mem.mem[1]  = NOP;
        dut.u_mem.mem[2]  = NOP;
        dut.u_mem.mem[3]  = 32'h30509073; // csrrw x0, mtvec, x1
        dut.u_mem.mem[4]  = 32'h80000113; // addi x2, x0, 0x800 (MEIE)
        dut.u_mem.mem[5]  = NOP;
        dut.u_mem.mem[6]  = NOP;
        dut.u_mem.mem[7]  = 32'h30412073; // csrrs x0, mie, x2
        dut.u_mem.mem[8]  = 32'h00800193; // addi x3, x0, 8 (MSTATUS.MIE)
        dut.u_mem.mem[9]  = NOP;
        dut.u_mem.mem[10] = NOP;
        dut.u_mem.mem[11] = 32'h3001a073; // csrrs x0, mstatus, x3
        dut.u_mem.mem[12] = 32'h40000537; // lui x10, 0x40000 (DMA base)
        dut.u_mem.mem[13] = 32'h40000793; // addi x15, x0, 0x400 (flag addr)
        dut.u_mem.mem[14] = NOP;
        dut.u_mem.mem[15] = NOP;
        dut.u_mem.mem[16] = 32'h20000593; // addi x11, x0, 0x200 (src)
        dut.u_mem.mem[17] = NOP;
        dut.u_mem.mem[18] = NOP;
        dut.u_mem.mem[19] = 32'h00b52023; // sw x11, 0(x10)
        dut.u_mem.mem[20] = 32'h30000613; // addi x12, x0, 0x300 (dst)
        dut.u_mem.mem[21] = NOP;
        dut.u_mem.mem[22] = NOP;
        dut.u_mem.mem[23] = 32'h00c52223; // sw x12, 4(x10)
        dut.u_mem.mem[24] = 32'h01000693; // addi x13, x0, 0x10 (len)
        dut.u_mem.mem[25] = NOP;
        dut.u_mem.mem[26] = NOP;
        dut.u_mem.mem[27] = 32'h00d52423; // sw x13, 8(x10)
        dut.u_mem.mem[28] = 32'h00300713; // addi x14, x0, 3 (start|irq_en)
        dut.u_mem.mem[29] = NOP;
        dut.u_mem.mem[30] = NOP;
        dut.u_mem.mem[31] = 32'h00e52623; // sw x14, 12(x10)
        dut.u_mem.mem[32] = 32'h0007a283; // lw x5, 0(x15)
        dut.u_mem.mem[33] = NOP;
        dut.u_mem.mem[34] = NOP;
        dut.u_mem.mem[35] = 32'h00029463; // bne x5, x0, +8
        dut.u_mem.mem[36] = 32'hfe0008e3; // beq x0, x0, -16
        dut.u_mem.mem[37] = 32'h00000063; // beq x0, x0, 0

        // ISR @ 0x0000_0100
        dut.u_mem.mem[64] = 32'h00100113; // addi x2, x0, 1
        dut.u_mem.mem[65] = 32'h400014b7; // lui x9, 0x40001 (IO base)
        dut.u_mem.mem[66] = NOP;
        dut.u_mem.mem[67] = 32'h0027a023; // sw x2, 0(x15) (flag)
        dut.u_mem.mem[68] = 32'h0024a023; // sw x2, 0(x9) (LED)
        dut.u_mem.mem[69] = NOP;
        dut.u_mem.mem[70] = 32'h00252a23; // sw x2, 20(x10) (DMA_CLR)
        dut.u_mem.mem[71] = 32'h30200073; // mret

        // hart1 program @ 0x0000_0180
        dut.u_mem.mem[96] = 32'h00000063; // beq x0, x0, 0

        // DMA source data
        dut.u_mem.mem[SRC_IDX + 0] = 32'h1111_1111;
        dut.u_mem.mem[SRC_IDX + 1] = 32'h2222_2222;
        dut.u_mem.mem[SRC_IDX + 2] = 32'h3333_3333;
        dut.u_mem.mem[SRC_IDX + 3] = 32'h4444_4444;
        dut.u_mem.mem[DST_IDX + 0] = 32'h0000_0000;
        dut.u_mem.mem[DST_IDX + 1] = 32'h0000_0000;
        dut.u_mem.mem[DST_IDX + 2] = 32'h0000_0000;
        dut.u_mem.mem[DST_IDX + 3] = 32'h0000_0000;

        rst_n = 1'b1;
        @(negedge clk);
        dut.u_cpu.pc[1] = 32'h0000_0180;

        repeat (800) @(posedge clk);

        $display("dma_irq flag=%0d led=0x%04x", dut.u_mem.mem[FLAG_IDX], led);
        $display("dst[0]=0x%08x dst[1]=0x%08x dst[2]=0x%08x dst[3]=0x%08x",
                 dut.u_mem.mem[DST_IDX + 0],
                 dut.u_mem.mem[DST_IDX + 1],
                 dut.u_mem.mem[DST_IDX + 2],
                 dut.u_mem.mem[DST_IDX + 3]);

        if (dut.u_mem.mem[FLAG_IDX] !== 32'd1) $fatal(1, "ISR flag not set: %0d", dut.u_mem.mem[FLAG_IDX]);
        if (led[0] !== 1'b1) $fatal(1, "LED0 not set");
        if (dut.u_mem.mem[DST_IDX + 0] !== 32'h1111_1111) $fatal(1, "DMA dst[0] mismatch");
        if (dut.u_mem.mem[DST_IDX + 1] !== 32'h2222_2222) $fatal(1, "DMA dst[1] mismatch");
        if (dut.u_mem.mem[DST_IDX + 2] !== 32'h3333_3333) $fatal(1, "DMA dst[2] mismatch");
        if (dut.u_mem.mem[DST_IDX + 3] !== 32'h4444_4444) $fatal(1, "DMA dst[3] mismatch");

        $display("dma irq demo passed");
        $finish;
    end
endmodule
