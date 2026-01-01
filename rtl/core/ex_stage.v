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
    output reg [`XLEN-1:0] branch_target,
    output reg custom_valid
);
    wire is_op_imm = (opcode == 7'b0010011);
    wire is_op     = (opcode == 7'b0110011);
    wire is_muldiv = is_op && (funct7 == 7'b0000001);
    wire is_custom0 = (opcode == `OPCODE_CUSTOM0);
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

    integer i;
    wire [7:0] rs1_b0 = rs1_val[7:0];
    wire [7:0] rs1_b1 = rs1_val[15:8];
    wire [7:0] rs1_b2 = rs1_val[23:16];
    wire [7:0] rs1_b3 = rs1_val[31:24];
    wire [7:0] rs2_b0 = rs2_val[7:0];
    wire [7:0] rs2_b1 = rs2_val[15:8];
    wire [7:0] rs2_b2 = rs2_val[23:16];
    wire [7:0] rs2_b3 = rs2_val[31:24];

    function [8:0] sext8;
        input [7:0] val;
        begin
            sext8 = {val[7], val};
        end
    endfunction

    function [7:0] sat8;
        input [9:0] val;
        begin
            if ($signed(val) > 10'sd127) begin
                sat8 = 8'h7f;
            end else if ($signed(val) < -10'sd128) begin
                sat8 = 8'h80;
            end else begin
                sat8 = val[7:0];
            end
        end
    endfunction

    function [15:0] sat16;
        input [17:0] val;
        begin
            if ($signed(val) > 18'sd32767) begin
                sat16 = 16'h7fff;
            end else if ($signed(val) < -18'sd32768) begin
                sat16 = 16'h8000;
            end else begin
                sat16 = val[15:0];
            end
        end
    endfunction

    function [7:0] abs8;
        input [7:0] val;
        reg [8:0] s;
        begin
            s = sext8(val);
            if ($signed(s) == -9'sd128) begin
                abs8 = 8'h7f;
            end else if (s[8]) begin
                abs8 = (~s + 1'b1);
            end else begin
                abs8 = s[7:0];
            end
        end
    endfunction

    function [7:0] clamp8;
        input [7:0] val;
        input [4:0] lim;
        integer sval;
        integer lim_s;
        integer neg_lim;
        begin
            sval = $signed({val[7], val});
            lim_s = lim;
            neg_lim = -lim_s;
            if (sval > lim_s) begin
                clamp8 = lim_s[7:0];
            end else if (sval < neg_lim) begin
                clamp8 = neg_lim[7:0];
            end else begin
                clamp8 = sval[7:0];
            end
        end
    endfunction

    function [7:0] shl8i_byte;
        input [7:0] val;
        input [2:0] shamt;
        begin
            shl8i_byte = val << shamt;
        end
    endfunction

    function [7:0] sru8i_byte;
        input [7:0] val;
        input [2:0] shamt;
        begin
            sru8i_byte = val >> shamt;
        end
    endfunction

    function [7:0] shr8i_byte;
        input [7:0] val;
        input [2:0] shamt;
        integer tmp;
        begin
            tmp = $signed({{8{val[7]}}, val});
            tmp = tmp >>> shamt;
            shr8i_byte = tmp[7:0];
        end
    endfunction

    function [7:0] rshr8i_byte;
        input [7:0] val;
        input [2:0] shamt;
        integer tmp;
        begin
            if (shamt == 3'd0) begin
                rshr8i_byte = val;
            end else begin
                tmp = $signed({{8{val[7]}}, val});
                tmp = tmp + (1 << (shamt - 1));
                tmp = tmp >>> shamt;
                rshr8i_byte = tmp[7:0];
            end
        end
    endfunction

    function [`XLEN-1:0] dot4_ss;
        input [31:0] a;
        input [31:0] b;
        reg [7:0] a0;
        reg [7:0] a1;
        reg [7:0] a2;
        reg [7:0] a3;
        reg [7:0] b0;
        reg [7:0] b1;
        reg [7:0] b2;
        reg [7:0] b3;
        integer acc;
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            acc = ($signed(sext8(a0)) * $signed(sext8(b0))) +
                  ($signed(sext8(a1)) * $signed(sext8(b1))) +
                  ($signed(sext8(a2)) * $signed(sext8(b2))) +
                  ($signed(sext8(a3)) * $signed(sext8(b3)));
            dot4_ss = acc;
        end
    endfunction

    function [`XLEN-1:0] dot4_su;
        input [31:0] a;
        input [31:0] b;
        reg [7:0] a0;
        reg [7:0] a1;
        reg [7:0] a2;
        reg [7:0] a3;
        reg [7:0] b0;
        reg [7:0] b1;
        reg [7:0] b2;
        reg [7:0] b3;
        integer acc;
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            acc = ($signed(sext8(a0)) * $signed({1'b0, b0})) +
                  ($signed(sext8(a1)) * $signed({1'b0, b1})) +
                  ($signed(sext8(a2)) * $signed({1'b0, b2})) +
                  ($signed(sext8(a3)) * $signed({1'b0, b3}));
            dot4_su = acc;
        end
    endfunction

    function [`XLEN-1:0] dot4_uu;
        input [31:0] a;
        input [31:0] b;
        reg [7:0] a0;
        reg [7:0] a1;
        reg [7:0] a2;
        reg [7:0] a3;
        reg [7:0] b0;
        reg [7:0] b1;
        reg [7:0] b2;
        reg [7:0] b3;
        integer acc;
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            acc = ({1'b0, a0} * {1'b0, b0}) +
                  ({1'b0, a1} * {1'b0, b1}) +
                  ({1'b0, a2} * {1'b0, b2}) +
                  ({1'b0, a3} * {1'b0, b3});
            dot4_uu = acc;
        end
    endfunction

    always @(*) begin
        alu_result = {`XLEN{1'b0}};
        branch_taken = 1'b0;
        branch_target = {`XLEN{1'b0}};
        custom_valid = 1'b0;
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
        end else if (is_custom0) begin
            custom_valid = 1'b1;
            case (funct3)
                `CUST3_DOTMAC: begin
                    case (funct7)
                        `CUST7_DOT4_SS: alu_result = dot4_ss(rs1_val, rs2_val);
                        `CUST7_DOT4_SU: alu_result = dot4_su(rs1_val, rs2_val);
                        `CUST7_DOT4_UU: alu_result = dot4_uu(rs1_val, rs2_val);
                        default: custom_valid = 1'b0;
                    endcase
                end
                `CUST3_ADDSUB: begin
                    case (funct7)
                        `CUST7_ADD8:
                            alu_result = {rs1_b3 + rs2_b3, rs1_b2 + rs2_b2,
                                          rs1_b1 + rs2_b1, rs1_b0 + rs2_b0};
                        `CUST7_SUB8:
                            alu_result = {rs1_b3 - rs2_b3, rs1_b2 - rs2_b2,
                                          rs1_b1 - rs2_b1, rs1_b0 - rs2_b0};
                        `CUST7_ADDSAT8:
                            alu_result = {sat8(sext8(rs1_b3) + sext8(rs2_b3)),
                                          sat8(sext8(rs1_b2) + sext8(rs2_b2)),
                                          sat8(sext8(rs1_b1) + sext8(rs2_b1)),
                                          sat8(sext8(rs1_b0) + sext8(rs2_b0))};
                        `CUST7_SUBSAT8:
                            alu_result = {sat8(sext8(rs1_b3) - sext8(rs2_b3)),
                                          sat8(sext8(rs1_b2) - sext8(rs2_b2)),
                                          sat8(sext8(rs1_b1) - sext8(rs2_b1)),
                                          sat8(sext8(rs1_b0) - sext8(rs2_b0))};
                        default: custom_valid = 1'b0;
                    endcase
                end
                `CUST3_MISC: begin
                    case (funct7)
                        `CUST7_MAX8:
                            alu_result = {(sext8(rs1_b3) >= sext8(rs2_b3)) ? rs1_b3 : rs2_b3,
                                          (sext8(rs1_b2) >= sext8(rs2_b2)) ? rs1_b2 : rs2_b2,
                                          (sext8(rs1_b1) >= sext8(rs2_b1)) ? rs1_b1 : rs2_b1,
                                          (sext8(rs1_b0) >= sext8(rs2_b0)) ? rs1_b0 : rs2_b0};
                        `CUST7_MIN8:
                            alu_result = {(sext8(rs1_b3) <= sext8(rs2_b3)) ? rs1_b3 : rs2_b3,
                                          (sext8(rs1_b2) <= sext8(rs2_b2)) ? rs1_b2 : rs2_b2,
                                          (sext8(rs1_b1) <= sext8(rs2_b1)) ? rs1_b1 : rs2_b1,
                                          (sext8(rs1_b0) <= sext8(rs2_b0)) ? rs1_b0 : rs2_b0};
                        `CUST7_ABS8:
                            alu_result = {abs8(rs1_b3), abs8(rs1_b2),
                                          abs8(rs1_b1), abs8(rs1_b0)};
                        `CUST7_AVG8:
                            alu_result = {({1'b0, rs1_b3} + {1'b0, rs2_b3} + 9'd1) >> 1,
                                          ({1'b0, rs1_b2} + {1'b0, rs2_b2} + 9'd1) >> 1,
                                          ({1'b0, rs1_b1} + {1'b0, rs2_b1} + 9'd1) >> 1,
                                          ({1'b0, rs1_b0} + {1'b0, rs2_b0} + 9'd1) >> 1};
                        `CUST7_ADD16: begin
                            alu_result[15:0]  = rs1_val[15:0] + rs2_val[15:0];
                            alu_result[31:16] = rs1_val[31:16] + rs2_val[31:16];
                        end
                        `CUST7_ADDSAT16: begin
                            alu_result[15:0]  = sat16($signed({rs1_val[15], rs1_val[15:0]}) +
                                                     $signed({rs2_val[15], rs2_val[15:0]}));
                            alu_result[31:16] = sat16($signed({rs1_val[31], rs1_val[31:16]}) +
                                                     $signed({rs2_val[31], rs2_val[31:16]}));
                        end
                        default: custom_valid = 1'b0;
                    endcase
                end
                `CUST3_SHIFT: begin
                    case (funct7)
                        `CUST7_SHL8I:
                            alu_result = {shl8i_byte(rs1_b3, imm[2:0]),
                                          shl8i_byte(rs1_b2, imm[2:0]),
                                          shl8i_byte(rs1_b1, imm[2:0]),
                                          shl8i_byte(rs1_b0, imm[2:0])};
                        `CUST7_SHR8I:
                            alu_result = {shr8i_byte(rs1_b3, imm[2:0]),
                                          shr8i_byte(rs1_b2, imm[2:0]),
                                          shr8i_byte(rs1_b1, imm[2:0]),
                                          shr8i_byte(rs1_b0, imm[2:0])};
                        `CUST7_SRU8I:
                            alu_result = {sru8i_byte(rs1_b3, imm[2:0]),
                                          sru8i_byte(rs1_b2, imm[2:0]),
                                          sru8i_byte(rs1_b1, imm[2:0]),
                                          sru8i_byte(rs1_b0, imm[2:0])};
                        `CUST7_RSHR8I:
                            alu_result = {rshr8i_byte(rs1_b3, imm[2:0]),
                                          rshr8i_byte(rs1_b2, imm[2:0]),
                                          rshr8i_byte(rs1_b1, imm[2:0]),
                                          rshr8i_byte(rs1_b0, imm[2:0])};
                        `CUST7_CLAMP8I:
                            alu_result = {clamp8(rs1_b3, imm[4:0]),
                                          clamp8(rs1_b2, imm[4:0]),
                                          clamp8(rs1_b1, imm[4:0]),
                                          clamp8(rs1_b0, imm[4:0])};
                        default: custom_valid = 1'b0;
                    endcase
                end
                `CUST3_PACK: begin
                    case (funct7)
                        `CUST7_PACKB: begin
                            alu_result = {rs2_val[15:8], rs2_val[7:0], rs1_val[15:8], rs1_val[7:0]};
                        end
                        `CUST7_UNPK8L_S: begin
                            alu_result[15:0]  = {{8{rs1_val[7]}}, rs1_val[7:0]};
                            alu_result[31:16] = {{8{rs1_val[15]}}, rs1_val[15:8]};
                        end
                        `CUST7_UNPK8H_S: begin
                            alu_result[15:0]  = {{8{rs1_val[23]}}, rs1_val[23:16]};
                            alu_result[31:16] = {{8{rs1_val[31]}}, rs1_val[31:24]};
                        end
                        `CUST7_PACKH: begin
                            alu_result = {rs2_val[15:0], rs1_val[15:0]};
                        end
                        default: custom_valid = 1'b0;
                    endcase
                end
                `CUST3_PERM: begin
                    case (funct7)
                        `CUST7_REV8: alu_result = {rs1_val[7:0], rs1_val[15:8], rs1_val[23:16], rs1_val[31:24]};
                        `CUST7_SWAP16: alu_result = {rs1_val[15:0], rs1_val[31:16]};
                        default: custom_valid = 1'b0;
                    endcase
                end
                `CUST3_RELU: begin
                    case (funct7)
                        `CUST7_RELU8:
                            alu_result = {rs1_b3[7] ? 8'h00 : rs1_b3,
                                          rs1_b2[7] ? 8'h00 : rs1_b2,
                                          rs1_b1[7] ? 8'h00 : rs1_b1,
                                          rs1_b0[7] ? 8'h00 : rs1_b0};
                        default: custom_valid = 1'b0;
                    endcase
                end
                default: custom_valid = 1'b0;
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
