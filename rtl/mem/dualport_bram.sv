`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module dualport_bram #(
    parameter integer RESET_CLEARS = `MEM_RESET_CLEARS,
    parameter string INIT_FILE = `MEM_INIT_FILE
) (
    input  clk,
    input  rst_n,
    `MEM_REQ_PORTS(input, a_mem),
    `MEM_RSP_PORTS(output, a_mem),
    `MEM_REQ_PORTS(input, b_mem),
    `MEM_RSP_PORTS(output, b_mem)
);
    // True dual-port RAM model; concurrent writes to same address resolve to port B.

    localparam integer DEPTH = (`MEM_SIZE_BYTES / 4);
    localparam integer ADDR_IDX_W = $clog2(DEPTH);

    (* ram_style = "block" *) reg [`XLEN-1:0] mem [0:DEPTH-1];

    wire [ADDR_IDX_W-1:0] a_idx = a_mem_addr[ADDR_IDX_W+1:2];
    wire [ADDR_IDX_W-1:0] b_idx = b_mem_addr[ADDR_IDX_W+1:2];

    reg [`XLEN-1:0] a_mem_rdata_r;
    reg [`XLEN-1:0] b_mem_rdata_r;
    reg a_mem_ready_r;
    reg b_mem_ready_r;

    integer i;
`ifndef SYNTHESIS
    reg reset_cleared;
`endif
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    wire same_addr_write = a_mem_req && a_mem_we && // A口想写
                           b_mem_req && b_mem_we && // B口也想写
                           (a_idx == b_idx); // 写的是同一个格子

    // Port A: synchronous read/write. When both ports write same address, port B wins.
    always @(posedge clk) begin
        if (!rst_n) begin
            a_mem_rdata_r <= {`XLEN{1'b0}};
            a_mem_ready_r <= 1'b0;
            if (RESET_CLEARS) begin
`ifndef SYNTHESIS
                if (!reset_cleared) begin
                    for (i = 0; i < DEPTH; i = i + 1) begin
                        mem[i] <= {`XLEN{1'b0}};
                    end
                    reset_cleared <= 1'b1;
                end
`else
                for (i = 0; i < DEPTH; i = i + 1) begin
                    mem[i] <= {`XLEN{1'b0}};
                end
`endif
            end
        end else begin
`ifndef SYNTHESIS
            reset_cleared <= 1'b0;
`endif
            a_mem_ready_r <= a_mem_req;
            if (a_mem_req) begin
                if (a_mem_we) begin
                    if (!same_addr_write) begin
                        mem[a_idx] <= a_mem_wdata;
                    end
                end else begin // 读操作总是发生的
                    a_mem_rdata_r <= mem[a_idx];
                end
            end
        end
    end

    // Port B: synchronous read/write.
    always @(posedge clk) begin
        if (!rst_n) begin
            b_mem_rdata_r <= {`XLEN{1'b0}};
            b_mem_ready_r <= 1'b0;
        end else begin
            b_mem_ready_r <= b_mem_req;
            if (b_mem_req) begin
                if (b_mem_we) begin
                    mem[b_idx] <= b_mem_wdata;
                end else begin
                    b_mem_rdata_r <= mem[b_idx];
                end
            end
        end
    end

    assign a_mem_rdata = a_mem_rdata_r;
    assign b_mem_rdata = b_mem_rdata_r;
    assign a_mem_ready = a_mem_ready_r;
    assign b_mem_ready = b_mem_ready_r;
endmodule
