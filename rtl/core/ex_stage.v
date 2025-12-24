`include "defines.vh"

module ex_stage(
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,
    input  [`XLEN-1:0] rs1_val,
    input  [`XLEN-1:0] rs2_val,
    input  [`XLEN-1:0] imm,
    input  [`XLEN-1:0] pc_in,
    output reg [`XLEN-1:0] alu_result,
    output reg branch_taken,
    output reg [`XLEN-1:0] branch_target
);
    wire is_op_imm = (opcode == 7'b0010011);
    wire is_op     = (opcode == 7'b0110011);
    wire is_add    = (funct3 == 3'b000) && (funct7 == 7'b0000000);
    wire is_branch = (opcode == 7'b1100011);
    wire is_load   = (opcode == 7'b0000011);
    wire is_store  = (opcode == 7'b0100011);
    wire is_lui    = (opcode == 7'b0110111);
    wire is_auipc  = (opcode == 7'b0010111);
    wire is_jal    = (opcode == 7'b1101111);
    wire is_jalr   = (opcode == 7'b1100111) && (funct3 == 3'b000);

    always @(*) begin
        alu_result = {`XLEN{1'b0}};
        branch_taken = 1'b0;
        branch_target = {`XLEN{1'b0}};
        if (is_op_imm && (funct3 == 3'b000)) begin
            alu_result = rs1_val + imm; // ADDI
        end else if (is_op && is_add) begin
            alu_result = rs1_val + rs2_val; // ADD
        end else if (is_load || is_store) begin
            alu_result = rs1_val + imm; // effective address for LW/SW
        end else if (is_lui) begin
            alu_result = imm; // LUI
        end else if (is_auipc) begin
            alu_result = pc_in + imm; // AUIPC
        end

        if (is_branch) begin
            branch_target = pc_in + imm;
            if (funct3 == 3'b000) begin
                branch_taken = (rs1_val == rs2_val); // BEQ
            end else if (funct3 == 3'b001) begin
                branch_taken = (rs1_val != rs2_val); // BNE
            end else begin
                branch_taken = 1'b0;
            end
        end else if (is_jal) begin
            branch_taken = 1'b1;
            branch_target = pc_in + imm;
        end else if (is_jalr) begin
            branch_taken = 1'b1;
            branch_target = (rs1_val + imm) & ~32'b1;
        end
    end
endmodule
