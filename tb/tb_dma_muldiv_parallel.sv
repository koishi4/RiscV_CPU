`timescale 1ns/1ps
`include "defines.vh"

module tb_dma_muldiv_parallel;
    reg clk;
    reg rst_n;
    reg [4:0] btn;
    wire [`IO_LED_WIDTH-1:0] led;
    wire [7:0] seg0;
    wire [7:0] seg1;
    wire [7:0] seg_an;
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
    localparam [`XLEN-1:0]   DMA_LEN_BYTES = 32'h0000_0100;
    localparam [`ADDR_W-1:0] COUNT_ADDR    = 32'h0000_0500;

    localparam integer SRC_IDX   = DMA_SRC_ADDR >> 2;
    localparam integer DST_IDX   = DMA_DST_ADDR >> 2;
    localparam integer COUNT_IDX = COUNT_ADDR >> 2;

    localparam integer MAX_CYCLES = 8000;

    integer i;
    integer cycles;
    integer dma_busy_cycles;
    integer overlap_cycles;
    integer muldiv_start_count;
    integer muldiv_done_count;
    integer first_overlap_cycle;
    reg seen_overlap;
    reg [31:0] last_count;
    reg saw_progress;
    reg dma_busy_d;

    wire dma_busy = (dut.u_dma.state != 2'd0);

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            dma_busy_cycles <= 0;
            overlap_cycles <= 0;
            muldiv_start_count <= 0;
            muldiv_done_count <= 0;
            first_overlap_cycle <= 0;
            seen_overlap <= 1'b0;
            last_count <= 32'd0;
            saw_progress <= 1'b0;
            dma_busy_d <= 1'b0;
        end else begin
            cycles <= cycles + 1;
            dma_busy_d <= dma_busy;
            if (dma_busy) begin
                dma_busy_cycles <= dma_busy_cycles + 1;
            end

            if (!dma_busy_d && dma_busy) begin
                $display("DMA busy start: t=%0t cycle=%0d", $time, cycles);
            end
            if (dma_busy_d && !dma_busy) begin
                $display("DMA busy end  : t=%0t cycle=%0d", $time, cycles);
            end

            if (dut.muldiv_start) begin
                muldiv_start_count <= muldiv_start_count + 1;
                $display("MULDIV start: t=%0t cycle=%0d op=%0d hart=%0d a=0x%08x b=0x%08x",
                         $time, cycles, dut.muldiv_op, dut.muldiv_hart_id,
                         dut.muldiv_a, dut.muldiv_b);
            end

            if (dut.muldiv_done) begin
                muldiv_done_count <= muldiv_done_count + 1;
                $display("MULDIV done : t=%0t cycle=%0d hart=%0d rd=%0d result=0x%08x",
                         $time, cycles, dut.muldiv_done_hart_id,
                         dut.muldiv_done_rd, dut.muldiv_result);
            end

            if (dma_busy && dut.muldiv_busy) begin
                overlap_cycles <= overlap_cycles + 1;
                if (!seen_overlap) begin
                    seen_overlap <= 1'b1;
                    first_overlap_cycle <= cycles;
                    $display("OVERLAP: DMA busy + MULDIV busy at t=%0t cycle=%0d",
                             $time, cycles);
                end
            end

            if (dma_busy && (dut.u_mem.mem[COUNT_IDX] != last_count)) begin
                last_count <= dut.u_mem.mem[COUNT_IDX];
                saw_progress <= 1'b1;
                $display("COUNT update while DMA busy: t=%0t cycle=%0d count=%0d",
                         $time, cycles, dut.u_mem.mem[COUNT_IDX]);
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        btn = 5'b00000;

        repeat (2) @(posedge clk);
        @(negedge clk);

        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            dut.u_mem.mem[i] = NOP;
        end

        // hart0: delay, then issue mul/div sequence (no looped branch encoding needed).
        for (i = 0; i < 8; i = i + 1) begin
            dut.u_mem.mem[i] = NOP;
        end
        dut.u_mem.mem[8]  = 32'h00a00093; // addi x1, x0, 10
        dut.u_mem.mem[9]  = 32'h00300113; // addi x2, x0, 3
        dut.u_mem.mem[10] = NOP;
        dut.u_mem.mem[11] = NOP;
        dut.u_mem.mem[12] = 32'h022081b3; // mul x3, x1, x2
        dut.u_mem.mem[13] = 32'h0220c233; // div x4, x1, x2
        dut.u_mem.mem[14] = 32'h0220e2b3; // rem x5, x1, x2
        dut.u_mem.mem[15] = 32'h022081b3; // mul x3, x1, x2
        dut.u_mem.mem[16] = 32'h0220c233; // div x4, x1, x2
        dut.u_mem.mem[17] = 32'h0220e2b3; // rem x5, x1, x2
        dut.u_mem.mem[18] = 32'h022081b3; // mul x3, x1, x2
        dut.u_mem.mem[19] = 32'h0220c233; // div x4, x1, x2
        dut.u_mem.mem[20] = 32'h0220e2b3; // rem x5, x1, x2
        dut.u_mem.mem[21] = 32'h00000063; // beq x0, x0, 0

        // hart1: start DMA then loop incrementing a counter in RAM.
        dut.u_mem.mem[96]  = 32'h40000537; // lui x10, 0x40000 (DMA base)
        dut.u_mem.mem[97]  = 32'h20000593; // addi x11, x0, 0x200 (src)
        dut.u_mem.mem[98]  = NOP;
        dut.u_mem.mem[99]  = NOP;
        dut.u_mem.mem[100] = 32'h00b52023; // sw x11, 0(x10)
        dut.u_mem.mem[101] = 32'h30000613; // addi x12, x0, 0x300 (dst)
        dut.u_mem.mem[102] = NOP;
        dut.u_mem.mem[103] = NOP;
        dut.u_mem.mem[104] = 32'h00c52223; // sw x12, 4(x10)
        dut.u_mem.mem[105] = 32'h10000693; // addi x13, x0, 0x100 (len)
        dut.u_mem.mem[106] = NOP;
        dut.u_mem.mem[107] = NOP;
        dut.u_mem.mem[108] = 32'h00d52423; // sw x13, 8(x10)
        dut.u_mem.mem[109] = 32'h00100713; // addi x14, x0, 1 (start)
        dut.u_mem.mem[110] = NOP;
        dut.u_mem.mem[111] = NOP;
        dut.u_mem.mem[112] = 32'h00e52623; // sw x14, 12(x10)
        dut.u_mem.mem[113] = 32'h50000793; // addi x15, x0, 0x500 (counter addr)
        dut.u_mem.mem[114] = 32'h00000093; // addi x1, x0, 0
        dut.u_mem.mem[115] = 32'h00108093; // addi x1, x1, 1
        dut.u_mem.mem[116] = 32'h0017a023; // sw x1, 0(x15)
        dut.u_mem.mem[117] = 32'hfe000ce3; // beq x0, x0, -8

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
        if (muldiv_done_count == 0) begin
            $fatal(1, "MULDIV never completed");
        end
        if (!seen_overlap) begin
            $fatal(1, "No overlap between DMA busy and MULDIV busy observed");
        end

        if (dut.u_cpu.u_regfile.regs[0][3] !== 32'd30) begin
            $fatal(1, "hart0 x3 mismatch: %0d", dut.u_cpu.u_regfile.regs[0][3]);
        end
        if (dut.u_cpu.u_regfile.regs[0][4] !== 32'd3) begin
            $fatal(1, "hart0 x4 mismatch: %0d", dut.u_cpu.u_regfile.regs[0][4]);
        end
        if (dut.u_cpu.u_regfile.regs[0][5] !== 32'd1) begin
            $fatal(1, "hart0 x5 mismatch: %0d", dut.u_cpu.u_regfile.regs[0][5]);
        end

        for (i = 0; i < (DMA_LEN_BYTES >> 2); i = i + 1) begin
            if (dut.u_mem.mem[DST_IDX + i] !== 32'hA000_0000 + i) begin
                $fatal(1, "DMA dst mismatch idx=%0d exp=%08x got=%08x",
                       i, 32'hA000_0000 + i, dut.u_mem.mem[DST_IDX + i]);
            end
        end

        $display("SUMMARY: dma_busy_cycles=%0d muldiv_start=%0d muldiv_done=%0d overlap_cycles=%0d first_overlap_cycle=%0d",
                 dma_busy_cycles, muldiv_start_count, muldiv_done_count,
                 overlap_cycles, first_overlap_cycle);
        $display("dma + muldiv parallel demo completed");
        $finish;
    end
endmodule
