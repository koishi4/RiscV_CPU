`timescale 1ns/1ps
`include "defines.vh"

module tb_muldiv_perf;
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
    localparam integer HIST_MAX = 32;

    integer op_count [0:7];
    integer op_cycles_sum [0:7];
    integer op_cycles_min [0:7];
    integer op_cycles_max [0:7];
    integer cycle_hist [0:HIST_MAX-1];
    integer cycle_hist_over;

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

    task automatic init_perf;
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                op_count[i] = 0;
                op_cycles_sum[i] = 0;
                op_cycles_min[i] = 0;
                op_cycles_max[i] = 0;
            end
            for (i = 0; i < HIST_MAX; i = i + 1) begin
                cycle_hist[i] = 0;
            end
            cycle_hist_over = 0;
        end
    endtask

    task automatic record_perf;
        input [2:0] op;
        input [7:0] cycles;
        begin
            if (op_count[op] == 0) begin
                op_cycles_min[op] = cycles;
                op_cycles_max[op] = cycles;
            end else begin
                if (cycles < op_cycles_min[op]) begin
                    op_cycles_min[op] = cycles;
                end
                if (cycles > op_cycles_max[op]) begin
                    op_cycles_max[op] = cycles;
                end
            end
            op_count[op] = op_count[op] + 1;
            op_cycles_sum[op] = op_cycles_sum[op] + cycles;
            if (cycles < HIST_MAX) begin
                cycle_hist[cycles] = cycle_hist[cycles] + 1;
            end else begin
                cycle_hist_over = cycle_hist_over + 1;
            end
        end
    endtask

    task automatic dump_perf;
        integer i;
        real avg;
        begin
            $display("muldiv perf summary:");
            for (i = 0; i < 8; i = i + 1) begin
                if (op_count[i] == 0) begin
                    $display("  op=%0d count=0", i);
                end else begin
                    avg = op_cycles_sum[i] * 1.0 / op_count[i];
                    case (i)
                        `MULDIV_OP_MUL:    $display("  MUL    count=%0d min=%0d max=%0d avg=%0.2f", op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                        `MULDIV_OP_MULH:   $display("  MULH   count=%0d min=%0d max=%0d avg=%0.2f", op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                        `MULDIV_OP_MULHU:  $display("  MULHU  count=%0d min=%0d max=%0d avg=%0.2f", op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                        `MULDIV_OP_MULHSU: $display("  MULHSU count=%0d min=%0d max=%0d avg=%0.2f", op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                        `MULDIV_OP_DIV:    $display("  DIV    count=%0d min=%0d max=%0d avg=%0.2f", op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                        `MULDIV_OP_DIVU:   $display("  DIVU   count=%0d min=%0d max=%0d avg=%0.2f", op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                        `MULDIV_OP_REM:    $display("  REM    count=%0d min=%0d max=%0d avg=%0.2f", op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                        `MULDIV_OP_REMU:   $display("  REMU   count=%0d min=%0d max=%0d avg=%0.2f", op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                        default:           $display("  op=%0d count=%0d min=%0d max=%0d avg=%0.2f", i, op_count[i], op_cycles_min[i], op_cycles_max[i], avg);
                    endcase
                end
            end
            $display("cycle histogram (cycles -> count):");
            for (i = 0; i < HIST_MAX; i = i + 1) begin
                $display("  %0d: %0d", i, cycle_hist[i]);
            end
            $display("  >=%0d: %0d", HIST_MAX, cycle_hist_over);
        end
    endtask

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

    task automatic wait_done;
        output [`XLEN-1:0] result;
        output [`HART_ID_W-1:0] hart_id;
        output [`REG_ADDR_W-1:0] rd;
        output [7:0] cycles;
        integer timeout;
        begin
            timeout = 200;
            cycles = 0;
            while (!muldiv_done && timeout > 0) begin
                @(posedge clk);
                cycles = cycles + 1;
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

    task automatic run_vec;
        input integer vec_id;
        input [2:0] op;
        input [`XLEN-1:0] a;
        input [`XLEN-1:0] b;
        reg [`XLEN-1:0] exp;
        reg [`XLEN-1:0] got;
        reg [7:0] cycles;
        reg [`HART_ID_W-1:0] done_hart;
        reg [`REG_ADDR_W-1:0] done_rd;
        begin
            exp = ref_muldiv(op, a, b);
            drive_start(op, a, b, 1'b0, 5'd0);
            wait_done(got, done_hart, done_rd, cycles);
            record_perf(op, cycles);
            $display("VEC[%0d] op=%0d a=%h b=%h cycles=%0d result=%h", vec_id, op, a, b, cycles, got);
            if (got !== exp) begin
                $display("ERROR: result mismatch exp=%h got=%h", exp, got);
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        integer i;
        reg [`XLEN-1:0] a;
        reg [`XLEN-1:0] b;
        reg [2:0] op;

        init_perf();

        rst_n = 1'b0;
        muldiv_start = 1'b0;
        muldiv_op = 3'd0;
        muldiv_a = {`XLEN{1'b0}};
        muldiv_b = {`XLEN{1'b0}};
        muldiv_hart_id = {`HART_ID_W{1'b0}};
        muldiv_rd = {`REG_ADDR_W{1'b0}};

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Directed vectors to expose fast paths and worst-ish cases.
        run_vec(1, `MULDIV_OP_MUL, 32'h0000_0000, 32'h0000_0000);
        run_vec(2, `MULDIV_OP_MUL, 32'h0000_0001, 32'h1234_5678);
        run_vec(3, `MULDIV_OP_MUL, 32'hffff_ffff, 32'h0000_0002);
        run_vec(4, `MULDIV_OP_MULH, 32'h8000_0000, 32'h0000_0002);
        run_vec(5, `MULDIV_OP_MULHU, 32'hffff_ffff, 32'hffff_ffff);
        run_vec(6, `MULDIV_OP_MULHSU, 32'hffff_ffff, 32'hffff_ffff);
        run_vec(7, `MULDIV_OP_DIV, 32'h8000_0000, 32'hffff_ffff);
        run_vec(8, `MULDIV_OP_DIV, 32'h0000_0001, 32'h0000_0000);
        run_vec(9, `MULDIV_OP_DIVU, 32'h0000_0033, 32'h0000_0008);
        run_vec(10, `MULDIV_OP_REM, 32'hffff_ff9c, 32'hffff_fffc);
        run_vec(11, `MULDIV_OP_REMU, 32'h0000_0005, 32'h0000_0007);
        run_vec(12, `MULDIV_OP_DIVU, 32'h8000_0000, 32'h0000_0010);

        // Random vectors for cycle distribution.
        for (i = 0; i < 256; i = i + 1) begin
            a = $urandom;
            b = $urandom;
            op = $urandom % 8;
            run_vec(1000 + i, op, a, b);
        end

        dump_perf();
        $display("tb_muldiv_perf PASS");
        $finish;
    end
endmodule
