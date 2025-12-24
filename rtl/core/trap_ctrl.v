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
    // Combinational trap decision for machine external interrupt.
    wire mstatus_mie = mstatus[`MSTATUS_MIE_BIT];
    wire mie_meie    = mie[`MIE_MEIE_BIT];
    wire mip_meip    = mip[`MIP_MEIP_BIT];

    assign take_trap    = mstatus_mie && mie_meie && mip_meip;
    assign trap_hart_id = hart_id;
    assign trap_vector  = mtvec;
    assign trap_mepc    = pc_in;
    assign trap_mcause  = `MCAUSE_MEI;
endmodule
