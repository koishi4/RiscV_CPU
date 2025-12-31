`timescale 1ns/1ps
`include "defines.vh"

module dma_tb;
    reg clk;
    reg rst_n;

    reg mmio_req;
    reg mmio_we;
    reg [`ADDR_W-1:0] mmio_addr;
    reg [`XLEN-1:0] mmio_wdata;
    wire [`XLEN-1:0] mmio_rdata;
    wire mmio_ready;

    wire dma_mem_req;
    wire dma_mem_we;
    wire [`ADDR_W-1:0] dma_mem_addr;
    wire [`XLEN-1:0] dma_mem_wdata;
    wire [`XLEN-1:0] dma_mem_rdata;
    reg dma_mem_ready;

    wire dma_irq;

    dma_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .mmio_req(mmio_req),
        .mmio_we(mmio_we),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready),
        .dma_mem_req(dma_mem_req),
        .dma_mem_we(dma_mem_we),
        .dma_mem_addr(dma_mem_addr),
        .dma_mem_wdata(dma_mem_wdata),
        .dma_mem_rdata(dma_mem_rdata),
        .dma_mem_ready(dma_mem_ready),
        .dma_irq(dma_irq)
    );

    localparam [`ADDR_W-1:0] DMA_SRC_ADDR  = `DMA_BASE_ADDR + `DMA_SRC_OFFSET;
    localparam [`ADDR_W-1:0] DMA_DST_ADDR  = `DMA_BASE_ADDR + `DMA_DST_OFFSET;
    localparam [`ADDR_W-1:0] DMA_LEN_ADDR  = `DMA_BASE_ADDR + `DMA_LEN_OFFSET;
    localparam [`ADDR_W-1:0] DMA_CTRL_ADDR = `DMA_BASE_ADDR + `DMA_CTRL_OFFSET;
    localparam [`ADDR_W-1:0] DMA_STAT_ADDR = `DMA_BASE_ADDR + `DMA_STAT_OFFSET;
    localparam [`ADDR_W-1:0] DMA_CLR_ADDR  = `DMA_BASE_ADDR + `DMA_CLR_OFFSET;

    localparam integer MEM_WORDS = 1024;
    reg [`XLEN-1:0] mem [0:MEM_WORDS-1];
    wire [9:0] mem_index = dma_mem_addr[11:2];
    reg stall_enable;

    assign dma_mem_rdata = mem[mem_index];

    always @(posedge clk) begin
        if (dma_mem_req && dma_mem_ready && dma_mem_we) begin
            mem[mem_index] <= dma_mem_wdata;
        end
    end

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_mem_ready <= 1'b0;
        end else if (stall_enable) begin
            dma_mem_ready <= ($urandom_range(0, 3) != 0);
        end else begin
            dma_mem_ready <= 1'b1;
        end
    end

    function integer addr_to_index;
        input [`ADDR_W-1:0] addr;
        begin
            addr_to_index = addr[11:2];
        end
    endfunction

    task automatic mmio_write;
        input [`ADDR_W-1:0] addr;
        input [`XLEN-1:0] data;
        begin
            @(negedge clk);
            mmio_req <= 1'b1;
            mmio_we <= 1'b1;
            mmio_addr <= addr;
            mmio_wdata <= data;
            do begin
                @(posedge clk);
            end while (!mmio_ready);
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
            do begin
                @(posedge clk);
            end while (!mmio_ready);
            @(negedge clk);
            data = mmio_rdata;
            mmio_req <= 1'b0;
            mmio_addr <= {`ADDR_W{1'b0}};
        end
    endtask

    task automatic dma_clear;
        begin
            mmio_write(DMA_CLR_ADDR, (1 << `DMA_CLR_DONE_BIT) | (1 << `DMA_CLR_ERR_BIT));
        end
    endtask

    task automatic dma_start;
        input [`ADDR_W-1:0] src;
        input [`ADDR_W-1:0] dst;
        input [`XLEN-1:0] len;
        input [0:0] irq_en;
        reg [`XLEN-1:0] ctrl_val;
        begin
            mmio_write(DMA_SRC_ADDR, src);
            mmio_write(DMA_DST_ADDR, dst);
            mmio_write(DMA_LEN_ADDR, len);
            ctrl_val = {`XLEN{1'b0}};
            if (irq_en) begin
                ctrl_val = ctrl_val | (1 << `DMA_CTRL_IRQ_EN_BIT);
            end
            ctrl_val = ctrl_val | (1 << `DMA_CTRL_START_BIT);
            mmio_write(DMA_CTRL_ADDR, ctrl_val);
        end
    endtask

    task automatic wait_done;
        input integer timeout;
        output [`XLEN-1:0] stat;
        integer t;
        begin
            stat = {`XLEN{1'b0}};
            for (t = 0; t < timeout; t = t + 1) begin
                mmio_read(DMA_STAT_ADDR, stat);
                if (stat[`DMA_STAT_DONE_BIT]) begin
                    break;
                end
            end
            if (!stat[`DMA_STAT_DONE_BIT]) begin
                $display("ERROR: DMA timeout");
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        integer i;
        integer base_idx;
        integer sticky_i;
        reg [`XLEN-1:0] stat;
        reg [`ADDR_W-1:0] src_base;
        reg [`ADDR_W-1:0] dst_base;
        reg [`XLEN-1:0] len_bytes;

        rst_n = 1'b0;
        mmio_req = 1'b0;
        mmio_we = 1'b0;
        mmio_addr = {`ADDR_W{1'b0}};
        mmio_wdata = {`XLEN{1'b0}};
        stall_enable = 1'b0;

        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = {`XLEN{1'b0}};
        end

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Directed transfer test.
        src_base = 32'h0000_0100;
        dst_base = 32'h0000_0200;
        len_bytes = 32'd16;
        base_idx = addr_to_index(src_base);
        for (i = 0; i < 4; i = i + 1) begin
            mem[base_idx + i] = 32'hA5A5_0000 + i;
        end
        base_idx = addr_to_index(dst_base);
        for (i = 0; i < 4; i = i + 1) begin
            mem[base_idx + i] = 32'hDEAD_BEEF;
        end

        dma_start(src_base, dst_base, len_bytes, 1'b1);
        wait_done(2000, stat);
        if (!dma_irq) begin
            $display("ERROR: dma_irq not asserted on done");
            $finish;
        end
        // Sticky check: irq stays high without DMA_CLR.
        for (sticky_i = 0; sticky_i < 8; sticky_i = sticky_i + 1) begin
            @(posedge clk);
            if (!dma_irq) begin
                $display("ERROR: dma_irq deasserted without DMA_CLR");
                $finish;
            end
        end
        for (sticky_i = 0; sticky_i < 4; sticky_i = sticky_i + 1) begin
            mmio_read(DMA_STAT_ADDR, stat);
            if (!dma_irq) begin
                $display("ERROR: dma_irq cleared by MMIO read");
                $finish;
            end
        end
        mmio_write(DMA_CTRL_ADDR, {`XLEN{1'b0}});
        @(posedge clk);
        if (!dma_irq) begin
            $display("ERROR: dma_irq cleared by CTRL write");
            $finish;
        end
        base_idx = addr_to_index(dst_base);
        for (i = 0; i < 4; i = i + 1) begin
            if (mem[base_idx + i] !== (32'hA5A5_0000 + i)) begin
                $display("ERROR: DMA data mismatch at %0d", i);
                $finish;
            end
        end

        // DONE/IRQ sticky until CLR.
        mmio_read(DMA_STAT_ADDR, stat);
        if (!stat[`DMA_STAT_DONE_BIT]) begin
            $display("ERROR: DONE not sticky");
            $finish;
        end
        dma_clear();
        mmio_read(DMA_STAT_ADDR, stat);
        if (stat[`DMA_STAT_DONE_BIT]) begin
            $display("ERROR: DONE not cleared");
            $finish;
        end
        if (dma_irq) begin
            $display("ERROR: dma_irq not cleared after DMA_CLR");
            $finish;
        end

        // LEN==0 should complete immediately.
        dma_start(src_base, dst_base, 32'd0, 1'b0);
        wait_done(200, stat);
        dma_clear();

        // Unaligned length should raise ERR.
        dma_start(src_base, dst_base, 32'd6, 1'b0);
        wait_done(200, stat);
        if (!stat[`DMA_STAT_ERR_BIT]) begin
            $display("ERROR: ERR not set on unaligned length");
            $finish;
        end
        dma_clear();

        // Randomized transfers with stalls.
        stall_enable = 1'b1;
        for (i = 0; i < 50; i = i + 1) begin
            integer words;
            integer src_idx;
            integer dst_idx;
            integer j;
            words = ($urandom_range(1, 16));
            src_idx = $urandom_range(0, (MEM_WORDS / 2) - words);
            dst_idx = $urandom_range((MEM_WORDS / 2), MEM_WORDS - words);
            src_base = {20'b0, src_idx[9:0], 2'b00};
            dst_base = {20'b0, dst_idx[9:0], 2'b00};
            len_bytes = words * 4;
            for (j = 0; j < words; j = j + 1) begin
                mem[src_idx + j] = $urandom;
                mem[dst_idx + j] = ~mem[src_idx + j];
            end
            dma_start(src_base, dst_base, len_bytes, 1'b0);
            wait_done(5000, stat);
            for (j = 0; j < words; j = j + 1) begin
                if (mem[dst_idx + j] !== mem[src_idx + j]) begin
                    $display("ERROR: Random DMA mismatch at iter %0d idx %0d", i, j);
                    $finish;
                end
            end
            dma_clear();
        end

        $display("dma_tb PASS");
        $finish;
    end
endmodule
