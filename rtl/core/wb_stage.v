`timescale 1ns/1ps
`include "defines.vh"

module wb_stage(
    input  exec_valid,
    input  mem_stall,
    input  exwb_valid,
    input  [`HART_ID_W-1:0] exwb_hart_id,
    input  [`REG_ADDR_W-1:0] exwb_rd,
    input  [`XLEN-1:0] exwb_data,
    input  muldiv_pending,
    input  [`HART_ID_W-1:0] muldiv_pending_hart_id,
    input  [`REG_ADDR_W-1:0] muldiv_pending_rd,
    input  [`XLEN-1:0] muldiv_pending_result,
    output wb_we,
    output [`HART_ID_W-1:0] wb_hart_id,
    output [`REG_ADDR_W-1:0] wb_rd,
    output [`XLEN-1:0] wb_data,
    output wb_stall,
    output muldiv_wb_fire
);
    wire muldiv_need_port = muldiv_pending && (muldiv_pending_rd != {`REG_ADDR_W{1'b0}});
    wire wb_ex_req = exec_valid && !mem_stall && exwb_valid &&
                     (exwb_rd != {`REG_ADDR_W{1'b0}});
    wire wb_use_muldiv = muldiv_need_port;
    wire wb_use_ex = wb_ex_req && !wb_use_muldiv;

    assign muldiv_wb_fire = muldiv_pending && (!muldiv_need_port || wb_use_muldiv);
    assign wb_stall = muldiv_need_port && wb_ex_req;

    assign wb_we = (wb_use_muldiv && (muldiv_pending_rd != {`REG_ADDR_W{1'b0}})) || wb_use_ex;
    assign wb_hart_id = wb_use_muldiv ? muldiv_pending_hart_id : exwb_hart_id;
    assign wb_rd = wb_use_muldiv ? muldiv_pending_rd : exwb_rd;
    assign wb_data = wb_use_muldiv ? muldiv_pending_result : exwb_data;
endmodule
