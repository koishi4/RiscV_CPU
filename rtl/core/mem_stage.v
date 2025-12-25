`timescale 1ns/1ps
`include "defines.vh"

module mem_stage(
    input  exmem_valid,
    input  exmem_is_load,
    input  exmem_mem_we,
    input  [`ADDR_W-1:0] exmem_addr,
    input  [`XLEN-1:0] exmem_wdata,
    input  [`XLEN-1:0] exmem_wb_data_raw,
    input  mem_ready,
    input  [`XLEN-1:0] mem_rdata,
    output mem_req,
    output mem_we,
    output [`ADDR_W-1:0] mem_addr,
    output [`XLEN-1:0] mem_wdata,
    output [`XLEN-1:0] mem_wb_data,
    output mem_stall
);
    wire mem_op = exmem_is_load || exmem_mem_we;

    assign mem_req = exmem_valid && mem_op;
    assign mem_we = mem_req && exmem_mem_we;
    assign mem_addr = exmem_addr;
    assign mem_wdata = exmem_wdata;
    assign mem_wb_data = exmem_is_load ? mem_rdata : exmem_wb_data_raw;
    assign mem_stall = mem_req && !mem_ready;
endmodule
