`timescale 1ns/1ps
`include "defines.vh"

module tb_dma_cpu_parallel;
    reg clk;
    reg rst_n;
    wire [`IO_LED_WIDTH-1:0] led;
    wire [7:0] seg0;
    wire [7:0] seg1;
    wire [7:0] seg_an;
    reg [4:0] btn;
    wire uart_tx;

    soc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .led(led),
        .seg0(seg0),
        .seg1(seg1),
        .seg_an(seg_an),
        .btn(btn),
        .uart_tx(uart_tx)
    );

    localparam [`XLEN-1:0] NOP = 32'h00000013;
    localparam integer MEM_DEPTH = (`MEM_SIZE_BYTES / 4);

    localparam [`ADDR_W-1:0] DMA_SRC_ADDR  = 32'h0000_0200;
    localparam [`ADDR_W-1:0] DMA_DST_ADDR  = 32'h0000_0300;
    localparam [`XLEN-1:0]   DMA_LEN_BYTES = 32'h0000_0040;
    localparam [`ADDR_W-1:0] COUNT_ADDR    = 32'h0000_0500;

    localparam integer SRC_IDX   = DMA_SRC_ADDR >> 2;
    localparam integer DST_IDX   = DMA_DST_ADDR >> 2;
    localparam integer COUNT_IDX = COUNT_ADDR >> 2;

    localparam integer MAX_CYCLES = 5000;

    integer i;
    reg [31:0] last_count;
    reg saw_progress;
    integer dma_busy_cycles;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            last_count <= 32'd0;
            saw_progress <= 1'b0;
            dma_busy_cycles <= 0;
        end else begin
            if (dut.u_dma.state != 2'd0) begin
                dma_busy_cycles <= dma_busy_cycles + 1;
                if (dut.u_mem.mem[COUNT_IDX] != last_count) begin
                    saw_progress <= 1'b1;
                    last_count <= dut.u_mem.mem[COUNT_IDX];
                end
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        btn = 5'b00000;

        repeat (2) @(posedge clk);
        @(negedge clk);

        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            dut.u_mem.mem[i] = NOP;
        end

        // hart0: start DMA then loop incrementing a counter in RAM
        dut.u_mem.mem[0]  = 32'h40000537; // lui x10, 0x40000 (DMA base)
        dut.u_mem.mem[1]  = 32'h20000593; // addi x11, x0, 0x200 (src)
        dut.u_mem.mem[2]  = NOP;
        dut.u_mem.mem[3]  = NOP;
        dut.u_mem.mem[4]  = 32'h00b52023; // sw x11, 0(x10)
        dut.u_mem.mem[5]  = 32'h30000613; // addi x12, x0, 0x300 (dst)
        dut.u_mem.mem[6]  = NOP;
        dut.u_mem.mem[7]  = NOP;
        dut.u_mem.mem[8]  = 32'h00c52223; // sw x12, 4(x10)
        dut.u_mem.mem[9]  = 32'h04000693; // addi x13, x0, 0x40 (len)
        dut.u_mem.mem[10] = NOP;
        dut.u_mem.mem[11] = NOP;
        dut.u_mem.mem[12] = 32'h00d52423; // sw x13, 8(x10)
        dut.u_mem.mem[13] = 32'h00100713; // addi x14, x0, 1 (start)
        dut.u_mem.mem[14] = NOP;
        dut.u_mem.mem[15] = NOP;
        dut.u_mem.mem[16] = 32'h00e52623; // sw x14, 12(x10)
        dut.u_mem.mem[17] = 32'h50000793; // addi x15, x0, 0x500 (counter addr)
        dut.u_mem.mem[18] = 32'h00000093; // addi x1, x0, 0
        dut.u_mem.mem[19] = 32'h00108093; // addi x1, x1, 1
        dut.u_mem.mem[20] = 32'h0017a023; // sw x1, 0(x15)
        dut.u_mem.mem[21] = 32'hfe000ce3; // beq x0, x0, -8

        // hart1 idle
        dut.u_mem.mem[96] = 32'h00000063; // beq x0, x0, 0

        // DMA source data + clear destination + counter.
        for (i = 0; i < (DMA_LEN_BYTES >> 2); i = i + 1) begin
            dut.u_mem.mem[SRC_IDX + i] = 32'hA000_0000 + i;
            dut.u_mem.mem[DST_IDX + i] = 32'h0000_0000;
        end
        dut.u_mem.mem[COUNT_IDX] = 32'h0000_0000;

        rst_n = 1'b1;
        @(negedge clk);
        dut.u_cpu.pc[1] = 32'h0000_0180;

        repeat (MAX_CYCLES) @(posedge clk);

        if (dma_busy_cycles == 0) begin
            $fatal(1, "DMA never entered busy state");
        end
        if (!saw_progress) begin
            $fatal(1, "CPU did not update counter while DMA was busy");
        end

        for (i = 0; i < (DMA_LEN_BYTES >> 2); i = i + 1) begin
            if (dut.u_mem.mem[DST_IDX + i] !== 32'hA000_0000 + i) begin
                $fatal(1, "DMA dst mismatch idx=%0d exp=%08x got=%08x",
                       i, 32'hA000_0000 + i, dut.u_mem.mem[DST_IDX + i]);
            end
        end

        $display("dma/cpu parallel test passed");
        $finish;
    end
endmodule
