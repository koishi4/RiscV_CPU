`timescale 1ns/1ps
`include "defines.vh"

module hazard_fwd(
    input  [`REG_ADDR_W-1:0] rs1_addr,
    input  [`REG_ADDR_W-1:0] rs2_addr,
    input  [`XLEN-1:0] rs1_val_in,
    input  [`XLEN-1:0] rs2_val_in,
    input  exmem_wb_en,
    input  [`REG_ADDR_W-1:0] exmem_rd,
    input  [`XLEN-1:0] exmem_wb_data,
    input  exwb_wb_en,
    input  [`REG_ADDR_W-1:0] exwb_rd,
    input  [`XLEN-1:0] exwb_wb_data,
    output reg [`XLEN-1:0] rs1_val_out,
    output reg [`XLEN-1:0] rs2_val_out
);
    // Simple priority forwarding: EX/MEM wins over MEM/WB.
    always @(*) begin
        rs1_val_out = rs1_val_in;
        rs2_val_out = rs2_val_in;

        if (exmem_wb_en && (exmem_rd != {`REG_ADDR_W{1'b0}}) && (exmem_rd == rs1_addr)) begin
            rs1_val_out = exmem_wb_data;
        end else if (exwb_wb_en && (exwb_rd != {`REG_ADDR_W{1'b0}}) && (exwb_rd == rs1_addr)) begin
            rs1_val_out = exwb_wb_data;
        end

        if (exmem_wb_en && (exmem_rd != {`REG_ADDR_W{1'b0}}) && (exmem_rd == rs2_addr)) begin
            rs2_val_out = exmem_wb_data;
        end else if (exwb_wb_en && (exwb_rd != {`REG_ADDR_W{1'b0}}) && (exwb_rd == rs2_addr)) begin
            rs2_val_out = exwb_wb_data;
        end
    end
endmodule
