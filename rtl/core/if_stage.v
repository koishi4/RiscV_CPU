`timescale 1ns/1ps
`include "defines.vh"

module if_stage(
    input  [`XLEN-1:0] pc_in,
    input  if_valid,
    input  [`XLEN-1:0] mem_rdata,
    input  mem_ready,
    output mem_req,
    output [`ADDR_W-1:0] mem_addr,
    output [`XLEN-1:0] inst_out,
    output inst_valid,
    output [`XLEN-1:0] pc_next
);
    // Simple fetch: request current PC, assume word-aligned instruction.
    assign mem_req   = if_valid;
    assign mem_addr  = pc_in;
    assign inst_out  = mem_rdata;
    assign inst_valid = if_valid && mem_ready;
    assign pc_next   = pc_in + 32'd4;
endmodule
