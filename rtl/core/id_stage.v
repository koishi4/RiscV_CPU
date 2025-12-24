`include "defines.vh"

module id_stage(
    input  [`XLEN-1:0] inst_in,
    input  [`XLEN-1:0] pc_in,
    input  [`XLEN-1:0] rdata1,
    input  [`XLEN-1:0] rdata2,
    output [`REG_ADDR_W-1:0] rs1,
    output [`REG_ADDR_W-1:0] rs2,
    output [`REG_ADDR_W-1:0] rd,
    output [6:0] opcode,
    output [2:0] funct3,
    output [6:0] funct7,
    output reg [`XLEN-1:0] imm,
    output [`XLEN-1:0] rs1_val,
    output [`XLEN-1:0] rs2_val
);
    wire [`XLEN-1:0] imm_i = {{20{inst_in[31]}}, inst_in[31:20]};
    wire [`XLEN-1:0] imm_s = {{20{inst_in[31]}}, inst_in[31:25], inst_in[11:7]};
    wire [`XLEN-1:0] imm_b = {{19{inst_in[31]}}, inst_in[31], inst_in[7], inst_in[30:25], inst_in[11:8], 1'b0};
    wire [`XLEN-1:0] imm_u = {inst_in[31:12], 12'b0};
    wire [`XLEN-1:0] imm_j = {{11{inst_in[31]}}, inst_in[31], inst_in[19:12], inst_in[20], inst_in[30:21], 1'b0};

    assign opcode = inst_in[6:0];
    assign rd     = inst_in[11:7];
    assign funct3 = inst_in[14:12];
    assign rs1    = inst_in[19:15];
    assign rs2    = inst_in[24:20];
    assign funct7 = inst_in[31:25];

    always @(*) begin
        case (opcode)
            7'b0010011: imm = imm_i; // OP-IMM
            7'b0000011: imm = imm_i; // LOAD
            7'b1100111: imm = imm_i; // JALR
            7'b0100011: imm = imm_s; // STORE
            7'b1100011: imm = imm_b; // BRANCH
            7'b0110111: imm = imm_u; // LUI
            7'b0010111: imm = imm_u; // AUIPC
            7'b1101111: imm = imm_j; // JAL
            7'b1110011: imm = imm_i; // SYSTEM
            default:    imm = imm_i;
        endcase
    end

    assign rs1_val = rdata1;
    assign rs2_val = rdata2;
endmodule
