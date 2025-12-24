`include "defines.vh"
`include "interface.vh"

module muldiv_unit(
    input  clk,
    input  rst_n,
    `MULDIV_REQ_PORTS(input, muldiv),
    `MULDIV_RSP_PORTS(output, muldiv)
);
    // start is accepted only when not busy; start asserted while busy is ignored.

    localparam integer MUL_LATENCY = 4;
    localparam integer DIV_LATENCY = 32;
    localparam integer CNT_W = 6;
    localparam integer DW = `XLEN * 2;
    localparam [`XLEN-1:0] ALL_ONES = {`XLEN{1'b1}};
    localparam [`XLEN-1:0] SIGN_MIN = {1'b1, {(`XLEN-1){1'b0}}};

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_RUN  = 2'd1;
    localparam [1:0] STATE_DONE = 2'd2;

    reg [1:0] state;
    reg [CNT_W-1:0] latency_cnt;

    reg [`XLEN-1:0] result_reg;
    reg [`HART_ID_W-1:0] done_hart_id_reg;
    reg [`REG_ADDR_W-1:0] done_rd_reg;

    function [`XLEN-1:0] compute_result;
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

            compute_result = {`XLEN{1'b0}};
            case (op)
                `MULDIV_OP_MUL: begin
                    compute_result = prod_uu[`XLEN-1:0];
                end
                `MULDIV_OP_MULH: begin
                    compute_result = prod_ss[DW-1:`XLEN];
                end
                `MULDIV_OP_MULHU: begin
                    compute_result = prod_uu[DW-1:`XLEN];
                end
                `MULDIV_OP_MULHSU: begin
                    compute_result = prod_su[DW-1:`XLEN];
                end
                `MULDIV_OP_DIV: begin
                    if (b_u == {`XLEN{1'b0}}) begin
                        compute_result = ALL_ONES;
                    end else if ((a_u == SIGN_MIN) && (b_u == ALL_ONES)) begin
                        compute_result = SIGN_MIN;
                    end else begin
                        compute_result = $signed(a_s) / $signed(b_s);
                    end
                end
                `MULDIV_OP_DIVU: begin
                    if (b_u == {`XLEN{1'b0}}) begin
                        compute_result = ALL_ONES;
                    end else begin
                        compute_result = a_u / b_u;
                    end
                end
                `MULDIV_OP_REM: begin
                    if (b_u == {`XLEN{1'b0}}) begin
                        compute_result = a_u;
                    end else if ((a_u == SIGN_MIN) && (b_u == ALL_ONES)) begin
                        compute_result = {`XLEN{1'b0}};
                    end else begin
                        compute_result = $signed(a_s) % $signed(b_s);
                    end
                end
                `MULDIV_OP_REMU: begin
                    if (b_u == {`XLEN{1'b0}}) begin
                        compute_result = a_u;
                    end else begin
                        compute_result = a_u % b_u;
                    end
                end
                default: begin
                    compute_result = {`XLEN{1'b0}};
                end
            endcase
        end
    endfunction

    wire op_is_div = (muldiv_op == `MULDIV_OP_DIV)  ||
                     (muldiv_op == `MULDIV_OP_DIVU) ||
                     (muldiv_op == `MULDIV_OP_REM)  ||
                     (muldiv_op == `MULDIV_OP_REMU);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            latency_cnt <= {CNT_W{1'b0}};
            result_reg <= {`XLEN{1'b0}};
            done_hart_id_reg <= {`HART_ID_W{1'b0}};
            done_rd_reg <= {`REG_ADDR_W{1'b0}};
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (muldiv_start) begin
                        state <= STATE_RUN;
                        result_reg <= compute_result(muldiv_op, muldiv_a, muldiv_b);
                        done_hart_id_reg <= muldiv_hart_id;
                        done_rd_reg <= muldiv_rd;
                        latency_cnt <= op_is_div ? (DIV_LATENCY - 1) : (MUL_LATENCY - 1);
                    end
                end
                STATE_RUN: begin
                    if (latency_cnt == {CNT_W{1'b0}}) begin
                        state <= STATE_DONE;
                    end else begin
                        latency_cnt <= latency_cnt - {{(CNT_W-1){1'b0}}, 1'b1};
                    end
                end
                STATE_DONE: begin
                    state <= STATE_IDLE;
                    latency_cnt <= {CNT_W{1'b0}};
                end
                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

    assign muldiv_busy         = (state != STATE_IDLE);
    assign muldiv_done         = (state == STATE_DONE);
    assign muldiv_result       = result_reg;
    assign muldiv_done_hart_id = done_hart_id_reg;
    assign muldiv_done_rd      = done_rd_reg;
endmodule
