`timescale 1ns/1ps
`include "defines.vh"

module tb_custom0_cpu;
    reg clk;
    reg rst_n;

    wire cpu_mem_req;
    wire cpu_mem_we;
    wire [`ADDR_W-1:0] cpu_mem_addr;
    wire [`XLEN-1:0] cpu_mem_wdata;
    wire [`XLEN-1:0] cpu_mem_rdata;
    wire cpu_mem_ready;

    wire muldiv_start;
    wire [2:0] muldiv_op;
    wire [`XLEN-1:0] muldiv_a;
    wire [`XLEN-1:0] muldiv_b;
    wire [`HART_ID_W-1:0] muldiv_hart_id;
    wire [`REG_ADDR_W-1:0] muldiv_rd;
    wire muldiv_busy;
    wire muldiv_done;
    wire [`XLEN-1:0] muldiv_result;
    wire [`HART_ID_W-1:0] muldiv_done_hart_id;
    wire [`REG_ADDR_W-1:0] muldiv_done_rd;

    reg [`XLEN-1:0] mem[0:1023];

    cpu_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_mem_req(cpu_mem_req),
        .cpu_mem_we(cpu_mem_we),
        .cpu_mem_addr(cpu_mem_addr),
        .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mem_rdata),
        .cpu_mem_ready(cpu_mem_ready),
        .muldiv_start(muldiv_start),
        .muldiv_op(muldiv_op),
        .muldiv_a(muldiv_a),
        .muldiv_b(muldiv_b),
        .muldiv_hart_id(muldiv_hart_id),
        .muldiv_rd(muldiv_rd),
        .muldiv_busy(muldiv_busy),
        .muldiv_done(muldiv_done),
        .muldiv_result(muldiv_result),
        .muldiv_done_hart_id(muldiv_done_hart_id),
        .muldiv_done_rd(muldiv_done_rd),
        .ext_irq(1'b0)
    );

    muldiv_unit u_muldiv (
        .clk(clk),
        .rst_n(rst_n),
        .muldiv_start(muldiv_start),
        .muldiv_op(muldiv_op),
        .muldiv_a(muldiv_a),
        .muldiv_b(muldiv_b),
        .muldiv_hart_id(muldiv_hart_id),
        .muldiv_rd(muldiv_rd),
        .muldiv_busy(muldiv_busy),
        .muldiv_done(muldiv_done),
        .muldiv_result(muldiv_result),
        .muldiv_done_hart_id(muldiv_done_hart_id),
        .muldiv_done_rd(muldiv_done_rd)
    );

    reg mem_req_d;
    reg [`ADDR_W-1:0] mem_addr_d;
    reg [`XLEN-1:0] mem_rdata_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_req_d <= 1'b0;
            mem_addr_d <= {`ADDR_W{1'b0}};
            mem_rdata_d <= {`XLEN{1'b0}};
        end else begin
            mem_req_d <= cpu_mem_req;
            mem_addr_d <= cpu_mem_addr;
            mem_rdata_d <= mem[cpu_mem_addr[11:2]];
            if (cpu_mem_req && cpu_mem_we) begin
                mem[cpu_mem_addr[11:2]] <= cpu_mem_wdata;
            end
        end
    end

    assign cpu_mem_ready = mem_req_d;
    assign cpu_mem_rdata = mem_rdata_d;

    function automatic [31:0] enc_lui;
        input [4:0] rd;
        input [19:0] imm20;
        begin
            enc_lui = {imm20, rd, 7'b0110111};
        end
    endfunction

    function automatic [31:0] enc_addi;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] imm12;
        begin
            enc_addi = {imm12, rs1, 3'b000, rd, 7'b0010011};
        end
    endfunction

    function automatic [31:0] enc_sw;
        input [4:0] rs2;
        input [4:0] rs1;
        input [11:0] imm12;
        begin
            enc_sw = {imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011};
        end
    endfunction

    function automatic [31:0] enc_custom_r;
        input [6:0] f7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        begin
            enc_custom_r = {f7, rs2, rs1, f3, rd, `OPCODE_CUSTOM0};
        end
    endfunction

    function automatic [31:0] enc_custom_i;
        input [6:0] f7;
        input [4:0] imm5;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        begin
            enc_custom_i = {f7, imm5, rs1, f3, rd, `OPCODE_CUSTOM0};
        end
    endfunction

    localparam [31:0] NOP = 32'h00000013;
    localparam [31:0] OUT_BASE = 32'h00000400;
    localparam integer OUT_IDX = OUT_BASE >> 2;

    integer i;
    reg [31:0] exp0;
    reg [31:0] exp1;
    reg [31:0] exp2;
    reg [31:0] exp3;
    reg [31:0] exp4;
    reg [31:0] exp5;
    reg [31:0] exp6;
    reg [31:0] exp7;
    reg [31:0] exp8;
    reg [31:0] exp9;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        for (i = 0; i < 1024; i = i + 1) begin
            mem[i] = NOP;
        end

        // hart dispatch: mhartid -> hart1 jumps to 0x100, hart0 falls through.
        mem[0] = 32'hf14020f3; // csrrs x1, mhartid, x0
        mem[1] = NOP;
        mem[2] = NOP;
        mem[3] = NOP;
        mem[4] = 32'h0e009863; // bne x1, x0, +0x0f0 (to 0x100)
        mem[5] = NOP;
        mem[6] = NOP;
        mem[7] = NOP;

        // hart0 program @ 0x0000_0020
        mem[8]  = enc_lui(5'd1, 20'h01020); // x1 = 0x01020000
        mem[9]  = enc_addi(5'd1, 5'd1, 12'h304); // x1 = 0x01020304
        mem[10] = enc_lui(5'd2, 20'h11121); // x2 = 0x11121000
        mem[11] = enc_addi(5'd2, 5'd2, 12'h314); // x2 = 0x11121314
        mem[12] = enc_addi(5'd10, 5'd0, 12'h400); // x10 = OUT_BASE

        mem[13] = enc_custom_r(`CUST7_REV8, 5'd0, 5'd1, `CUST3_PERM, 5'd3); // x3 = rev8(x1)
        mem[14] = NOP;
        mem[15] = enc_sw(5'd3, 5'd10, 12'h000); // store x3

        mem[16] = enc_custom_r(`CUST7_PACKB, 5'd2, 5'd1, `CUST3_PACK, 5'd4); // x4 = packb(x1,x2)
        mem[17] = NOP;
        mem[18] = enc_sw(5'd4, 5'd10, 12'h004); // store x4

        mem[19] = enc_custom_r(`CUST7_UNPK8L_S, 5'd0, 5'd1, `CUST3_PACK, 5'd5); // x5 = unpk8l
        mem[20] = NOP;
        mem[21] = enc_sw(5'd5, 5'd10, 12'h008); // store x5

        mem[22] = enc_custom_r(`CUST7_ADD8, 5'd2, 5'd1, `CUST3_ADDSUB, 5'd6); // x6 = add8
        mem[23] = NOP;
        mem[24] = enc_sw(5'd6, 5'd10, 12'h00c); // store x6

        mem[25] = enc_custom_r(`CUST7_DOT4_SS, 5'd2, 5'd1, `CUST3_DOTMAC, 5'd7); // x7 = dot4.ss
        mem[26] = NOP;
        mem[27] = enc_sw(5'd7, 5'd10, 12'h010); // store x7

        mem[28] = enc_lui(5'd8, 20'h7fff8); // x8 = 0x7fff8000
        mem[29] = enc_lui(5'd9, 20'h00020); // x9 = 0x00020000
        mem[30] = enc_addi(5'd9, 5'd9, 12'h003); // x9 = 0x00020003

        mem[31] = enc_custom_r(`CUST7_ADDSAT16, 5'd9, 5'd8, `CUST3_MISC, 5'd12); // x12 = addsat16
        mem[32] = NOP;
        mem[33] = enc_sw(5'd12, 5'd10, 12'h014); // store x12

        mem[34] = enc_custom_r(`CUST7_PACKH, 5'd9, 5'd8, `CUST3_PACK, 5'd13); // x13 = packh
        mem[35] = NOP;
        mem[36] = enc_sw(5'd13, 5'd10, 12'h018); // store x13

        mem[37] = enc_custom_r(`CUST7_SWAP16, 5'd0, 5'd1, `CUST3_PERM, 5'd14); // x14 = swap16
        mem[38] = NOP;
        mem[39] = enc_sw(5'd14, 5'd10, 12'h01c); // store x14

        mem[40] = enc_custom_i(`CUST7_CLAMP8I, 5'd5, 5'd8, `CUST3_SHIFT, 5'd15); // x15 = clamp8i
        mem[41] = NOP;
        mem[42] = enc_sw(5'd15, 5'd10, 12'h020); // store x15

        mem[43] = enc_custom_r(`CUST7_RELU8, 5'd0, 5'd8, `CUST3_RELU, 5'd16); // x16 = relu8
        mem[44] = NOP;
        mem[45] = enc_sw(5'd16, 5'd10, 12'h024); // store x16

        mem[46] = 32'h00000063; // beq x0, x0, 0 (halt)

        // hart1 program @ 0x0000_0100
        mem[64] = 32'h00000063; // beq x0, x0, 0

        // Expected results.
        exp0 = 32'h04030201;
        exp1 = 32'h13140304;
        exp2 = 32'h00030004;
        exp3 = 32'h12141618;
        exp4 = 32'h000000be;
        exp5 = 32'h7fff8003;
        exp6 = 32'h00038000;
        exp7 = 32'h03040102;
        exp8 = 32'h05fffb00;
        exp9 = 32'h7f000000;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (900) @(posedge clk);

        $display("custom0 cpu: mem[0]=0x%08x mem[1]=0x%08x mem[2]=0x%08x mem[3]=0x%08x mem[4]=0x%08x",
                 mem[OUT_IDX + 0], mem[OUT_IDX + 1], mem[OUT_IDX + 2],
                 mem[OUT_IDX + 3], mem[OUT_IDX + 4]);
        $display("custom0 cpu: mem[5]=0x%08x mem[6]=0x%08x mem[7]=0x%08x mem[8]=0x%08x mem[9]=0x%08x",
                 mem[OUT_IDX + 5], mem[OUT_IDX + 6], mem[OUT_IDX + 7],
                 mem[OUT_IDX + 8], mem[OUT_IDX + 9]);

        if (mem[OUT_IDX + 0] !== exp0) $fatal(1, "rev8 mismatch exp=%08x got=%08x", exp0, mem[OUT_IDX + 0]);
        if (mem[OUT_IDX + 1] !== exp1) $fatal(1, "packb mismatch exp=%08x got=%08x", exp1, mem[OUT_IDX + 1]);
        if (mem[OUT_IDX + 2] !== exp2) $fatal(1, "unpk8l mismatch exp=%08x got=%08x", exp2, mem[OUT_IDX + 2]);
        if (mem[OUT_IDX + 3] !== exp3) $fatal(1, "add8 mismatch exp=%08x got=%08x", exp3, mem[OUT_IDX + 3]);
        if (mem[OUT_IDX + 4] !== exp4) $fatal(1, "dot4 mismatch exp=%08x got=%08x", exp4, mem[OUT_IDX + 4]);
        if (mem[OUT_IDX + 5] !== exp5) $fatal(1, "addsat16 mismatch exp=%08x got=%08x", exp5, mem[OUT_IDX + 5]);
        if (mem[OUT_IDX + 6] !== exp6) $fatal(1, "packh mismatch exp=%08x got=%08x", exp6, mem[OUT_IDX + 6]);
        if (mem[OUT_IDX + 7] !== exp7) $fatal(1, "swap16 mismatch exp=%08x got=%08x", exp7, mem[OUT_IDX + 7]);
        if (mem[OUT_IDX + 8] !== exp8) $fatal(1, "clamp8i mismatch exp=%08x got=%08x", exp8, mem[OUT_IDX + 8]);
        if (mem[OUT_IDX + 9] !== exp9) $fatal(1, "relu8 mismatch exp=%08x got=%08x", exp9, mem[OUT_IDX + 9]);

        $display("custom0 cpu directed test PASSED");
        $finish;
    end
endmodule
