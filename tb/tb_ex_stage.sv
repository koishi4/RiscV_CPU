`timescale 1ns/1ps
`include "defines.vh"

module tb_ex_stage;
    reg [6:0] opcode;
    reg [2:0] funct3;
    reg [6:0] funct7;
    reg [`XLEN-1:0] rs1_val;
    reg [`XLEN-1:0] rs2_val;
    reg [`XLEN-1:0] imm;
    reg [`XLEN-1:0] pc_in;

    wire [`XLEN-1:0] alu_result;
    wire branch_taken;
    wire [`XLEN-1:0] branch_target;

    ex_stage dut (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .rs1_val(rs1_val),
        .rs2_val(rs2_val),
        .imm(imm),
        .pc_in(pc_in),
        .alu_result(alu_result),
        .branch_taken(branch_taken),
        .branch_target(branch_target)
    );

    function automatic [`XLEN-1:0] ref_alu;
        input [6:0] f_opcode;
        input [2:0] f_funct3;
        input [6:0] f_funct7;
        input [`XLEN-1:0] f_rs1;
        input [`XLEN-1:0] f_rs2;
        input [`XLEN-1:0] f_imm;
        input [`XLEN-1:0] f_pc;
        reg signed [`XLEN-1:0] rs1_s;
        reg signed [`XLEN-1:0] rs2_s;
        reg signed [`XLEN-1:0] imm_s;
        begin
            rs1_s = f_rs1;
            rs2_s = f_rs2;
            imm_s = f_imm;
            ref_alu = {`XLEN{1'b0}};
            case (f_opcode)
                7'b0010011: begin
                    case (f_funct3)
                        3'b000: ref_alu = f_rs1 + f_imm; // ADDI
                        3'b010: ref_alu = (rs1_s < imm_s) ? 32'd1 : 32'd0; // SLTI
                        3'b011: ref_alu = (f_rs1 < f_imm) ? 32'd1 : 32'd0; // SLTIU
                        3'b100: ref_alu = f_rs1 ^ f_imm; // XORI
                        3'b110: ref_alu = f_rs1 | f_imm; // ORI
                        3'b111: ref_alu = f_rs1 & f_imm; // ANDI
                        3'b001: ref_alu = f_rs1 << f_imm[4:0]; // SLLI
                        3'b101: begin
                            if (f_funct7 == 7'b0100000) begin
                                ref_alu = rs1_s >>> f_imm[4:0]; // SRAI
                            end else begin
                                ref_alu = f_rs1 >> f_imm[4:0]; // SRLI
                            end
                        end
                        default: ref_alu = {`XLEN{1'b0}};
                    endcase
                end
                7'b0110011: begin
                    if (f_funct7 == 7'b0000001) begin
                        ref_alu = {`XLEN{1'b0}};
                    end else begin
                        case (f_funct3)
                            3'b000: begin
                                if (f_funct7 == 7'b0100000) begin
                                    ref_alu = f_rs1 - f_rs2; // SUB
                                end else begin
                                    ref_alu = f_rs1 + f_rs2; // ADD
                                end
                            end
                            3'b001: ref_alu = f_rs1 << f_rs2[4:0]; // SLL
                            3'b010: ref_alu = (rs1_s < rs2_s) ? 32'd1 : 32'd0; // SLT
                            3'b011: ref_alu = (f_rs1 < f_rs2) ? 32'd1 : 32'd0; // SLTU
                            3'b100: ref_alu = f_rs1 ^ f_rs2; // XOR
                            3'b101: begin
                                if (f_funct7 == 7'b0100000) begin
                                    ref_alu = rs1_s >>> f_rs2[4:0]; // SRA
                                end else begin
                                    ref_alu = f_rs1 >> f_rs2[4:0]; // SRL
                                end
                            end
                            3'b110: ref_alu = f_rs1 | f_rs2; // OR
                            3'b111: ref_alu = f_rs1 & f_rs2; // AND
                            default: ref_alu = {`XLEN{1'b0}};
                        endcase
                    end
                end
                7'b0000011: ref_alu = f_rs1 + f_imm; // LOAD address
                7'b0100011: ref_alu = f_rs1 + f_imm; // STORE address
                7'b0110111: ref_alu = f_imm; // LUI
                7'b0010111: ref_alu = f_pc + f_imm; // AUIPC
                default: ref_alu = {`XLEN{1'b0}};
            endcase
        end
    endfunction

    function automatic exp_branch;
        input [6:0] f_opcode;
        input [2:0] f_funct3;
        input [`XLEN-1:0] f_rs1;
        input [`XLEN-1:0] f_rs2;
        reg signed [`XLEN-1:0] rs1_s;
        reg signed [`XLEN-1:0] rs2_s;
        begin
            rs1_s = f_rs1;
            rs2_s = f_rs2;
            exp_branch = 1'b0;
            if (f_opcode == 7'b1100011) begin
                case (f_funct3)
                    3'b000: exp_branch = (f_rs1 == f_rs2); // BEQ
                    3'b001: exp_branch = (f_rs1 != f_rs2); // BNE
                    3'b100: exp_branch = (rs1_s < rs2_s); // BLT
                    3'b101: exp_branch = (rs1_s >= rs2_s); // BGE
                    3'b110: exp_branch = (f_rs1 < f_rs2); // BLTU
                    3'b111: exp_branch = (f_rs1 >= f_rs2); // BGEU
                    default: exp_branch = 1'b0;
                endcase
            end
        end
    endfunction

    task automatic check_alu;
        input [6:0] t_opcode;
        input [2:0] t_funct3;
        input [6:0] t_funct7;
        input [`XLEN-1:0] t_rs1;
        input [`XLEN-1:0] t_rs2;
        input [`XLEN-1:0] t_imm;
        input [`XLEN-1:0] t_pc;
        reg [`XLEN-1:0] exp;
        begin
            opcode = t_opcode;
            funct3 = t_funct3;
            funct7 = t_funct7;
            rs1_val = t_rs1;
            rs2_val = t_rs2;
            imm = t_imm;
            pc_in = t_pc;
            #1;
            exp = ref_alu(t_opcode, t_funct3, t_funct7, t_rs1, t_rs2, t_imm, t_pc);
            if (alu_result !== exp) begin
                $display("ALU mismatch op=%b f3=%b f7=%b rs1=%h rs2=%h imm=%h exp=%h got=%h",
                         t_opcode, t_funct3, t_funct7, t_rs1, t_rs2, t_imm, exp, alu_result);
                $finish;
            end
        end
    endtask

    task automatic check_branch;
        input [2:0] t_funct3;
        input [`XLEN-1:0] t_rs1;
        input [`XLEN-1:0] t_rs2;
        input [`XLEN-1:0] t_imm;
        input [`XLEN-1:0] t_pc;
        reg exp;
        begin
            opcode = 7'b1100011;
            funct3 = t_funct3;
            funct7 = 7'b0000000;
            rs1_val = t_rs1;
            rs2_val = t_rs2;
            imm = t_imm;
            pc_in = t_pc;
            #1;
            exp = exp_branch(opcode, funct3, rs1_val, rs2_val);
            if (branch_taken !== exp) begin
                $display("BRANCH mismatch f3=%b rs1=%h rs2=%h exp=%b got=%b",
                         t_funct3, t_rs1, t_rs2, exp, branch_taken);
                $finish;
            end
            if (branch_target !== (t_pc + t_imm)) begin
                $display("BRANCH target mismatch exp=%h got=%h", t_pc + t_imm, branch_target);
                $finish;
            end
        end
    endtask

    initial begin
        opcode = 7'b0;
        funct3 = 3'b0;
        funct7 = 7'b0;
        rs1_val = {`XLEN{1'b0}};
        rs2_val = {`XLEN{1'b0}};
        imm = {`XLEN{1'b0}};
        pc_in = 32'h0000_0100;

        // Directed ALU tests.
        check_alu(7'b0010011, 3'b000, 7'b0000000, 32'd5, 32'd0, 32'd3, pc_in); // ADDI
        check_alu(7'b0010011, 3'b010, 7'b0000000, 32'hFFFF_FFFF, 32'd0, 32'd1, pc_in); // SLTI
        check_alu(7'b0010011, 3'b011, 7'b0000000, 32'd1, 32'd0, 32'd2, pc_in); // SLTIU
        check_alu(7'b0010011, 3'b100, 7'b0000000, 32'hAA55_AA55, 32'd0, 32'h0F0F_0F0F, pc_in); // XORI
        check_alu(7'b0010011, 3'b110, 7'b0000000, 32'h00FF_0000, 32'd0, 32'h0F00_0F00, pc_in); // ORI
        check_alu(7'b0010011, 3'b111, 7'b0000000, 32'hFFFF_0000, 32'd0, 32'h0F0F_0F0F, pc_in); // ANDI
        check_alu(7'b0010011, 3'b001, 7'b0000000, 32'h0000_0001, 32'd0, 32'd4, pc_in); // SLLI
        check_alu(7'b0010011, 3'b101, 7'b0000000, 32'h8000_0000, 32'd0, 32'd4, pc_in); // SRLI
        check_alu(7'b0010011, 3'b101, 7'b0100000, 32'h8000_0000, 32'd0, 32'd4, pc_in); // SRAI

        check_alu(7'b0110011, 3'b000, 7'b0000000, 32'd7, 32'd4, 32'd0, pc_in); // ADD
        check_alu(7'b0110011, 3'b000, 7'b0100000, 32'd7, 32'd4, 32'd0, pc_in); // SUB
        check_alu(7'b0110011, 3'b001, 7'b0000000, 32'd1, 32'd8, 32'd0, pc_in); // SLL
        check_alu(7'b0110011, 3'b010, 7'b0000000, 32'hFFFF_FFFF, 32'd1, 32'd0, pc_in); // SLT
        check_alu(7'b0110011, 3'b011, 7'b0000000, 32'hFFFF_FFFF, 32'd1, 32'd0, pc_in); // SLTU
        check_alu(7'b0110011, 3'b100, 7'b0000000, 32'hAAAA_0000, 32'h0F0F_0F0F, 32'd0, pc_in); // XOR
        check_alu(7'b0110011, 3'b101, 7'b0000000, 32'h8000_0000, 32'd4, 32'd0, pc_in); // SRL
        check_alu(7'b0110011, 3'b101, 7'b0100000, 32'h8000_0000, 32'd4, 32'd0, pc_in); // SRA
        check_alu(7'b0110011, 3'b110, 7'b0000000, 32'h0000_FF00, 32'h00FF_0000, 32'd0, pc_in); // OR
        check_alu(7'b0110011, 3'b111, 7'b0000000, 32'h0000_FF00, 32'h00FF_0000, 32'd0, pc_in); // AND

        // Directed branch tests.
        check_branch(3'b000, 32'd5, 32'd5, 32'd8, pc_in); // BEQ taken
        check_branch(3'b001, 32'd5, 32'd6, 32'd8, pc_in); // BNE taken
        check_branch(3'b100, 32'hFFFF_FFFF, 32'd1, 32'd8, pc_in); // BLT taken
        check_branch(3'b101, 32'd2, 32'd1, 32'd8, pc_in); // BGE taken
        check_branch(3'b110, 32'd1, 32'd2, 32'd8, pc_in); // BLTU taken
        check_branch(3'b111, 32'd2, 32'd1, 32'd8, pc_in); // BGEU taken

        // JAL/JALR target checks.
        opcode = 7'b1101111;
        funct3 = 3'b000;
        funct7 = 7'b0000000;
        rs1_val = 32'd0;
        rs2_val = 32'd0;
        imm = 32'd16;
        pc_in = 32'h0000_0100;
        #1;
        if (!branch_taken || branch_target !== (pc_in + imm)) begin
            $display("JAL mismatch target=%h taken=%b", branch_target, branch_taken);
            $finish;
        end

        opcode = 7'b1100111;
        funct3 = 3'b000;
        funct7 = 7'b0000000;
        rs1_val = 32'h0000_1234;
        rs2_val = 32'd0;
        imm = 32'd4;
        pc_in = 32'h0000_0100;
        #1;
        if (!branch_taken || branch_target !== ((rs1_val + imm) & ~32'b1)) begin
            $display("JALR mismatch target=%h taken=%b", branch_target, branch_taken);
            $finish;
        end

        // Randomized ALU tests.
        begin : rand_alu
            integer i;
            reg [2:0] f3;
            reg [6:0] f7;
            reg [`XLEN-1:0] a;
            reg [`XLEN-1:0] b;
            reg [`XLEN-1:0] im;
            for (i = 0; i < 1000; i = i + 1) begin
                a = $urandom;
                b = $urandom;
                im = $urandom;
                f3 = $urandom % 8;
                f7 = 7'b0000000;
                if (f3 == 3'b101) begin
                    f7 = ($urandom_range(0, 1) == 0) ? 7'b0000000 : 7'b0100000;
                end
                if (f3 == 3'b001) begin
                    f7 = 7'b0000000;
                end
                check_alu(7'b0010011, f3, f7, a, b, im, 32'h0000_0100);
            end
        end

        begin : rand_op
            integer i;
            reg [2:0] f3;
            reg [6:0] f7;
            reg [`XLEN-1:0] a;
            reg [`XLEN-1:0] b;
            for (i = 0; i < 1000; i = i + 1) begin
                a = $urandom;
                b = $urandom;
                f3 = $urandom % 8;
                f7 = 7'b0000000;
                if (f3 == 3'b000 || f3 == 3'b101) begin
                    f7 = ($urandom_range(0, 1) == 0) ? 7'b0000000 : 7'b0100000;
                end
                check_alu(7'b0110011, f3, f7, a, b, 32'd0, 32'h0000_0100);
            end
        end

        $display("ex_stage_tb PASS");
        $finish;
    end
endmodule
