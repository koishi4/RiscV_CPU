`include "defines.vh"

module regfile_bank(
    input  clk,
    input  rst_n,
    input  [`HART_ID_W-1:0] r_hart_id,
    input  [`REG_ADDR_W-1:0] raddr1,
    input  [`REG_ADDR_W-1:0] raddr2,
    output [`XLEN-1:0] rdata1,
    output [`XLEN-1:0] rdata2,
    input  w_en,
    input  [`HART_ID_W-1:0] w_hart_id,
    input  [`REG_ADDR_W-1:0] waddr,
    input  [`XLEN-1:0] wdata
);
    // TODO: 2-bank regfile, x0 hardwired to 0 for each hart.

    assign rdata1 = {`XLEN{1'b0}};
    assign rdata2 = {`XLEN{1'b0}};
endmodule
