`timescale 1ns/1ps
`include "defines.vh"

module tb_custom0_ex_stage;
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

    integer i;
    integer errors;
    integer tests;
    reg [`XLEN-1:0] gold_sum;
    reg [`XLEN-1:0] dut_sum;
    reg [`XLEN-1:0] rand_a;
    reg [`XLEN-1:0] rand_b;
    reg [4:0] rand_imm5;

    function [8:0] sext8;
        input [7:0] val;
        begin
            sext8 = {val[7], val};
        end
    endfunction

    function [7:0] sat8;
        input [9:0] val;
        integer s;
        begin
            s = $signed(val);
            if (s > 127) begin
                sat8 = 8'h7f;
            end else if (s < -128) begin
                sat8 = 8'h80;
            end else begin
                sat8 = val[7:0];
            end
        end
    endfunction

    function [15:0] sat16;
        input integer val;
        begin
            if (val > 32767) begin
                sat16 = 16'h7fff;
            end else if (val < -32768) begin
                sat16 = 16'h8000;
            end else begin
                sat16 = val[15:0];
            end
        end
    endfunction

    function [7:0] abs8;
        input [7:0] val;
        integer s;
        begin
            s = $signed({val[7], val});
            if (s == -128) begin
                abs8 = 8'h7f;
            end else if (s < 0) begin
                abs8 = -s;
            end else begin
                abs8 = val;
            end
        end
    endfunction

    function [7:0] clamp8;
        input [7:0] val;
        input [4:0] lim;
        integer s;
        integer l;
        begin
            s = $signed({val[7], val});
            l = lim;
            if (s > l) begin
                clamp8 = l;
            end else if (s < -l) begin
                clamp8 = -l;
            end else begin
                clamp8 = s;
            end
        end
    endfunction

    function [7:0] relu8;
        input [7:0] val;
        integer s;
        begin
            s = $signed({val[7], val});
            if (s < 0) begin
                relu8 = 8'h00;
            end else begin
                relu8 = val;
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

    function [`XLEN-1:0] ref_dot4_ss;
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
            ref_dot4_ss = acc;
        end
    endfunction

    function [`XLEN-1:0] ref_dot4_su;
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
            ref_dot4_su = acc;
        end
    endfunction

    function [`XLEN-1:0] ref_dot4_uu;
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
            ref_dot4_uu = acc;
        end
    endfunction

    function [`XLEN-1:0] ref_add8;
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
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            ref_add8 = {a3 + b3, a2 + b2, a1 + b1, a0 + b0};
        end
    endfunction

    function [`XLEN-1:0] ref_sub8;
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
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            ref_sub8 = {a3 - b3, a2 - b2, a1 - b1, a0 - b0};
        end
    endfunction

    function [`XLEN-1:0] ref_addsat8;
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
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            ref_addsat8 = {sat8(sext8(a3) + sext8(b3)),
                           sat8(sext8(a2) + sext8(b2)),
                           sat8(sext8(a1) + sext8(b1)),
                           sat8(sext8(a0) + sext8(b0))};
        end
    endfunction

    function [`XLEN-1:0] ref_subsat8;
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
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            ref_subsat8 = {sat8(sext8(a3) - sext8(b3)),
                           sat8(sext8(a2) - sext8(b2)),
                           sat8(sext8(a1) - sext8(b1)),
                           sat8(sext8(a0) - sext8(b0))};
        end
    endfunction

    function [`XLEN-1:0] ref_max8;
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
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            ref_max8 = {(sext8(a3) >= sext8(b3)) ? a3 : b3,
                        (sext8(a2) >= sext8(b2)) ? a2 : b2,
                        (sext8(a1) >= sext8(b1)) ? a1 : b1,
                        (sext8(a0) >= sext8(b0)) ? a0 : b0};
        end
    endfunction

    function [`XLEN-1:0] ref_min8;
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
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            ref_min8 = {(sext8(a3) <= sext8(b3)) ? a3 : b3,
                        (sext8(a2) <= sext8(b2)) ? a2 : b2,
                        (sext8(a1) <= sext8(b1)) ? a1 : b1,
                        (sext8(a0) <= sext8(b0)) ? a0 : b0};
        end
    endfunction

    function [`XLEN-1:0] ref_abs8;
        input [31:0] a;
        reg [7:0] a0;
        reg [7:0] a1;
        reg [7:0] a2;
        reg [7:0] a3;
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            ref_abs8 = {abs8(a3), abs8(a2), abs8(a1), abs8(a0)};
        end
    endfunction

    function [`XLEN-1:0] ref_avg8;
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
        begin
            a0 = a[7:0];
            a1 = a[15:8];
            a2 = a[23:16];
            a3 = a[31:24];
            b0 = b[7:0];
            b1 = b[15:8];
            b2 = b[23:16];
            b3 = b[31:24];
            ref_avg8 = {({1'b0, a3} + {1'b0, b3} + 9'd1) >> 1,
                        ({1'b0, a2} + {1'b0, b2} + 9'd1) >> 1,
                        ({1'b0, a1} + {1'b0, b1} + 9'd1) >> 1,
                        ({1'b0, a0} + {1'b0, b0} + 9'd1) >> 1};
        end
    endfunction

    function [`XLEN-1:0] ref_add16;
        input [31:0] a;
        input [31:0] b;
        begin
            ref_add16[15:0]  = a[15:0] + b[15:0];
            ref_add16[31:16] = a[31:16] + b[31:16];
        end
    endfunction

    function [`XLEN-1:0] ref_addsat16;
        input [31:0] a;
        input [31:0] b;
        integer s0;
        integer s1;
        begin
            s0 = $signed({a[15], a[15:0]}) + $signed({b[15], b[15:0]});
            s1 = $signed({a[31], a[31:16]}) + $signed({b[31], b[31:16]});
            ref_addsat16[15:0]  = sat16(s0);
            ref_addsat16[31:16] = sat16(s1);
        end
    endfunction

    function [`XLEN-1:0] ref_shl8i;
        input [31:0] a;
        input [2:0] shamt;
        begin
            ref_shl8i = {shl8i_byte(a[31:24], shamt),
                        shl8i_byte(a[23:16], shamt),
                        shl8i_byte(a[15:8], shamt),
                        shl8i_byte(a[7:0], shamt)};
        end
    endfunction

    function [`XLEN-1:0] ref_shr8i;
        input [31:0] a;
        input [2:0] shamt;
        begin
            ref_shr8i = {shr8i_byte(a[31:24], shamt),
                        shr8i_byte(a[23:16], shamt),
                        shr8i_byte(a[15:8], shamt),
                        shr8i_byte(a[7:0], shamt)};
        end
    endfunction

    function [`XLEN-1:0] ref_sru8i;
        input [31:0] a;
        input [2:0] shamt;
        begin
            ref_sru8i = {sru8i_byte(a[31:24], shamt),
                        sru8i_byte(a[23:16], shamt),
                        sru8i_byte(a[15:8], shamt),
                        sru8i_byte(a[7:0], shamt)};
        end
    endfunction

    function [`XLEN-1:0] ref_rshr8i;
        input [31:0] a;
        input [2:0] shamt;
        begin
            ref_rshr8i = {rshr8i_byte(a[31:24], shamt),
                          rshr8i_byte(a[23:16], shamt),
                          rshr8i_byte(a[15:8], shamt),
                          rshr8i_byte(a[7:0], shamt)};
        end
    endfunction

    function [`XLEN-1:0] ref_clamp8i;
        input [31:0] a;
        input [4:0] lim;
        begin
            ref_clamp8i = {clamp8(a[31:24], lim),
                           clamp8(a[23:16], lim),
                           clamp8(a[15:8], lim),
                           clamp8(a[7:0], lim)};
        end
    endfunction

    function [`XLEN-1:0] ref_packb;
        input [31:0] a;
        input [31:0] b;
        begin
            ref_packb = {b[15:8], b[7:0], a[15:8], a[7:0]};
        end
    endfunction

    function [`XLEN-1:0] ref_packh;
        input [31:0] a;
        input [31:0] b;
        begin
            ref_packh = {b[15:0], a[15:0]};
        end
    endfunction

    function [`XLEN-1:0] ref_unpk8l_s;
        input [31:0] a;
        begin
            ref_unpk8l_s[15:0]  = {{8{a[7]}}, a[7:0]};
            ref_unpk8l_s[31:16] = {{8{a[15]}}, a[15:8]};
        end
    endfunction

    function [`XLEN-1:0] ref_unpk8h_s;
        input [31:0] a;
        begin
            ref_unpk8h_s[15:0]  = {{8{a[23]}}, a[23:16]};
            ref_unpk8h_s[31:16] = {{8{a[31]}}, a[31:24]};
        end
    endfunction

    function [`XLEN-1:0] ref_rev8;
        input [31:0] a;
        begin
            ref_rev8 = {a[7:0], a[15:8], a[23:16], a[31:24]};
        end
    endfunction

    function [`XLEN-1:0] ref_swap16;
        input [31:0] a;
        begin
            ref_swap16 = {a[15:0], a[31:16]};
        end
    endfunction

    function [`XLEN-1:0] ref_relu8;
        input [31:0] a;
        begin
            ref_relu8 = {relu8(a[31:24]), relu8(a[23:16]), relu8(a[15:8]), relu8(a[7:0])};
        end
    endfunction

    task check_r;
        input [2:0] f3;
        input [6:0] f7;
        input [31:0] a;
        input [31:0] b;
        input [31:0] exp;
        begin
            opcode = `OPCODE_CUSTOM0;
            funct3 = f3;
            funct7 = f7;
            rs1_val = a;
            rs2_val = b;
            imm = 32'h0;
            pc_in = 32'h0;
            #1;
            tests = tests + 1;
            if (!custom_valid) begin
                errors = errors + 1;
                $display("ERR: custom_valid=0 f3=%0d f7=0x%02x a=0x%08x b=0x%08x",
                         f3, f7, a, b);
            end else if (alu_result !== exp) begin
                errors = errors + 1;
                $display("ERR: f3=%0d f7=0x%02x a=0x%08x b=0x%08x exp=0x%08x got=0x%08x",
                         f3, f7, a, b, exp, alu_result);
            end
            gold_sum = gold_sum ^ exp;
            dut_sum = dut_sum ^ alu_result;
        end
    endtask

    task check_i;
        input [2:0] f3;
        input [6:0] f7;
        input [31:0] a;
        input [4:0] imm5;
        input [31:0] exp;
        begin
            opcode = `OPCODE_CUSTOM0;
            funct3 = f3;
            funct7 = f7;
            rs1_val = a;
            rs2_val = 32'h0;
            imm = {20'b0, f7, imm5};
            pc_in = 32'h0;
            #1;
            tests = tests + 1;
            if (!custom_valid) begin
                errors = errors + 1;
                $display("ERR: custom_valid=0 f3=%0d f7=0x%02x a=0x%08x sh=%0d",
                         f3, f7, a, imm5);
            end else if (alu_result !== exp) begin
                errors = errors + 1;
                $display("ERR: f3=%0d f7=0x%02x a=0x%08x sh=%0d exp=0x%08x got=0x%08x",
                         f3, f7, a, imm5, exp, alu_result);
            end
            gold_sum = gold_sum ^ exp;
            dut_sum = dut_sum ^ alu_result;
        end
    endtask

    initial begin
        errors = 0;
        tests = 0;
        gold_sum = 32'h0;
        dut_sum = 32'h0;

        // Directed tests (edge cases).
        check_r(`CUST3_DOTMAC, `CUST7_DOT4_SS, 32'h01020304, 32'h11121314, ref_dot4_ss(32'h01020304, 32'h11121314));
        check_r(`CUST3_DOTMAC, `CUST7_DOT4_SU, 32'hff80ff7f, 32'h00010203, ref_dot4_su(32'hff80ff7f, 32'h00010203));
        check_r(`CUST3_DOTMAC, `CUST7_DOT4_UU, 32'h80808080, 32'h01010101, ref_dot4_uu(32'h80808080, 32'h01010101));

        check_r(`CUST3_ADDSUB, `CUST7_ADD8, 32'h7f7f7f7f, 32'h01010101, ref_add8(32'h7f7f7f7f, 32'h01010101));
        check_r(`CUST3_ADDSUB, `CUST7_SUB8, 32'h00010203, 32'h01010101, ref_sub8(32'h00010203, 32'h01010101));
        check_r(`CUST3_ADDSUB, `CUST7_ADDSAT8, 32'h7f7f7f7f, 32'h01020304, ref_addsat8(32'h7f7f7f7f, 32'h01020304));
        check_r(`CUST3_ADDSUB, `CUST7_SUBSAT8, 32'h80808080, 32'h01020304, ref_subsat8(32'h80808080, 32'h01020304));

        check_r(`CUST3_MISC, `CUST7_MAX8, 32'h7f80ff00, 32'h01020304, ref_max8(32'h7f80ff00, 32'h01020304));
        check_r(`CUST3_MISC, `CUST7_MIN8, 32'h7f80ff00, 32'h01020304, ref_min8(32'h7f80ff00, 32'h01020304));
        check_r(`CUST3_MISC, `CUST7_ABS8, 32'h8081ff7f, 32'h0, ref_abs8(32'h8081ff7f));
        check_r(`CUST3_MISC, `CUST7_AVG8, 32'h00010203, 32'h01010101, ref_avg8(32'h00010203, 32'h01010101));
        check_r(`CUST3_MISC, `CUST7_ADD16, 32'h7fff8000, 32'h00020003, ref_add16(32'h7fff8000, 32'h00020003));
        check_r(`CUST3_MISC, `CUST7_ADDSAT16, 32'h7fff8000, 32'h00020003,
                ref_addsat16(32'h7fff8000, 32'h00020003));

        check_i(`CUST3_SHIFT, `CUST7_SHL8I, 32'h01020304, 5'd1, ref_shl8i(32'h01020304, 3'd1));
        check_i(`CUST3_SHIFT, `CUST7_SHR8I, 32'h80818283, 5'd1, ref_shr8i(32'h80818283, 3'd1));
        check_i(`CUST3_SHIFT, `CUST7_SRU8I, 32'h80818283, 5'd1, ref_sru8i(32'h80818283, 3'd1));
        check_i(`CUST3_SHIFT, `CUST7_RSHR8I, 32'h7f808182, 5'd2, ref_rshr8i(32'h7f808182, 3'd2));
        check_i(`CUST3_SHIFT, `CUST7_CLAMP8I, 32'h90ff7f10, 5'd5, ref_clamp8i(32'h90ff7f10, 5'd5));

        check_r(`CUST3_PACK, `CUST7_PACKB, 32'h01020304, 32'h11121314, ref_packb(32'h01020304, 32'h11121314));
        check_r(`CUST3_PACK, `CUST7_UNPK8L_S, 32'h8081ff7f, 32'h0, ref_unpk8l_s(32'h8081ff7f));
        check_r(`CUST3_PACK, `CUST7_UNPK8H_S, 32'h8081ff7f, 32'h0, ref_unpk8h_s(32'h8081ff7f));
        check_r(`CUST3_PACK, `CUST7_PACKH, 32'h01020304, 32'h11121314, ref_packh(32'h01020304, 32'h11121314));
        check_r(`CUST3_PERM, `CUST7_REV8, 32'h01020304, 32'h0, ref_rev8(32'h01020304));
        check_r(`CUST3_PERM, `CUST7_SWAP16, 32'h01020304, 32'h0, ref_swap16(32'h01020304));
        check_r(`CUST3_RELU, `CUST7_RELU8, 32'h80ff7f01, 32'h0, ref_relu8(32'h80ff7f01));

        // Randomized regression.
        for (i = 0; i < 200; i = i + 1) begin
            rand_a = $urandom;
            rand_b = $urandom;
            rand_imm5 = $urandom;
            check_r(`CUST3_DOTMAC, `CUST7_DOT4_SS, rand_a, rand_b, ref_dot4_ss(rand_a, rand_b));
            check_r(`CUST3_DOTMAC, `CUST7_DOT4_SU, rand_a, rand_b, ref_dot4_su(rand_a, rand_b));
            check_r(`CUST3_DOTMAC, `CUST7_DOT4_UU, rand_a, rand_b, ref_dot4_uu(rand_a, rand_b));
            check_r(`CUST3_ADDSUB, `CUST7_ADD8, rand_a, rand_b, ref_add8(rand_a, rand_b));
            check_r(`CUST3_ADDSUB, `CUST7_SUB8, rand_a, rand_b, ref_sub8(rand_a, rand_b));
            check_r(`CUST3_ADDSUB, `CUST7_ADDSAT8, rand_a, rand_b, ref_addsat8(rand_a, rand_b));
            check_r(`CUST3_ADDSUB, `CUST7_SUBSAT8, rand_a, rand_b, ref_subsat8(rand_a, rand_b));
            check_r(`CUST3_MISC, `CUST7_MAX8, rand_a, rand_b, ref_max8(rand_a, rand_b));
            check_r(`CUST3_MISC, `CUST7_MIN8, rand_a, rand_b, ref_min8(rand_a, rand_b));
            check_r(`CUST3_MISC, `CUST7_ABS8, rand_a, rand_b, ref_abs8(rand_a));
            check_r(`CUST3_MISC, `CUST7_AVG8, rand_a, rand_b, ref_avg8(rand_a, rand_b));
            check_r(`CUST3_MISC, `CUST7_ADD16, rand_a, rand_b, ref_add16(rand_a, rand_b));
            check_r(`CUST3_MISC, `CUST7_ADDSAT16, rand_a, rand_b, ref_addsat16(rand_a, rand_b));
            check_i(`CUST3_SHIFT, `CUST7_SHL8I, rand_a, rand_imm5, ref_shl8i(rand_a, rand_imm5[2:0]));
            check_i(`CUST3_SHIFT, `CUST7_SHR8I, rand_a, rand_imm5, ref_shr8i(rand_a, rand_imm5[2:0]));
            check_i(`CUST3_SHIFT, `CUST7_SRU8I, rand_a, rand_imm5, ref_sru8i(rand_a, rand_imm5[2:0]));
            check_i(`CUST3_SHIFT, `CUST7_RSHR8I, rand_a, rand_imm5, ref_rshr8i(rand_a, rand_imm5[2:0]));
            check_i(`CUST3_SHIFT, `CUST7_CLAMP8I, rand_a, rand_imm5, ref_clamp8i(rand_a, rand_imm5));
            check_r(`CUST3_PACK, `CUST7_PACKB, rand_a, rand_b, ref_packb(rand_a, rand_b));
            check_r(`CUST3_PACK, `CUST7_UNPK8L_S, rand_a, rand_b, ref_unpk8l_s(rand_a));
            check_r(`CUST3_PACK, `CUST7_UNPK8H_S, rand_a, rand_b, ref_unpk8h_s(rand_a));
            check_r(`CUST3_PACK, `CUST7_PACKH, rand_a, rand_b, ref_packh(rand_a, rand_b));
            check_r(`CUST3_PERM, `CUST7_REV8, rand_a, rand_b, ref_rev8(rand_a));
            check_r(`CUST3_PERM, `CUST7_SWAP16, rand_a, rand_b, ref_swap16(rand_a));
            check_r(`CUST3_RELU, `CUST7_RELU8, rand_a, rand_b, ref_relu8(rand_a));
        end

        $display("custom0 ex_stage tests: %0d total, %0d errors", tests, errors);
        $display("golden checksum=0x%08x dut checksum=0x%08x", gold_sum, dut_sum);
        if (errors != 0) begin
            $fatal(1, "custom0 ex_stage mismatches");
        end
        $display("custom0 ex_stage PASSED");
        $finish;
    end
endmodule
