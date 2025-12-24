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
        begin
            while (muldiv_busy) begin
                @(posedge clk);
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
        output [`XLEN-1:0] result;
        output [`HART_ID_W-1:0] hart_id;
        output [`REG_ADDR_W-1:0] rd;
        begin
            while (!muldiv_done) begin
                @(posedge clk);
            end
            result = muldiv_result;
            hart_id = muldiv_done_hart_id;
            rd = muldiv_done_rd;
            if (!muldiv_busy) begin
                $display("ERROR: busy deasserted during done");
                $finish;
            end
            @(posedge clk);
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
            wait_done(got, done_hart, done_rd);
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
            wait_done(got, done_hart, done_rd);
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
            for (i = 0; i < 1000; i = i + 1) begin
                a = $urandom;
                b = $urandom;
                op = $urandom % 8;
                hart_id = $urandom % `HART_NUM;
                rd = $urandom % 32;
                run_check(op, a, b, hart_id[`HART_ID_W-1:0], rd[`REG_ADDR_W-1:0]);
            end
        end

        $display("muldiv_tb PASS");
        $finish;
    end
endmodule
