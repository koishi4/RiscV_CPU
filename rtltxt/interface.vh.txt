`ifndef INTERFACE_VH
`define INTERFACE_VH

`include "defines.vh"

// Memory-like request/response interface
`define MEM_REQ_PORTS(dir, prefix) \
    dir                prefix``_req, \
    dir                prefix``_we, \
    dir [`ADDR_W-1:0]  prefix``_addr, \
    dir [`XLEN-1:0]    prefix``_wdata

`define MEM_RSP_PORTS(dir, prefix) \
    dir [`XLEN-1:0]    prefix``_rdata, \
    dir                prefix``_ready

// MMIO interface (same shape as memory)
`define MMIO_REQ_PORTS(dir, prefix) \
    dir                prefix``_req, \
    dir                prefix``_we, \
    dir [`ADDR_W-1:0]  prefix``_addr, \
    dir [`XLEN-1:0]    prefix``_wdata

`define MMIO_RSP_PORTS(dir, prefix) \
    dir [`XLEN-1:0]    prefix``_rdata, \
    dir                prefix``_ready

// MUL/DIV handshake interface
`define MULDIV_REQ_PORTS(dir, prefix) \
    dir                prefix``_start, \
    dir [2:0]          prefix``_op, \
    dir [`XLEN-1:0]    prefix``_a, \
    dir [`XLEN-1:0]    prefix``_b, \
    dir [`HART_ID_W-1:0] prefix``_hart_id, \
    dir [4:0]          prefix``_rd

`define MULDIV_RSP_PORTS(dir, prefix) \
    dir                prefix``_busy, \
    dir                prefix``_done, \
    dir [`XLEN-1:0]    prefix``_result, \
    dir [`HART_ID_W-1:0] prefix``_done_hart_id, \
    dir [4:0]          prefix``_done_rd

// Optional signal bundle declarations (wires)
`define DECL_MEM_IF(prefix) \
    wire               prefix``_req; \
    wire               prefix``_we; \
    wire [`ADDR_W-1:0] prefix``_addr; \
    wire [`XLEN-1:0]   prefix``_wdata; \
    wire [`XLEN-1:0]   prefix``_rdata; \
    wire               prefix``_ready;

`define DECL_MMIO_IF(prefix) \
    wire               prefix``_req; \
    wire               prefix``_we; \
    wire [`ADDR_W-1:0] prefix``_addr; \
    wire [`XLEN-1:0]   prefix``_wdata; \
    wire [`XLEN-1:0]   prefix``_rdata; \
    wire               prefix``_ready;

`define DECL_MULDIV_IF(prefix) \
    wire               prefix``_start; \
    wire [2:0]         prefix``_op; \
    wire [`XLEN-1:0]   prefix``_a; \
    wire [`XLEN-1:0]   prefix``_b; \
    wire [`HART_ID_W-1:0] prefix``_hart_id; \
    wire [4:0]         prefix``_rd; \
    wire               prefix``_busy; \
    wire               prefix``_done; \
    wire [`XLEN-1:0]   prefix``_result; \
    wire [`HART_ID_W-1:0] prefix``_done_hart_id; \
    wire [4:0]         prefix``_done_rd;

`endif
