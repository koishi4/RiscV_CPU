`timescale 1ns/1ps
`include "defines.vh"

module tb_alu_id;
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
    wire custom_valid;

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
        .branch_target(branch_target),
        .custom_valid(custom_valid)
    );

    // 学号按十六进制使用：0x2023216458（40-bit），取低 32 位用于 ALU。
    localparam [39:0] ID_HEX  = 40'h2023_2164_58;
    localparam [`XLEN-1:0] ID_NUM = ID_HEX[31:0];
    localparam [`XLEN-1:0] ID_NEG = (~ID_NUM + 32'd1);
    // 立即数也使用学号的十六进制分组。
    localparam [`XLEN-1:0] IMM_2023 = 32'h0000_2023;
    localparam [`XLEN-1:0] IMM_2164 = 32'h0000_2164;
    localparam [`XLEN-1:0] IMM_6458 = 32'h0000_6458;
    localparam [`XLEN-1:0] IMM_LUI  = 32'h2023_2000;
    localparam [`XLEN-1:0] PC_BASE  = 32'h0001_0000;

`ifdef NO_CHECK
    localparam CHECK_EN = 0;
`else
    localparam CHECK_EN = 1;
`endif

`ifdef DUMP_VCD
    initial begin
        $dumpfile("alu_id_wave.vcd");
        $dumpvars(0, tb_alu_id);
    end
`endif

    function automatic [`XLEN-1:0] sra32;
        input [`XLEN-1:0] val;
        input [4:0] shamt;
        reg [63:0] ext;
        begin
            ext = {{32{val[31]}}, val};
            sra32 = ext >>> shamt;
        end
    endfunction

    task automatic run_case;
        input string name;
        input [6:0] t_opcode;
        input [2:0] t_funct3;
        input [6:0] t_funct7;
        input [`XLEN-1:0] t_rs1;
        input [`XLEN-1:0] t_rs2;
        input [`XLEN-1:0] t_imm;
        input [`XLEN-1:0] t_pc;
        input [`XLEN-1:0] exp;
        begin
            opcode = t_opcode;
            funct3 = t_funct3;
            funct7 = t_funct7;
            rs1_val = t_rs1;
            rs2_val = t_rs2;
            imm = t_imm;
            pc_in = t_pc;
            #1;
            if (alu_result !== exp) begin
                $display("FAIL %s rs1=0x%08x rs2=0x%08x imm=0x%08x pc=0x%08x exp=0x%08x got=0x%08x",
                         name, t_rs1, t_rs2, t_imm, t_pc, exp, alu_result);
                if (CHECK_EN) begin
                    $finish;
                end
            end
            $display("PASS %s rs1=0x%08x rs2=0x%08x imm=0x%08x pc=0x%08x result=0x%08x",
                     name, t_rs1, t_rs2, t_imm, t_pc, alu_result);
        end
    endtask

    initial begin
        opcode = 7'b0;
        funct3 = 3'b0;
        funct7 = 7'b0;
        rs1_val = {`XLEN{1'b0}};
        rs2_val = {`XLEN{1'b0}};
        imm = {`XLEN{1'b0}};
        pc_in = PC_BASE;

        // R-type ALU
        run_case("ADD", 7'b0110011, 3'b000, 7'b0000000,
                 ID_NUM, IMM_2164, 32'd0, PC_BASE, ID_NUM + IMM_2164);
        run_case("SUB", 7'b0110011, 3'b000, 7'b0100000,
                 ID_NUM, IMM_6458, 32'd0, PC_BASE, ID_NUM - IMM_6458);
        run_case("XOR", 7'b0110011, 3'b100, 7'b0000000,
                 ID_NUM, IMM_2023, 32'd0, PC_BASE, ID_NUM ^ IMM_2023);
        run_case("OR", 7'b0110011, 3'b110, 7'b0000000,
                 ID_NUM, IMM_6458, 32'd0, PC_BASE, ID_NUM | IMM_6458);
        run_case("AND", 7'b0110011, 3'b111, 7'b0000000,
                 ID_NUM, IMM_2023, 32'd0, PC_BASE, ID_NUM & IMM_2023);
        run_case("SLL", 7'b0110011, 3'b001, 7'b0000000,
                 ID_NUM, IMM_2164, 32'd0, PC_BASE, ID_NUM << (IMM_2164[4:0]));
        run_case("SRL", 7'b0110011, 3'b101, 7'b0000000,
                 ID_NUM, IMM_6458, 32'd0, PC_BASE, ID_NUM >> (IMM_6458[4:0]));
        run_case("SRA", 7'b0110011, 3'b101, 7'b0100000,
                 ID_NEG, IMM_6458, 32'd0, PC_BASE, sra32(ID_NEG, IMM_6458[4:0]));
        run_case("SLT", 7'b0110011, 3'b010, 7'b0000000,
                 ID_NEG, ID_NUM, 32'd0, PC_BASE, ($signed(ID_NEG) < $signed(ID_NUM)) ? 32'd1 : 32'd0);
        run_case("SLTU", 7'b0110011, 3'b011, 7'b0000000,
                 ID_NEG, ID_NUM, 32'd0, PC_BASE, (ID_NEG < ID_NUM) ? 32'd1 : 32'd0);

        // I-type ALU
        run_case("ADDI", 7'b0010011, 3'b000, 7'b0000000,
                 ID_NUM, 32'd0, IMM_2023, PC_BASE, ID_NUM + IMM_2023);
        run_case("SLTI", 7'b0010011, 3'b010, 7'b0000000,
                 ID_NEG, 32'd0, IMM_2023, PC_BASE, ($signed(ID_NEG) < $signed(IMM_2023)) ? 32'd1 : 32'd0);
        run_case("SLTIU", 7'b0010011, 3'b011, 7'b0000000,
                 ID_NEG, 32'd0, IMM_2023, PC_BASE, (ID_NEG < IMM_2023) ? 32'd1 : 32'd0);
        run_case("XORI", 7'b0010011, 3'b100, 7'b0000000,
                 ID_NUM, 32'd0, IMM_2023, PC_BASE, ID_NUM ^ IMM_2023);
        run_case("ORI", 7'b0010011, 3'b110, 7'b0000000,
                 ID_NUM, 32'd0, IMM_6458, PC_BASE, ID_NUM | IMM_6458);
        run_case("ANDI", 7'b0010011, 3'b111, 7'b0000000,
                 ID_NUM, 32'd0, IMM_2023, PC_BASE, ID_NUM & IMM_2023);
        run_case("SLLI", 7'b0010011, 3'b001, 7'b0000000,
                 ID_NUM, 32'd0, 32'd6, PC_BASE, ID_NUM << 5'd6);
        run_case("SRLI", 7'b0010011, 3'b101, 7'b0000000,
                 ID_NUM, 32'd0, 32'd3, PC_BASE, ID_NUM >> 5'd3);
        run_case("SRAI", 7'b0010011, 3'b101, 7'b0100000,
                 ID_NEG, 32'd0, 32'd4, PC_BASE, sra32(ID_NEG, 5'd4));

        // U-type
        run_case("LUI", 7'b0110111, 3'b000, 7'b0000000,
                 32'd0, 32'd0, IMM_LUI, PC_BASE, IMM_LUI);
        run_case("AUIPC", 7'b0010111, 3'b000, 7'b0000000,
                 32'd0, 32'd0, IMM_LUI, PC_BASE, PC_BASE + IMM_LUI);

        $display("tb_alu_id PASS");
        $finish;
    end
endmodule
