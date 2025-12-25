`timescale 1ns/1ps
`include "defines.vh"

module mmio_decode_tb;
    reg clk;
    reg rst_n;

    reg cpu_mem_req;
    reg cpu_mem_we;
    reg [`ADDR_W-1:0] cpu_mem_addr;
    reg [`XLEN-1:0] cpu_mem_wdata;
    wire [`XLEN-1:0] cpu_mem_rdata;
    wire cpu_mem_ready;

    wire ram_mem_req;
    wire ram_mem_we;
    wire [`ADDR_W-1:0] ram_mem_addr;
    wire [`XLEN-1:0] ram_mem_wdata;
    wire [`XLEN-1:0] ram_mem_rdata;
    wire ram_mem_ready;

    wire dma_mmio_req;
    wire dma_mmio_we;
    wire [`ADDR_W-1:0] dma_mmio_addr;
    wire [`XLEN-1:0] dma_mmio_wdata;
    wire [`XLEN-1:0] dma_mmio_rdata;
    wire dma_mmio_ready;

    mmio_decode dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_mem_req(cpu_mem_req),
        .cpu_mem_we(cpu_mem_we),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mem_rdata),
        .cpu_mem_ready(cpu_mem_ready),
        .ram_mem_req(ram_mem_req),
        .ram_mem_we(ram_mem_we),
        .ram_mem_addr(ram_mem_addr),
        .ram_mem_wdata(ram_mem_wdata),
        .ram_mem_rdata(ram_mem_rdata),
        .ram_mem_ready(ram_mem_ready),
        .dma_mmio_req(dma_mmio_req),
        .dma_mmio_we(dma_mmio_we),
        .dma_mmio_addr(dma_mmio_addr),
        .dma_mmio_wdata(dma_mmio_wdata),
        .dma_mmio_rdata(dma_mmio_rdata),
        .dma_mmio_ready(dma_mmio_ready)
    );

    localparam integer MEM_WORDS = 256;
    localparam integer MEM_IDX_W = $clog2(MEM_WORDS);
    reg [`XLEN-1:0] mem [0:MEM_WORDS-1];
    wire [MEM_IDX_W-1:0] ram_idx = ram_mem_addr[MEM_IDX_W+1:2];

    assign ram_mem_rdata = mem[ram_idx];
    assign ram_mem_ready = ram_mem_req;

    assign dma_mmio_rdata = 32'hD00D_0000 | {26'b0, dma_mmio_addr[5:2]};
    assign dma_mmio_ready = dma_mmio_req;

    always @(posedge clk) begin
        if (ram_mem_req && ram_mem_we) begin
            mem[ram_idx] <= ram_mem_wdata;
        end
    end

    task automatic check_decode;
        input expected_dma;
        begin
            if (cpu_mem_ready !== cpu_mem_req) begin
                $display("ERROR: cpu_mem_ready mismatch req=%b ready=%b", cpu_mem_req, cpu_mem_ready);
                $finish;
            end
            if (expected_dma) begin
                if (!dma_mmio_req || ram_mem_req) begin
                    $display("ERROR: decode mismatch, expected DMA");
                    $finish;
                end
                if (dma_mmio_we !== cpu_mem_we) begin
                    $display("ERROR: dma_mmio_we mismatch");
                    $finish;
                end
            end else begin
                if (!ram_mem_req || dma_mmio_req) begin
                    $display("ERROR: decode mismatch, expected RAM");
                    $finish;
                end
                if (ram_mem_we !== cpu_mem_we) begin
                    $display("ERROR: ram_mem_we mismatch");
                    $finish;
                end
            end
        end
    endtask

    task automatic cpu_write;
        input [`ADDR_W-1:0] addr;
        input [`XLEN-1:0] data;
        input expected_dma;
        begin
            @(negedge clk);
            cpu_mem_req = 1'b1;
            cpu_mem_we = 1'b1;
            cpu_mem_addr = addr;
            cpu_mem_wdata = data;
            @(posedge clk);
            check_decode(expected_dma);
            @(negedge clk);
            cpu_mem_req = 1'b0;
            cpu_mem_we = 1'b0;
        end
    endtask

    task automatic cpu_read;
        input [`ADDR_W-1:0] addr;
        output [`XLEN-1:0] data;
        input expected_dma;
        begin
            @(negedge clk);
            cpu_mem_req = 1'b1;
            cpu_mem_we = 1'b0;
            cpu_mem_addr = addr;
            cpu_mem_wdata = {`XLEN{1'b0}};
            @(posedge clk);
            check_decode(expected_dma);
            data = cpu_mem_rdata;
            @(negedge clk);
            cpu_mem_req = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        integer i;
        reg [`XLEN-1:0] data;
        reg expected_dma;
        reg [`ADDR_W-1:0] addr;

        rst_n = 1'b0;
        cpu_mem_req = 1'b0;
        cpu_mem_we = 1'b0;
        cpu_mem_addr = {`ADDR_W{1'b0}};
        cpu_mem_wdata = {`XLEN{1'b0}};
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = {`XLEN{1'b0}};
        end

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // No request: ready should be low.
        @(posedge clk);
        if (cpu_mem_ready !== 1'b0) begin
            $display("ERROR: cpu_mem_ready asserted without request");
            $finish;
        end

        // RAM write/read.
        addr = 32'h0000_0010;
        cpu_write(addr, 32'h1234_5678, 1'b0);
        cpu_read(addr, data, 1'b0);
        if (data !== 32'h1234_5678) begin
            $display("ERROR: RAM readback mismatch exp=12345678 got=%h", data);
            $finish;
        end

        // DMA MMIO read path.
        addr = `DMA_BASE_ADDR;
        cpu_read(addr, data, 1'b1);
        if (data !== (32'hD00D_0000 | {26'b0, addr[5:2]})) begin
            $display("ERROR: DMA MMIO rdata mismatch got=%h", data);
            $finish;
        end

        // Boundary: DMA range end and next word.
        addr = `DMA_BASE_ADDR + 32'h1C;
        cpu_read(addr, data, 1'b1);
        addr = `DMA_BASE_ADDR + 32'h20;
        cpu_read(addr, data, 1'b0);

        // Random decode checks.
        for (i = 0; i < 200; i = i + 1) begin
            @(negedge clk);
            cpu_mem_req = $urandom_range(0, 1);
            cpu_mem_we = $urandom_range(0, 1);
            cpu_mem_addr = $urandom;
            cpu_mem_wdata = $urandom;
            expected_dma = cpu_mem_req &&
                           ((cpu_mem_addr & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);
            @(posedge clk);
            if (!cpu_mem_req) begin
                if (ram_mem_req || dma_mmio_req || cpu_mem_ready) begin
                    $display("ERROR: activity without request");
                    $finish;
                end
            end else begin
                check_decode(expected_dma);
            end
        end

        $display("mmio_decode_tb PASS");
        $finish;
    end
endmodule
