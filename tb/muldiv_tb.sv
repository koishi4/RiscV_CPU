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

    function automatic [`XLEN-1:0] abs_s;
        input [`XLEN-1:0] value;
        begin
            abs_s = value[`XLEN-1] ? (~value + 32'd1) : value;
        end
    endfunction

    function automatic [5:0] msb_pos;
        input [`XLEN-1:0] value;
        integer i;
        reg found;
        begin
            msb_pos = 6'd0;
            found = 1'b0;
            for (i = `XLEN-1; i >= 0; i = i - 1) begin
                if (!found && value[i]) begin
                    msb_pos = i[5:0];
                    found = 1'b1;
                end
            end
        end
    endfunction

    function automatic is_pow2;
        input [`XLEN-1:0] value;
        begin
            is_pow2 = (value != {`XLEN{1'b0}}) && ((value & (value - 32'd1)) == {`XLEN{1'b0}});
        end
    endfunction

    function automatic is_mul_fast;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        begin
            is_mul_fast = 1'b0;
            if ((op == `MULDIV_OP_MUL) || (op == `MULDIV_OP_MULH) ||
                (op == `MULDIV_OP_MULHU) || (op == `MULDIV_OP_MULHSU)) begin
                if ((a == {`XLEN{1'b0}}) || (b == {`XLEN{1'b0}}) ||
                    (a == 32'd1) || (b == 32'd1) ||
                    (a == ALL_ONES) || (b == ALL_ONES)) begin
                    is_mul_fast = 1'b1;
                end
            end
        end
    endfunction

    function automatic is_div_fast;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        reg [`XLEN-1:0] abs_a;
        reg [`XLEN-1:0] abs_b;
        reg signed_overflow;
        begin
            is_div_fast = 1'b0;
            if ((op == `MULDIV_OP_DIV) || (op == `MULDIV_OP_DIVU) ||
                (op == `MULDIV_OP_REM) || (op == `MULDIV_OP_REMU)) begin
                abs_a = ((op == `MULDIV_OP_DIV) || (op == `MULDIV_OP_REM)) ? abs_s(a) : a;
                abs_b = ((op == `MULDIV_OP_DIV) || (op == `MULDIV_OP_REM)) ? abs_s(b) : b;
                signed_overflow = ((op == `MULDIV_OP_DIV) || (op == `MULDIV_OP_REM)) &&
                                  (a == SIGN_MIN) && (b == ALL_ONES);
                is_div_fast = (b == {`XLEN{1'b0}}) || signed_overflow ||
                              is_pow2(abs_b) || (abs_a < abs_b);
            end
        end
    endfunction

    function automatic [7:0] expected_cycles;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        reg [`XLEN-1:0] abs_a;
        reg [`XLEN-1:0] abs_b;
        reg [5:0] shift_init;
        begin
            if (is_mul_fast(op, a, b) || is_div_fast(op, a, b)) begin
                expected_cycles = 8'd1;
            end else if ((op == `MULDIV_OP_MUL) || (op == `MULDIV_OP_MULH) ||
                         (op == `MULDIV_OP_MULHU) || (op == `MULDIV_OP_MULHSU)) begin
                expected_cycles = 8'd3;
            end else begin
                abs_a = ((op == `MULDIV_OP_DIV) || (op == `MULDIV_OP_REM)) ? abs_s(a) : a;
                abs_b = ((op == `MULDIV_OP_DIV) || (op == `MULDIV_OP_REM)) ? abs_s(b) : b;
                shift_init = msb_pos(abs_a) - msb_pos(abs_b);
                expected_cycles = {2'd0, (shift_init[5:1])} + 8'd1;
            end
        end
    endfunction

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
        output [7:0] cycles;
        output seen_busy;
        integer timeout;
        begin
            timeout = 200;
            cycles = 0;
            seen_busy = 1'b0;
            while (!muldiv_done && timeout > 0) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (muldiv_busy) begin
                    seen_busy = 1'b1;
                end
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("ERROR: Timeout waiting for muldiv_done!");
                $finish;
            end
            result = muldiv_result;
            hart_id = muldiv_done_hart_id;
            rd = muldiv_done_rd;
            @(posedge clk);
            #1;
            if (muldiv_done) begin
                $display("ERROR: done pulse wider than 1 cycle");
                $finish;
            end
        end
    endtask

    task automatic run_check;
        input integer test_id;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        input [`HART_ID_W-1:0] hart_id;
        input [`REG_ADDR_W-1:0] rd;
        reg [`XLEN-1:0] exp;
        reg [`XLEN-1:0] got;
        reg [`HART_ID_W-1:0] done_hart;
        reg [`REG_ADDR_W-1:0] done_rd;
        reg [7:0] cycles;
        reg seen_busy;
        reg [7:0] exp_cycles;
        reg fast_expected;
        begin
            exp = ref_muldiv(op, a, b);
            exp_cycles = expected_cycles(op, a, b);
            fast_expected = is_mul_fast(op, a, b) || is_div_fast(op, a, b);
            $display("TEST[%0d] op=%0d a=%h b=%h exp=%h", test_id, op, a, b, exp);
            drive_start(op, a, b, hart_id, rd);
            wait_done(got, done_hart, done_rd, cycles, seen_busy);
            $display("  -> got=%h cycles=%0d busy_seen=%0d", got, cycles, seen_busy);

            if (got !== exp) begin
                $display("ERROR: result mismatch exp=%h got=%h", exp, got);
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
            if (!fast_expected && !seen_busy) begin
                $display("ERROR: expected busy during op, but busy never asserted");
                $finish;
            end
            if (cycles > (exp_cycles + 8'd1)) begin
                $display("ERROR: latency too long exp<=%0d got=%0d", exp_cycles, cycles);
                $finish;
            end

        end
    endtask

    task automatic check_busy_ignore;
        reg [`XLEN-1:0] got;
        reg [`HART_ID_W-1:0] done_hart;
        reg [`REG_ADDR_W-1:0] done_rd;
        reg [7:0] cycles;
        reg seen_busy;
        reg [`XLEN-1:0] exp;
        begin
            drive_start(`MULDIV_OP_DIVU, 32'hf123_4567, 32'h0001_2345, 1'b0, 5'd13);
            while (!muldiv_busy) begin
                @(posedge clk);
            end
            drive_start_nowait(`MULDIV_OP_MUL, 32'h0000_00aa, 32'h0000_0002, 1'b1, 5'd14);
            exp = ref_muldiv(`MULDIV_OP_DIVU, 32'hf123_4567, 32'h0001_2345);
            wait_done(got, done_hart, done_rd, cycles, seen_busy);
            if (got !== exp) begin
                $display("ERROR: busy-ignore result mismatch exp=%h got=%h", exp, got);
                $finish;
            end
            if (done_hart !== 1'b0 || done_rd !== 5'd13) begin
                $display("ERROR: busy-ignore metadata mismatch hart=%0d rd=%0d", done_hart, done_rd);
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // No bubble: done should not coincide with busy.
    always @(posedge clk) begin
        if (muldiv_done && muldiv_busy) begin
            $display("ERROR: bubble detected: done asserted while busy");
            $finish;
        end
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
        run_check(1, `MULDIV_OP_MUL, 32'h0000_0000, 32'h0000_0000, 1'b0, 5'd1);
        run_check(2, `MULDIV_OP_MUL, 32'h0000_0001, 32'h0000_1234, 1'b1, 5'd2);
        run_check(3, `MULDIV_OP_MUL, 32'hffff_ffff, 32'h0000_0002, 1'b0, 5'd3);
        run_check(4, `MULDIV_OP_MULH, 32'h8000_0000, 32'h0000_0002, 1'b1, 5'd4);
        run_check(5, `MULDIV_OP_MULHU, 32'hffff_ffff, 32'hffff_ffff, 1'b0, 5'd5);
        run_check(6, `MULDIV_OP_MULHSU, 32'hffff_ffff, 32'hffff_ffff, 1'b1, 5'd6);

        run_check(7, `MULDIV_OP_DIV, 32'h0000_0007, 32'h0000_0003, 1'b0, 5'd7);
        run_check(8, `MULDIV_OP_DIV, 32'h8000_0000, 32'hffff_ffff, 1'b1, 5'd8);
        run_check(9, `MULDIV_OP_DIV, 32'h0000_0001, 32'h0000_0000, 1'b0, 5'd9);
        run_check(10, `MULDIV_OP_DIVU, 32'h0000_0033, 32'h0000_0008, 1'b1, 5'd10);
        run_check(11, `MULDIV_OP_REM, 32'hffff_ff9c, 32'hffff_fffc, 1'b0, 5'd11);
        run_check(12, `MULDIV_OP_REMU, 32'h0000_0005, 32'h0000_0007, 1'b1, 5'd12);
        run_check(13, `MULDIV_OP_MUL, 32'h8000_0000, 32'h0000_0002, 1'b0, 5'd13);
        run_check(14, `MULDIV_OP_MULH, 32'h8000_0000, 32'h8000_0000, 1'b1, 5'd14);
        run_check(15, `MULDIV_OP_MULH, 32'h7fff_ffff, 32'h7fff_ffff, 1'b0, 5'd15);
        run_check(16, `MULDIV_OP_MULHU, 32'hffff_ffff, 32'hffff_fffe, 1'b1, 5'd16);
        run_check(17, `MULDIV_OP_MULHSU, 32'h8000_0000, 32'h0000_0002, 1'b0, 5'd17);
        run_check(18, `MULDIV_OP_DIV, 32'h0000_0007, 32'hffff_fffd, 1'b1, 5'd18);
        run_check(19, `MULDIV_OP_REM, 32'h0000_0007, 32'hffff_fffd, 1'b0, 5'd19);
        run_check(20, `MULDIV_OP_DIV, 32'hffff_fffd, 32'h0000_0005, 1'b1, 5'd20);
        run_check(21, `MULDIV_OP_REM, 32'hffff_fffd, 32'h0000_0005, 1'b0, 5'd21);
        run_check(22, `MULDIV_OP_DIVU, 32'h8000_0000, 32'h0000_0010, 1'b1, 5'd22);
        run_check(23, `MULDIV_OP_REMU, 32'h8000_0005, 32'h0000_0008, 1'b0, 5'd23);
        run_check(24, `MULDIV_OP_DIVU, 32'h0000_0003, 32'h0000_0005, 1'b1, 5'd24);
        run_check(25, `MULDIV_OP_REMU, 32'h0000_0003, 32'h0000_0005, 1'b0, 5'd25);
        run_check(26, `MULDIV_OP_REM, 32'h8000_0000, 32'hffff_ffff, 1'b1, 5'd26);
        run_check(27, `MULDIV_OP_DIV, 32'h1234_5678, 32'h0000_0000, 1'b0, 5'd27);
        run_check(28, `MULDIV_OP_REM, 32'h1234_5678, 32'h0000_0000, 1'b1, 5'd28);

        check_busy_ignore();

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
                run_check(1000 + i, op, a, b, hart_id[`HART_ID_W-1:0], rd[`REG_ADDR_W-1:0]);
            end
        end

        $display("muldiv_tb PASS");
        $finish;
    end
endmodule
