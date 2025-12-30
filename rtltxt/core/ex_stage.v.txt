`timescale 1ns/1ps
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
    wire is_muldiv = is_op && (funct7 == 7'b0000001);
    wire is_branch = (opcode == 7'b1100011);
    wire is_load   = (opcode == 7'b0000011);
    wire is_store  = (opcode == 7'b0100011);
    wire is_lui    = (opcode == 7'b0110111);
    wire is_auipc  = (opcode == 7'b0010111);
    wire is_jal    = (opcode == 7'b1101111);
    wire is_jalr   = (opcode == 7'b1100111) && (funct3 == 3'b000);
    wire [4:0] shamt_imm = imm[4:0];
    wire [4:0] shamt_reg = rs2_val[4:0];
    wire rs1_lt_rs2 = ($signed(rs1_val) < $signed(rs2_val));
    wire rs1_ltu_rs2 = (rs1_val < rs2_val);
    wire rs1_lt_imm = ($signed(rs1_val) < $signed(imm));
    wire rs1_ltu_imm = (rs1_val < imm);

    always @(*) begin
        alu_result = {`XLEN{1'b0}};
        branch_taken = 1'b0;
        branch_target = {`XLEN{1'b0}};
        if (is_op_imm) begin
            case (funct3)
                3'b000: alu_result = rs1_val + imm; // ADDI
                3'b010: alu_result = rs1_lt_imm ? 32'd1 : 32'd0; // SLTI
                3'b011: alu_result = rs1_ltu_imm ? 32'd1 : 32'd0; // SLTIU
                3'b100: alu_result = rs1_val ^ imm; // XORI
                3'b110: alu_result = rs1_val | imm; // ORI
                3'b111: alu_result = rs1_val & imm; // ANDI
                3'b001: alu_result = rs1_val << shamt_imm; // SLLI
                3'b101: begin
                    if (funct7 == 7'b0100000) begin
                        alu_result = $signed(rs1_val) >>> shamt_imm; // SRAI
                    end else begin
                        alu_result = rs1_val >> shamt_imm; // SRLI
                    end
                end
                default: alu_result = {`XLEN{1'b0}};
            endcase
        end else if (is_op && !is_muldiv) begin
            case (funct3)
                3'b000: begin
                    if (funct7 == 7'b0100000) begin
                        alu_result = rs1_val - rs2_val; // SUB
                    end else begin
                        alu_result = rs1_val + rs2_val; // ADD
                    end
                end
                3'b001: alu_result = rs1_val << shamt_reg; // SLL
                3'b010: alu_result = rs1_lt_rs2 ? 32'd1 : 32'd0; // SLT
                3'b011: alu_result = rs1_ltu_rs2 ? 32'd1 : 32'd0; // SLTU
                3'b100: alu_result = rs1_val ^ rs2_val; // XOR
                3'b101: begin
                    if (funct7 == 7'b0100000) begin
                        alu_result = $signed(rs1_val) >>> shamt_reg; // SRA
                    end else begin
                        alu_result = rs1_val >> shamt_reg; // SRL
                    end
                end
                3'b110: alu_result = rs1_val | rs2_val; // OR
                3'b111: alu_result = rs1_val & rs2_val; // AND
                default: alu_result = {`XLEN{1'b0}};
            endcase
        end else if (is_load || is_store) begin
            alu_result = rs1_val + imm; // effective address for LW/SW
        end else if (is_lui) begin
            alu_result = imm; // LUI
        end else if (is_auipc) begin
            alu_result = pc_in + imm; // AUIPC
        end

        if (is_branch) begin
            branch_target = pc_in + imm;
            case (funct3)
                3'b000: branch_taken = (rs1_val == rs2_val); // BEQ
                3'b001: branch_taken = (rs1_val != rs2_val); // BNE
                3'b100: branch_taken = rs1_lt_rs2; // BLT
                3'b101: branch_taken = !rs1_lt_rs2; // BGE
                3'b110: branch_taken = rs1_ltu_rs2; // BLTU
                3'b111: branch_taken = !rs1_ltu_rs2; // BGEU
                default: branch_taken = 1'b0;
            endcase
        end else if (is_jal) begin
            branch_taken = 1'b1;
            branch_target = pc_in + imm;
        end else if (is_jalr) begin
            branch_taken = 1'b1;
            branch_target = (rs1_val + imm) & ~32'b1;
        end
    end
endmodule
