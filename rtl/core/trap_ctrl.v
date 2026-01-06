`timescale 1ns/1ps
`include "defines.vh"

module trap_ctrl(
    input  clk,
    input  rst_n,
    input  [`HART_ID_W-1:0] hart_id,
    input  [`XLEN-1:0] pc_in,
    input  [`XLEN-1:0] mtvec,
    input  [`XLEN-1:0] mstatus,
    input  [`XLEN-1:0] mie,
    input  [`XLEN-1:0] mip,
    output take_trap,
    output [`HART_ID_W-1:0] trap_hart_id,
    output [`XLEN-1:0] trap_vector,
    output [`XLEN-1:0] trap_mepc,
    output [`XLEN-1:0] trap_mcause
);
    // 机器态外部中断判定（组合逻辑）：
    // - 只允许 hart0 响应（当前实现限定）
    // - 同时满足 mstatus.MIE、mie.MEIE、mip.MEIP 才触发
    wire mstatus_mie = mstatus[`MSTATUS_MIE_BIT]; // 全局中断使能
    wire mie_meie    = mie[`MIE_MEIE_BIT];        // 外部中断使能
    wire mip_meip    = mip[`MIP_MEIP_BIT];        // 外部中断挂起

    // take_trap：是否进入异常处理
    // trap_hart_id：触发中断的 hart
    // trap_vector：跳转向量（mtvec，直达模式）
    // trap_mepc：异常返回地址（当前 PC）
    // trap_mcause：异常原因（机器外部中断）
    assign take_trap    = (hart_id == {`HART_ID_W{1'b0}}) &&
                          mstatus_mie && mie_meie && mip_meip;
    assign trap_hart_id = hart_id;
    assign trap_vector  = mtvec;
    assign trap_mepc    = pc_in;
    assign trap_mcause  = `MCAUSE_MEI;
endmodule
