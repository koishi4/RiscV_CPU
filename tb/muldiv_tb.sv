`timescale 1ns/1ps
`include "defines.vh"

module muldiv_tb;
    reg clk;
    reg rst_n;

    reg muldiv_start;
    reg [2:0] muldiv_op;
    reg [`XLEN-1:0] muldiv_a;
    reg [`XLEN-1:0] muldiv_b;
    reg [`HART_ID_W-1:0] muldiv_hart_id;
    reg [`REG_ADDR_W-1:0] muldiv_rd;

    wire muldiv_busy;
    wire muldiv_done;
    wire [`XLEN-1:0] muldiv_result;
    wire [`HART_ID_W-1:0] muldiv_done_hart_id;
    wire [`REG_ADDR_W-1:0] muldiv_done_rd;

    integer random_iters;
    integer seed;

    muldiv_unit dut (
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

    localparam [`XLEN-1:0] ALL_ONES = {`XLEN{1'b1}};
    localparam [`XLEN-1:0] SIGN_MIN = {1'b1, {(`XLEN-1){1'b0}}};
    localparam integer DW = `XLEN * 2;

    function [`XLEN-1:0] ref_muldiv;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        reg signed [`XLEN-1:0] a_s;
        reg signed [`XLEN-1:0] b_s;
        reg [`XLEN-1:0] a_u;
        reg [`XLEN-1:0] b_u;
        reg signed [DW-1:0] prod_ss;
        reg [DW-1:0] prod_uu;
        reg [DW-1:0] prod_su;
        begin
            a_s = a;
            b_s = b;
            a_u = a;
            b_u = b;
            prod_ss = a_s * b_s;
            prod_uu = a_u * b_u;
            if (a_s[`XLEN-1]) begin
                prod_su = prod_uu - {b_u, {`XLEN{1'b0}}};
            end else begin
                prod_su = prod_uu;
            end

            ref_muldiv = {`XLEN{1'b0}};
            case (op)
                `MULDIV_OP_MUL: begin
                    ref_muldiv = prod_uu[`XLEN-1:0];
                end
                `MULDIV_OP_MULH: begin
                    ref_muldiv = prod_ss[DW-1:`XLEN];
                end
                `MULDIV_OP_MULHU: begin
                    ref_muldiv = prod_uu[DW-1:`XLEN];
                end
                `MULDIV_OP_MULHSU: begin
                    ref_muldiv = prod_su[DW-1:`XLEN];
                end
                `MULDIV_OP_DIV: begin
                    if (b_u == {`XLEN{1'b0}}) begin
                        ref_muldiv = ALL_ONES;
                    end else if ((a_u == SIGN_MIN) && (b_u == ALL_ONES)) begin
                        ref_muldiv = SIGN_MIN;
                    end else begin
                        ref_muldiv = $signed(a_s) / $signed(b_s);
                    end
                end
                `MULDIV_OP_DIVU: begin
                    if (b_u == {`XLEN{1'b0}}) begin
                        ref_muldiv = ALL_ONES;
                    end else begin
                        ref_muldiv = a_u / b_u;
                    end
                end
                `MULDIV_OP_REM: begin
                    if (b_u == {`XLEN{1'b0}}) begin
                        ref_muldiv = a_u;
                    end else if ((a_u == SIGN_MIN) && (b_u == ALL_ONES)) begin
                        ref_muldiv = {`XLEN{1'b0}};
                    end else begin
                        ref_muldiv = $signed(a_s) % $signed(b_s);
                    end
                end
                `MULDIV_OP_REMU: begin
                    if (b_u == {`XLEN{1'b0}}) begin
                        ref_muldiv = a_u;
                    end else begin
                        ref_muldiv = a_u % b_u;
                    end
                end
                default: begin
                    ref_muldiv = {`XLEN{1'b0}};
                end
            endcase
        end
    endfunction

    task automatic drive_start;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        input [`HART_ID_W-1:0] hart_id;
        input [`REG_ADDR_W-1:0] rd;
        integer wait_cycles;
        integer max_wait;
        begin
            wait_cycles = 0;
            max_wait = 200;
            while (muldiv_busy) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > max_wait) begin
                    $display("ERROR: busy stuck before start op=%0d a=%h b=%h busy=%b state=%0d div_count=%0d",
                             op, a, b, muldiv_busy, dut.state, dut.div_count);
                    $finish;
                end
            end
            @(negedge clk);
            muldiv_start = 1'b1;
            muldiv_op = op;
            muldiv_a = a;
            muldiv_b = b;
            muldiv_hart_id = hart_id;
            muldiv_rd = rd;
            @(negedge clk);
            muldiv_start = 1'b0;
        end
    endtask

    task automatic drive_start_nowait;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        input [`HART_ID_W-1:0] hart_id;
        input [`REG_ADDR_W-1:0] rd;
        begin
            @(negedge clk);
            muldiv_start = 1'b1;
            muldiv_op = op;
            muldiv_a = a;
            muldiv_b = b;
            muldiv_hart_id = hart_id;
            muldiv_rd = rd;
            @(negedge clk);
            muldiv_start = 1'b0;
        end
    endtask

    task automatic wait_done;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        output [`XLEN-1:0] result;
        output [`HART_ID_W-1:0] hart_id;
        output [`REG_ADDR_W-1:0] rd;
        integer cycles;
        integer max_cycles;
        begin
            cycles = 0;
            max_cycles = ((op == `MULDIV_OP_DIV)  || (op == `MULDIV_OP_DIVU) ||
                          (op == `MULDIV_OP_REM)  || (op == `MULDIV_OP_REMU)) ? 80 : 16;
            while (!muldiv_done) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (cycles > max_cycles) begin
                    $display("ERROR: timeout op=%0d a=%h b=%h busy=%b state=%0d div_count=%0d",
                             op, a, b, muldiv_busy, dut.state, dut.div_count);
                    $finish;
                end
            end
            result = muldiv_result;
            hart_id = muldiv_done_hart_id;
            rd = muldiv_done_rd;
            if (!muldiv_busy) begin
                $display("ERROR: busy deasserted during done");
                $finish;
            end
            @(posedge clk);
            #1;
            if (muldiv_done) begin
                $display("ERROR: done pulse wider than 1 cycle");
                $finish;
            end
        end
    endtask

    task automatic run_check;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        input [`HART_ID_W-1:0] hart_id;
        input [`REG_ADDR_W-1:0] rd;
        reg [`XLEN-1:0] exp;
        reg [`XLEN-1:0] got;
        reg [`HART_ID_W-1:0] done_hart;
        reg [`REG_ADDR_W-1:0] done_rd;
        begin
            exp = ref_muldiv(op, a, b);
            drive_start(op, a, b, hart_id, rd);
            wait_done(op, a, b, got, done_hart, done_rd);
            if (got !== exp) begin
                $display("ERROR: op=%0d a=%h b=%h exp=%h got=%h", op, a, b, exp, got);
                $finish;
            end
            if (done_hart !== hart_id) begin
                $display("ERROR: hart_id mismatch exp=%0d got=%0d", hart_id, done_hart);
                $finish;
            end
            if (done_rd !== rd) begin
                $display("ERROR: rd mismatch exp=%0d got=%0d", rd, done_rd);
                $finish;
            end
        end
    endtask

    task automatic pick_operand;
        input integer idx;
        output reg [`XLEN-1:0] value;
        begin
            case (idx % 8)
                0: value = 32'h0000_0000;
                1: value = 32'h0000_0001;
                2: value = 32'hFFFF_FFFF;
                3: value = 32'h8000_0000;
                4: value = 32'h7FFF_FFFF;
                default: begin
                    value = $urandom(seed);
                    seed = seed + 1;
                end
            endcase
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        muldiv_start = 1'b0;
        muldiv_op = 3'd0;
        muldiv_a = {`XLEN{1'b0}};
        muldiv_b = {`XLEN{1'b0}};
        muldiv_hart_id = {`HART_ID_W{1'b0}};
        muldiv_rd = {`REG_ADDR_W{1'b0}};

        if (!$value$plusargs("RANDOM_ITERS=%d", random_iters)) begin
            random_iters = 10000;
        end
        if (!$value$plusargs("SEED=%d", seed)) begin
            seed = 32'd1;
        end
        $display("muldiv_tb CONFIG: RANDOM_ITERS=%0d SEED=%0d", random_iters, seed);

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Directed corner cases.
        run_check(`MULDIV_OP_MUL, 32'h0000_0000, 32'h0000_0000, 1'b0, 5'd1);
        run_check(`MULDIV_OP_MUL, 32'h0000_0001, 32'h0000_0001, 1'b1, 5'd2);
        run_check(`MULDIV_OP_MUL, 32'hFFFF_FFFF, 32'h0000_0002, 1'b0, 5'd3);
        run_check(`MULDIV_OP_MULH, 32'h8000_0000, 32'h0000_0002, 1'b1, 5'd4);
        run_check(`MULDIV_OP_MULHU, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b0, 5'd5);
        run_check(`MULDIV_OP_MULHSU, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b1, 5'd6);

        run_check(`MULDIV_OP_DIV, 32'h0000_0007, 32'h0000_0003, 1'b0, 5'd7);
        run_check(`MULDIV_OP_DIV, 32'h8000_0000, 32'hFFFF_FFFF, 1'b1, 5'd8);
        run_check(`MULDIV_OP_DIV, 32'h0000_0001, 32'h0000_0000, 1'b0, 5'd9);
        run_check(`MULDIV_OP_DIVU, 32'hFFFF_FFFF, 32'h0000_0002, 1'b1, 5'd10);
        run_check(`MULDIV_OP_REM, 32'hFFFF_FFFE, 32'h0000_0007, 1'b0, 5'd11);
        run_check(`MULDIV_OP_REMU, 32'hFFFF_FFFF, 32'h0000_0000, 1'b1, 5'd12);

        // Start while busy should be ignored.
        drive_start(`MULDIV_OP_DIV, 32'h0000_00FF, 32'h0000_0003, 1'b0, 5'd13);
        repeat (3) @(posedge clk);
        drive_start_nowait(`MULDIV_OP_MUL, 32'h0000_00AA, 32'h0000_0002, 1'b1, 5'd14);
        begin
            reg [`XLEN-1:0] got;
            reg [`HART_ID_W-1:0] done_hart;
            reg [`REG_ADDR_W-1:0] done_rd;
            reg [`XLEN-1:0] exp;
            exp = ref_muldiv(`MULDIV_OP_DIV, 32'h0000_00FF, 32'h0000_0003);
            wait_done(`MULDIV_OP_DIV, 32'h0000_00FF, 32'h0000_0003,
                      got, done_hart, done_rd);
            if (got !== exp) begin
                $display("ERROR: busy-ignore result exp=%h got=%h", exp, got);
                $finish;
            end
            if (done_hart !== 1'b0 || done_rd !== 5'd13) begin
                $display("ERROR: busy-ignore metadata mismatch hart=%0d rd=%0d", done_hart, done_rd);
                $finish;
            end
        end

        // Randomized vectors.
        begin : random_tests
            integer i;
            reg [`XLEN-1:0] a;
            reg [`XLEN-1:0] b;
            reg [2:0] op;
            reg [`HART_ID_W-1:0] hart_id;
            reg [`REG_ADDR_W-1:0] rd;
            integer op_i;
            for (op_i = 0; op_i < 8; op_i = op_i + 1) begin
                op = op_i[2:0];
                for (i = 0; i < random_iters; i = i + 1) begin
                    pick_operand(i, a);
                    pick_operand(i + 3, b);
                    hart_id = $urandom(seed) % `HART_NUM;
                    seed = seed + 1;
                    rd = $urandom(seed) % 32;
                    seed = seed + 1;
                    run_check(op, a, b, hart_id[`HART_ID_W-1:0], rd[`REG_ADDR_W-1:0]);
                end
            end
        end

        $display("muldiv_tb PASS");
        $finish;
    end
endmodule
