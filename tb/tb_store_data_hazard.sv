`timescale 1ns/1ps
`include "defines.vh"

module tb_store_data_hazard;
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

    reg [`XLEN-1:0] mem[0:511];

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
    assign cpu_mem_rdata = mem[cpu_mem_addr[10:2]];

    always @(posedge clk) begin
        if (cpu_mem_req && cpu_mem_we && cpu_mem_ready) begin
            mem[cpu_mem_addr[10:2]] <= cpu_mem_wdata;
        end
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task init_mem;
        integer i;
        begin
            for (i = 0; i < 512; i = i + 1) begin
                mem[i] = 32'h00000013; // NOP
            end
        end
    endtask

    task load_prog_no_nop;
        begin
            // x1 = 0x200
            mem[0]  = 32'h20000093; // addi x1, x0, 0x200
            mem[1]  = 32'h00000313; // addi x6, x0, 0x00
            mem[2]  = 32'h0060A023; // sw x6, 0(x1)
            mem[3]  = 32'h01100313; // addi x6, x0, 0x11
            mem[4]  = 32'h0060A223; // sw x6, 4(x1)
            mem[5]  = 32'h02200313; // addi x6, x0, 0x22
            mem[6]  = 32'h0060A423; // sw x6, 8(x1)
            mem[7]  = 32'h03300313; // addi x6, x0, 0x33
            mem[8]  = 32'h0060A623; // sw x6, 12(x1)
            mem[9]  = 32'h00000063; // beq x0, x0, 0
            mem[64] = 32'h00000063; // hart1 idle
        end
    endtask

    task load_prog_with_nop;
        begin
            mem[0]  = 32'h20000093; // addi x1, x0, 0x200
            mem[1]  = 32'h00000313; // addi x6, x0, 0x00
            mem[2]  = 32'h00000013; // nop
            mem[3]  = 32'h0060A023; // sw x6, 0(x1)
            mem[4]  = 32'h01100313; // addi x6, x0, 0x11
            mem[5]  = 32'h00000013; // nop
            mem[6]  = 32'h0060A223; // sw x6, 4(x1)
            mem[7]  = 32'h02200313; // addi x6, x0, 0x22
            mem[8]  = 32'h00000013; // nop
            mem[9]  = 32'h0060A423; // sw x6, 8(x1)
            mem[10] = 32'h03300313; // addi x6, x0, 0x33
            mem[11] = 32'h00000013; // nop
            mem[12] = 32'h0060A623; // sw x6, 12(x1)
            mem[13] = 32'h00000063; // beq x0, x0, 0
            mem[64] = 32'h00000063; // hart1 idle
        end
    endtask

    task run_and_check(input bit expect_hazard);
        integer cycles;
        reg [31:0] w0;
        reg [31:0] w1;
        reg [31:0] w2;
        reg [31:0] w3;
        begin
            for (cycles = 0; cycles < 200; cycles = cycles + 1) begin
                @(posedge clk);
            end

            w0 = mem[32'h200 >> 2];
            w1 = mem[32'h204 >> 2];
            w2 = mem[32'h208 >> 2];
            w3 = mem[32'h20c >> 2];
            $display("mem[0x200]=0x%08x mem[0x204]=0x%08x mem[0x208]=0x%08x mem[0x20c]=0x%08x",
                     w0, w1, w2, w3);

            if (expect_hazard) begin
                if (w0 == 32'h00000000 && w1 == 32'h00000011 &&
                    w2 == 32'h00000022 && w3 == 32'h00000033) begin
                    $display("WARN: no hazard observed (unexpected)"); 
                end else begin
                    $display("Expected hazard observed in no-NOP case");
                end
            end else begin
                if (w0 !== 32'h00000000) $fatal(1, "w0 mismatch: 0x%08x", w0);
                if (w1 !== 32'h00000011) $fatal(1, "w1 mismatch: 0x%08x", w1);
                if (w2 !== 32'h00000022) $fatal(1, "w2 mismatch: 0x%08x", w2);
                if (w3 !== 32'h00000033) $fatal(1, "w3 mismatch: 0x%08x", w3);
                $display("No-NOP hazard fixed (NOP inserted)");
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        init_mem();
        load_prog_no_nop();

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = 32'h0000_0100;
        run_and_check(1'b1);

        rst_n = 1'b0;
        init_mem();
        load_prog_with_nop();

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        dut.pc[1] = 32'h0000_0100;
        run_and_check(1'b0);

        $display("store-data hazard check completed");
        $finish;
    end
endmodule
