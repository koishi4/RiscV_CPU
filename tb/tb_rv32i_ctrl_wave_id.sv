`timescale 1ns/1ps
`include "defines.vh"

module tb_rv32i_ctrl_wave_id;
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

    localparam integer MEM_DEPTH = 2048;
    localparam [`XLEN-1:0] NOP = 32'h00000013;
    localparam [`ADDR_W-1:0] RES_ADDR  = 32'h0000_0400;
    localparam [`ADDR_W-1:0] DATA_ADDR = 32'h0000_0800;
    localparam [`ADDR_W-1:0] DATA_ADDR2 = 32'h0000_0804;
    localparam integer RES_IDX  = RES_ADDR >> 2;
    localparam integer DATA_IDX = DATA_ADDR >> 2;
    localparam integer DATA2_IDX = DATA_ADDR2 >> 2;

    // 学号按十六进制使用：0x2023216458（40-bit），取低 32 位用于 ALU。
    localparam [39:0] ID_HEX  = 40'h2023_2164_58;
    localparam [`XLEN-1:0] ID_NUM = ID_HEX[31:0];     // 0x23216458
    localparam [`XLEN-1:0] ID_LO12 = {20'b0, ID_NUM[11:0]}; // 0x00000458
    localparam [`XLEN-1:0] ID_LO8  = {24'b0, ID_NUM[7:0]};  // 0x00000058

`ifdef NO_CHECK
    localparam CHECK_EN = 0;
`else
    localparam CHECK_EN = 1;
`endif

    reg [`XLEN-1:0] mem[0:MEM_DEPTH-1];

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

    assign cpu_mem_ready = 1'b1;
    assign cpu_mem_rdata = mem[cpu_mem_addr[12:2]];

    always @(posedge clk) begin
        if (cpu_mem_req && cpu_mem_we) begin
            mem[cpu_mem_addr[12:2]] <= cpu_mem_wdata;
        end
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

`ifdef DUMP_VCD
    initial begin
        $dumpfile("rv32i_ctrl_id_wave.vcd");
        $dumpvars(0, tb_rv32i_ctrl_wave_id);
    end
`endif

    function automatic [31:0] enc_r;
        input [6:0] f7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        input [6:0] opc;
        begin
            enc_r = {f7, rs2, rs1, f3, rd, opc};
        end
    endfunction

    function automatic [31:0] enc_i;
        input integer imm;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        input [6:0] opc;
        reg [11:0] imm12;
        begin
            imm12 = imm[11:0];
            enc_i = {imm12, rs1, f3, rd, opc};
        end
    endfunction

    function automatic [31:0] enc_s;
        input integer imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [6:0] opc;
        reg [11:0] imm12;
        begin
            imm12 = imm[11:0];
            enc_s = {imm12[11:5], rs2, rs1, f3, imm12[4:0], opc};
        end
    endfunction

    function automatic [31:0] enc_b;
        input integer imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [6:0] opc;
        reg [12:0] imm13;
        begin
            imm13 = imm[12:0];
            enc_b = {imm13[12], imm13[10:5], rs2, rs1, f3, imm13[4:1], imm13[11], opc};
        end
    endfunction

    function automatic [31:0] enc_u;
        input [19:0] imm20;
        input [4:0] rd;
        input [6:0] opc;
        begin
            enc_u = {imm20, rd, opc};
        end
    endfunction

    function automatic [31:0] enc_j;
        input integer imm;
        input [4:0] rd;
        input [6:0] opc;
        reg [20:0] imm21;
        begin
            imm21 = imm[20:0];
            enc_j = {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd, opc};
        end
    endfunction

    task automatic clear_mem;
        integer i;
        begin
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                mem[i] = NOP;
            end
        end
    endtask

    task automatic init_hart1_idle;
        begin
            mem[128] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011); // beq x0,x0,0
        end
    endtask

    task automatic wait_store;
        integer timeout;
        begin
            timeout = 500;
            while (timeout > 0) begin
                @(posedge clk);
                if (cpu_mem_req && cpu_mem_we && (cpu_mem_addr == RES_ADDR)) begin
                    @(posedge clk);
                    return;
                end
                timeout = timeout - 1;
            end
            $display("FAIL store timeout");
            $finish;
        end
    endtask

    task automatic run_and_check;
        input string name;
        input [`XLEN-1:0] exp;
        input [`XLEN-1:0] in_rs1;
        input [`XLEN-1:0] in_rs2;
        input [`XLEN-1:0] in_imm;
        begin
            mem[RES_IDX] = 32'h0000_0000;
            rst_n = 1'b0;
            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            @(negedge clk);
            dut.pc[1] = 32'h0000_0200;
            wait_store();

            $display("TEST %s rs1=0x%08x rs2=0x%08x imm=0x%08x result=0x%08x",
                     name, in_rs1, in_rs2, in_imm, mem[RES_IDX]);
            if (mem[RES_IDX] !== exp) begin
                $display("FAIL %s exp=0x%08x got=0x%08x", name, exp, mem[RES_IDX]);
                if (CHECK_EN) begin
                    $finish;
                end
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        clear_mem();
        init_hart1_idle();

        // BEQ: rs1==rs2 -> taken
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_u(ID_NUM[31:12], 5'd1, 7'b0110111);            // lui x1, ID_NUM[31:12]
        mem[1] = enc_i(ID_NUM[11:0], 5'd1, 3'b000, 5'd1, 7'b0010011); // addi x1, x1, lo12
        mem[2] = enc_i(0, 5'd1, 3'b000, 5'd2, 7'b0010011);          // addi x2, x1, 0
        mem[3] = enc_b(8, 5'd2, 5'd1, 3'b000, 7'b1100011);          // beq x1,x2,+8
        mem[4] = enc_i(ID_LO12[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011); // addi x3, x0, fail
        mem[5] = enc_i(12'h164, 5'd0, 3'b000, 5'd3, 7'b0010011);    // addi x3, x0, pass
        mem[6] = NOP;
        mem[7] = enc_s(RES_ADDR, 5'd3, 5'd0, 3'b010, 7'b0100011);   // sw x3, RES(x0)
        mem[8] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);          // beq x0,x0,0
        run_and_check("BEQ", 32'h0000_0164, ID_NUM, ID_NUM, 32'h0000_0008);

        // BNE: rs1!=rs2 -> taken
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_u(ID_NUM[31:12], 5'd1, 7'b0110111);
        mem[1] = enc_i(ID_NUM[11:0], 5'd1, 3'b000, 5'd1, 7'b0010011);
        mem[2] = enc_i(1, 5'd1, 3'b000, 5'd2, 7'b0010011);          // x2 = x1 + 1
        mem[3] = enc_b(8, 5'd2, 5'd1, 3'b001, 7'b1100011);          // bne x1,x2,+8
        mem[4] = enc_i(ID_LO12[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[5] = enc_i(12'h164, 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[6] = NOP;
        mem[7] = enc_s(RES_ADDR, 5'd3, 5'd0, 3'b010, 7'b0100011);
        mem[8] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("BNE", 32'h0000_0164, ID_NUM, ID_NUM + 32'd1, 32'h0000_0008);

        // BLT: signed compare (neg < pos) -> taken
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_u(ID_NUM[31:12], 5'd1, 7'b0110111);
        mem[1] = enc_i(ID_NUM[11:0], 5'd1, 3'b000, 5'd1, 7'b0010011);
        mem[2] = enc_r(7'b0100000, 5'd1, 5'd0, 3'b000, 5'd1, 7'b0110011); // sub x1, x0, x1
        mem[3] = enc_u(ID_NUM[31:12], 5'd2, 7'b0110111);
        mem[4] = enc_i(ID_NUM[11:0], 5'd2, 3'b000, 5'd2, 7'b0010011);
        mem[5] = enc_b(8, 5'd2, 5'd1, 3'b100, 7'b1100011);          // blt x1,x2,+8
        mem[6] = enc_i(ID_LO12[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[7] = enc_i(12'h164, 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[8] = NOP;
        mem[9] = enc_s(RES_ADDR, 5'd3, 5'd0, 3'b010, 7'b0100011);
        mem[10] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("BLT", 32'h0000_0164, 32'h8000_0000, ID_NUM, 32'h0000_0008);

        // BGE: signed compare (pos >= neg) -> taken
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_u(ID_NUM[31:12], 5'd1, 7'b0110111);
        mem[1] = enc_i(ID_NUM[11:0], 5'd1, 3'b000, 5'd1, 7'b0010011);
        mem[2] = enc_r(7'b0100000, 5'd1, 5'd0, 3'b000, 5'd2, 7'b0110011); // sub x2, x0, x1
        mem[3] = enc_b(8, 5'd2, 5'd1, 3'b101, 7'b1100011);          // bge x1,x2,+8
        mem[4] = enc_i(ID_LO12[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[5] = enc_i(12'h164, 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[6] = NOP;
        mem[7] = enc_s(RES_ADDR, 5'd3, 5'd0, 3'b010, 7'b0100011);
        mem[8] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("BGE", 32'h0000_0164, ID_NUM, 32'h8000_0000, 32'h0000_0008);

        // BLTU: unsigned compare (0x58 < ID_NUM) -> taken
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_i(ID_LO8[11:0], 5'd0, 3'b000, 5'd1, 7'b0010011); // addi x1, x0, 0x58
        mem[1] = enc_u(ID_NUM[31:12], 5'd2, 7'b0110111);
        mem[2] = enc_i(ID_NUM[11:0], 5'd2, 3'b000, 5'd2, 7'b0010011);
        mem[3] = enc_b(8, 5'd2, 5'd1, 3'b110, 7'b1100011);          // bltu x1,x2,+8
        mem[4] = enc_i(ID_LO12[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[5] = enc_i(12'h164, 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[6] = NOP;
        mem[7] = enc_s(RES_ADDR, 5'd3, 5'd0, 3'b010, 7'b0100011);
        mem[8] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("BLTU", 32'h0000_0164, ID_LO8, ID_NUM, 32'h0000_0008);

        // BGEU: unsigned compare (ID_NUM >= 0x58) -> taken
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_u(ID_NUM[31:12], 5'd1, 7'b0110111);
        mem[1] = enc_i(ID_NUM[11:0], 5'd1, 3'b000, 5'd1, 7'b0010011);
        mem[2] = enc_i(ID_LO8[11:0], 5'd0, 3'b000, 5'd2, 7'b0010011);
        mem[3] = enc_b(8, 5'd2, 5'd1, 3'b111, 7'b1100011);          // bgeu x1,x2,+8
        mem[4] = enc_i(ID_LO12[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[5] = enc_i(12'h164, 5'd0, 3'b000, 5'd3, 7'b0010011);
        mem[6] = NOP;
        mem[7] = enc_s(RES_ADDR, 5'd3, 5'd0, 3'b010, 7'b0100011);
        mem[8] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("BGEU", 32'h0000_0164, ID_NUM, ID_LO8, 32'h0000_0008);

        // JAL: check control flow + link
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_u(ID_NUM[31:12], 5'd1, 7'b0110111);
        mem[1] = enc_i(ID_NUM[11:0], 5'd1, 3'b000, 5'd1, 7'b0010011);
        mem[2] = enc_j(8, 5'd5, 7'b1101111);                        // jal x5, +8
        mem[3] = enc_i(ID_LO12[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011); // skipped
        mem[4] = enc_r(7'b0000000, 5'd1, 5'd5, 3'b000, 5'd5, 7'b0110011); // add x5, x5, x1
        mem[5] = NOP;
        mem[6] = enc_s(RES_ADDR, 5'd5, 5'd0, 3'b010, 7'b0100011);
        mem[7] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("JAL", ID_NUM + 32'd12, ID_NUM, 32'd0, 32'h0000_0008);

        // JALR: check control flow + link
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_u(ID_NUM[31:12], 5'd1, 7'b0110111);
        mem[1] = enc_i(ID_NUM[11:0], 5'd1, 3'b000, 5'd1, 7'b0010011);
        mem[2] = enc_i(20, 5'd0, 3'b000, 5'd2, 7'b0010011);         // x2 = 0x14 (label)
        mem[3] = enc_i(0, 5'd2, 3'b000, 5'd5, 7'b1100111);          // jalr x5, 0(x2)
        mem[4] = enc_i(ID_LO12[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011); // skipped
        mem[5] = enc_r(7'b0000000, 5'd1, 5'd5, 3'b000, 5'd5, 7'b0110011); // add x5, x5, x1
        mem[6] = NOP;
        mem[7] = enc_s(RES_ADDR, 5'd5, 5'd0, 3'b010, 7'b0100011);
        mem[8] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("JALR", ID_NUM + 32'd16, ID_NUM, 32'd0, 32'h0000_0014);

        // LW: load from DATA_ADDR (0x0800) via LUI+ADDI
        clear_mem();
        init_hart1_idle();
        mem[DATA_IDX] = ID_NUM;
        mem[0] = enc_u(20'h00001, 5'd1, 7'b0110111);                // lui x1, 0x1 -> 0x1000
        mem[1] = enc_i(12'h800, 5'd1, 3'b000, 5'd1, 7'b0010011);    // addi x1, x1, -0x800 -> 0x0800
        mem[2] = enc_i(0, 5'd1, 3'b010, 5'd2, 7'b0000011);          // lw x2, 0(x1)
        mem[3] = NOP;
        mem[4] = enc_s(RES_ADDR, 5'd2, 5'd0, 3'b010, 7'b0100011);   // sw x2, RES
        mem[5] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("LW", ID_NUM, DATA_ADDR, 32'd0, 32'h0000_0000);

        // SW: store to DATA_ADDR2 (0x0804) via LUI+ADDI
        clear_mem();
        init_hart1_idle();
        mem[0] = enc_u(20'h00001, 5'd1, 7'b0110111);                // lui x1, 0x1 -> 0x1000
        mem[1] = enc_i(12'h804, 5'd1, 3'b000, 5'd1, 7'b0010011);    // addi x1, x1, -0x7FC -> 0x0804
        mem[2] = enc_u(ID_NUM[31:12], 5'd2, 7'b0110111);
        mem[3] = enc_i(ID_NUM[11:0], 5'd2, 3'b000, 5'd2, 7'b0010011);
        mem[4] = NOP;
        mem[5] = enc_s(0, 5'd2, 5'd1, 3'b010, 7'b0100011);          // sw x2, 0(x1)
        mem[6] = enc_i(0, 5'd1, 3'b010, 5'd3, 7'b0000011);          // lw x3, 0(x1)
        mem[7] = enc_s(RES_ADDR, 5'd3, 5'd0, 3'b010, 7'b0100011);   // sw x3, RES
        mem[8] = enc_b(0, 5'd0, 5'd0, 3'b000, 7'b1100011);
        run_and_check("SW", ID_NUM, DATA_ADDR2, ID_NUM, 32'h0000_0000);

        $display("tb_rv32i_ctrl_wave_id PASS");
        $finish;
    end
endmodule
