`timescale 1ns/1ps
`include "defines.vh"

module mem_concurrency_tb;
    reg clk;
    reg rst_n;

    reg a_mem_req;
    reg a_mem_we;
    reg [`ADDR_W-1:0] a_mem_addr;
    reg [`XLEN-1:0] a_mem_wdata;
    wire [`XLEN-1:0] a_mem_rdata;
    wire a_mem_ready;

    reg b_mem_req;
    reg b_mem_we;
    reg [`ADDR_W-1:0] b_mem_addr;
    reg [`XLEN-1:0] b_mem_wdata;
    wire [`XLEN-1:0] b_mem_rdata;
    wire b_mem_ready;

    dualport_bram dut (
        .clk(clk),
        .rst_n(rst_n),
        .a_mem_req(a_mem_req),
        .a_mem_we(a_mem_we),
        .a_mem_addr(a_mem_addr),
        .a_mem_wdata(a_mem_wdata),
        .a_mem_rdata(a_mem_rdata),
        .a_mem_ready(a_mem_ready),
        .b_mem_req(b_mem_req),
        .b_mem_we(b_mem_we),
        .b_mem_addr(b_mem_addr),
        .b_mem_wdata(b_mem_wdata),
        .b_mem_rdata(b_mem_rdata),
        .b_mem_ready(b_mem_ready)
    );

    localparam integer REGION_WORDS = 32;
    localparam [`ADDR_W-1:0] A_BASE = 32'h0000_0000;
    localparam [`ADDR_W-1:0] B_SRC_BASE = 32'h0000_1000;
    localparam [`ADDR_W-1:0] B_DST_BASE = 32'h0000_2000;
    localparam [`ADDR_W-1:0] SAME_BASE = 32'h0000_3000;
    localparam [`ADDR_W-1:0] A_RAND_BASE = 32'h0000_4000;
    localparam [`ADDR_W-1:0] B_RAND_BASE = 32'h0000_6000;

    function [`ADDR_W-1:0] addr_from_base;
        input [`ADDR_W-1:0] base;
        input integer word_idx;
        begin
            addr_from_base = base + (word_idx * 4);
        end
    endfunction

    task automatic a_write;
        input [`ADDR_W-1:0] addr;
        input [`XLEN-1:0] data;
        begin
            @(negedge clk);
            a_mem_req = 1'b1;
            a_mem_we = 1'b1;
            a_mem_addr = addr;
            a_mem_wdata = data;
            @(posedge clk);
            if (!a_mem_ready) begin
                $display("ERROR: a_mem_ready low on write");
                $finish;
            end
            @(negedge clk);
            a_mem_req = 1'b0;
            a_mem_we = 1'b0;
        end
    endtask

    task automatic b_write;
        input [`ADDR_W-1:0] addr;
        input [`XLEN-1:0] data;
        begin
            @(negedge clk);
            b_mem_req = 1'b1;
            b_mem_we = 1'b1;
            b_mem_addr = addr;
            b_mem_wdata = data;
            @(posedge clk);
            if (!b_mem_ready) begin
                $display("ERROR: b_mem_ready low on write");
                $finish;
            end
            @(negedge clk);
            b_mem_req = 1'b0;
            b_mem_we = 1'b0;
        end
    endtask

    task automatic a_read;
        input [`ADDR_W-1:0] addr;
        output [`XLEN-1:0] data;
        begin
            @(negedge clk);
            a_mem_req = 1'b1;
            a_mem_we = 1'b0;
            a_mem_addr = addr;
            a_mem_wdata = {`XLEN{1'b0}};
            @(posedge clk);
            if (!a_mem_ready) begin
                $display("ERROR: a_mem_ready low on read");
                $finish;
            end
            data = a_mem_rdata;
            @(negedge clk);
            a_mem_req = 1'b0;
        end
    endtask

    task automatic b_read;
        input [`ADDR_W-1:0] addr;
        output [`XLEN-1:0] data;
        begin
            @(negedge clk);
            b_mem_req = 1'b1;
            b_mem_we = 1'b0;
            b_mem_addr = addr;
            b_mem_wdata = {`XLEN{1'b0}};
            @(posedge clk);
            if (!b_mem_ready) begin
                $display("ERROR: b_mem_ready low on read");
                $finish;
            end
            data = b_mem_rdata;
            @(negedge clk);
            b_mem_req = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        integer i;
        reg [`XLEN-1:0] tmp;
        reg [`XLEN-1:0] got;
        reg [`XLEN-1:0] exp_data;
        reg [`XLEN-1:0] rand_a [0:REGION_WORDS-1];
        reg [`XLEN-1:0] rand_b [0:REGION_WORDS-1];

        rst_n = 1'b0;
        a_mem_req = 1'b0;
        a_mem_we = 1'b0;
        a_mem_addr = {`ADDR_W{1'b0}};
        a_mem_wdata = {`XLEN{1'b0}};
        b_mem_req = 1'b0;
        b_mem_we = 1'b0;
        b_mem_addr = {`ADDR_W{1'b0}};
        b_mem_wdata = {`XLEN{1'b0}};

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Directed concurrency: A writes region A while B copies region B.
        for (i = 0; i < REGION_WORDS; i = i + 1) begin
            b_write(addr_from_base(B_SRC_BASE, i), 32'hCAFE_0000 + i);
            b_write(addr_from_base(B_DST_BASE, i), 32'hDEAD_BEEF);
        end

        fork
            begin : port_a_writer
                integer j;
                for (j = 0; j < REGION_WORDS; j = j + 1) begin
                    a_write(addr_from_base(A_BASE, j), 32'h1111_0000 + j);
                end
            end
            begin : port_b_copier
                integer k;
                for (k = 0; k < REGION_WORDS; k = k + 1) begin
                    b_read(addr_from_base(B_SRC_BASE, k), tmp);
                    b_write(addr_from_base(B_DST_BASE, k), tmp);
                end
            end
        join

        for (i = 0; i < REGION_WORDS; i = i + 1) begin
            a_read(addr_from_base(A_BASE, i), got);
            exp_data = 32'h1111_0000 + i;
            if (got !== exp_data) begin
                $display("ERROR: A region mismatch idx=%0d exp=%h got=%h", i, exp_data, got);
                $finish;
            end
        end

        for (i = 0; i < REGION_WORDS; i = i + 1) begin
            b_read(addr_from_base(B_DST_BASE, i), got);
            exp_data = 32'hCAFE_0000 + i;
            if (got !== exp_data) begin
                $display("ERROR: B copy mismatch idx=%0d exp=%h got=%h", i, exp_data, got);
                $finish;
            end
        end

        // Deterministic same-address write (port B wins).
        fork
            begin
                @(negedge clk);
                a_mem_req = 1'b1;
                a_mem_we = 1'b1;
                a_mem_addr = SAME_BASE;
                a_mem_wdata = 32'hAAAA_AAAA;
                @(posedge clk);
                @(negedge clk);
                a_mem_req = 1'b0;
                a_mem_we = 1'b0;
            end
            begin
                @(negedge clk);
                b_mem_req = 1'b1;
                b_mem_we = 1'b1;
                b_mem_addr = SAME_BASE;
                b_mem_wdata = 32'hBBBB_BBBB;
                @(posedge clk);
                @(negedge clk);
                b_mem_req = 1'b0;
                b_mem_we = 1'b0;
            end
        join

        a_read(SAME_BASE, got);
        if (got !== 32'hBBBB_BBBB) begin
            $display("ERROR: same-address write priority mismatch got=%h", got);
            $finish;
        end

        // Randomized concurrent access in disjoint regions.
        for (i = 0; i < REGION_WORDS; i = i + 1) begin
            rand_a[i] = $urandom;
            rand_b[i] = $urandom;
            a_write(addr_from_base(A_RAND_BASE, i), rand_a[i]);
            b_write(addr_from_base(B_RAND_BASE, i), rand_b[i]);
        end

        fork
            begin : port_a_random
                integer m;
                integer idx;
                reg [`XLEN-1:0] data;
                for (m = 0; m < 200; m = m + 1) begin
                    idx = $urandom_range(0, REGION_WORDS - 1);
                    if ($urandom_range(0, 1)) begin
                        data = $urandom;
                        rand_a[idx] = data;
                        a_write(addr_from_base(A_RAND_BASE, idx), data);
                    end else begin
                        a_read(addr_from_base(A_RAND_BASE, idx), data);
                        if (data !== rand_a[idx]) begin
                            $display("ERROR: random A read mismatch idx=%0d exp=%h got=%h", idx, rand_a[idx], data);
                            $finish;
                        end
                    end
                end
            end
            begin : port_b_random
                integer n;
                integer idx;
                reg [`XLEN-1:0] data;
                for (n = 0; n < 200; n = n + 1) begin
                    idx = $urandom_range(0, REGION_WORDS - 1);
                    if ($urandom_range(0, 1)) begin
                        data = $urandom;
                        rand_b[idx] = data;
                        b_write(addr_from_base(B_RAND_BASE, idx), data);
                    end else begin
                        b_read(addr_from_base(B_RAND_BASE, idx), data);
                        if (data !== rand_b[idx]) begin
                            $display("ERROR: random B read mismatch idx=%0d exp=%h got=%h", idx, rand_b[idx], data);
                            $finish;
                        end
                    end
                end
            end
        join

        $display("mem_concurrency_tb PASS");
        $finish;
    end
endmodule
