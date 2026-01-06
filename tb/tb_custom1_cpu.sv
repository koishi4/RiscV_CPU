`timescale 1ns/1ps
`include "defines.vh"

module tb_custom1_cpu;
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

    function [31:0] enc_lui;
        input [4:0] rd;
        input [19:0] imm20;
        begin
            enc_lui = {imm20, rd, 7'b0110111};
        end
    endfunction

    function [31:0] enc_addi;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] imm12;
        begin
            enc_addi = {imm12, rs1, 3'b000, rd, 7'b0010011};
        end
    endfunction

    function [31:0] enc_sw;
        input [4:0] rs2;
        input [4:0] rs1;
        input [11:0] imm12;
        begin
            enc_sw = {imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] enc_custom1_r;
        input [6:0] f7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        begin
            enc_custom1_r = {f7, rs2, rs1, f3, rd, `OPCODE_CUSTOM1};
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
        mem[8]  = enc_lui(5'd1, 20'h00010); // x1 = 0x00010000
        mem[9]  = enc_addi(5'd1, 5'd1, 12'h234); // x1 = 0x00010234
        mem[10] = enc_addi(5'd2, 5'd0, 12'h001); // x2 = flags
        mem[11] = enc_addi(5'd10, 5'd0, 12'h400); // x10 = OUT_BASE

        mem[12] = enc_custom1_r(7'b0, 5'd2, 5'd1, `CUST1_START, 5'd3); // x3 = job_id
        mem[13] = NOP;
        mem[14] = enc_sw(5'd3, 5'd10, 12'h000);

        mem[15] = enc_custom1_r(7'b0, 5'd0, 5'd3, `CUST1_POLL, 5'd4); // x4 = status
        mem[16] = NOP;
        mem[17] = enc_sw(5'd4, 5'd10, 12'h004);

        mem[18] = enc_custom1_r(7'b0, 5'd0, 5'd3, `CUST1_WAIT, 5'd5); // x5 = status
        mem[19] = NOP;
        mem[20] = enc_sw(5'd5, 5'd10, 12'h008);

        mem[21] = enc_custom1_r(7'b0, 5'd0, 5'd3, `CUST1_GETERR, 5'd6); // x6 = err
        mem[22] = NOP;
        mem[23] = enc_sw(5'd6, 5'd10, 12'h00c);

        mem[24] = enc_addi(5'd7, 5'd0, 12'h001); // cfg_id = 1
        mem[25] = enc_lui(5'd8, 20'h00012); // x8 = 0x00012000
        mem[26] = enc_addi(5'd8, 5'd8, 12'h034); // x8 = 0x00012034
        mem[27] = enc_custom1_r(7'b0, 5'd8, 5'd7, `CUST1_SETCFG, 5'd9); // x9 = ret
        mem[28] = NOP;
        mem[29] = enc_sw(5'd9, 5'd10, 12'h010);

        mem[30] = enc_custom1_r(7'b0, 5'd0, 5'd7, `CUST1_GETCFG, 5'd11); // x11 = cfg
        mem[31] = NOP;
        mem[32] = enc_sw(5'd11, 5'd10, 12'h014);

        mem[33] = enc_custom1_r(7'b0, 5'd0, 5'd0, `CUST1_FENCE, 5'd12); // x12 = ret
        mem[34] = NOP;
        mem[35] = enc_sw(5'd12, 5'd10, 12'h018);

        mem[36] = 32'h00000063; // beq x0, x0, 0 (halt)

        // hart1 program @ 0x0000_0100
        mem[64] = 32'h00000063; // beq x0, x0, 0

        exp0 = 32'h00000001;
        exp1 = 32'h00000001;
        exp2 = 32'h00000002;
        exp3 = 32'h00000000;
        exp4 = 32'h00000000;
        exp5 = 32'h00012034;
        exp6 = 32'h00000000;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (1200) @(posedge clk);

        $display("custom1 cpu: mem[0]=0x%08x mem[1]=0x%08x mem[2]=0x%08x mem[3]=0x%08x",
                 mem[OUT_IDX + 0], mem[OUT_IDX + 1], mem[OUT_IDX + 2], mem[OUT_IDX + 3]);
        $display("custom1 cpu: mem[4]=0x%08x mem[5]=0x%08x mem[6]=0x%08x",
                 mem[OUT_IDX + 4], mem[OUT_IDX + 5], mem[OUT_IDX + 6]);

        if (mem[OUT_IDX + 0] !== exp0) $fatal(1, "start job_id mismatch exp=%08x got=%08x", exp0, mem[OUT_IDX + 0]);
        if (mem[OUT_IDX + 1] !== exp1) $fatal(1, "poll status mismatch exp=%08x got=%08x", exp1, mem[OUT_IDX + 1]);
        if (mem[OUT_IDX + 2] !== exp2) $fatal(1, "wait status mismatch exp=%08x got=%08x", exp2, mem[OUT_IDX + 2]);
        if (mem[OUT_IDX + 3] !== exp3) $fatal(1, "geterr mismatch exp=%08x got=%08x", exp3, mem[OUT_IDX + 3]);
        if (mem[OUT_IDX + 4] !== exp4) $fatal(1, "setcfg mismatch exp=%08x got=%08x", exp4, mem[OUT_IDX + 4]);
        if (mem[OUT_IDX + 5] !== exp5) $fatal(1, "getcfg mismatch exp=%08x got=%08x", exp5, mem[OUT_IDX + 5]);
        if (mem[OUT_IDX + 6] !== exp6) $fatal(1, "fence mismatch exp=%08x got=%08x", exp6, mem[OUT_IDX + 6]);

        $display("custom1 cpu directed test PASSED");
        $finish;
    end
endmodule
