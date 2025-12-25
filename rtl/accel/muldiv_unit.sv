`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module muldiv_unit(
    input  logic clk,
    input  logic rst_n,
    `MULDIV_REQ_PORTS(input, muldiv),
    `MULDIV_RSP_PORTS(output, muldiv)
);
    // start is accepted only when not busy; start asserted while busy is ignored.

    localparam int NUM_PP = 17;
    localparam [`XLEN-1:0] ALL_ONES = {`XLEN{1'b1}};
    localparam [`XLEN-1:0] SIGN_MIN = {1'b1, {(`XLEN-1){1'b0}}};

    typedef enum logic [2:0] {
        S_IDLE     = 3'd0,
        S_MUL_PP   = 3'd1,
        S_MUL_CSA  = 3'd2,
        S_MUL_ADD  = 3'd3,
        S_DIV_RUN  = 3'd4,
        S_DONE     = 3'd5
    } state_t;

    state_t state;

    logic [`XLEN-1:0] result_reg;
    logic [`HART_ID_W-1:0] done_hart_id_reg;
    logic [`REG_ADDR_W-1:0] done_rd_reg;
    logic done_reg;

    // Mul state.
    logic [`XLEN-1:0] mul_a_mag_reg;
    logic [`XLEN-1:0] mul_b_mag_reg;
    logic mul_sel_high;
    logic mul_signfix;
    logic mul_neg_reg;
    logic [63:0] mul_pp [0:NUM_PP-1];
    logic [63:0] mul_sum;
    logic [63:0] mul_carry;

    // Div state.
    logic div_sel_rem;
    logic div_sign_q;
    logic div_sign_r;
    logic [`XLEN-1:0] div_divisor_abs;
    logic [`XLEN-1:0] div_quot;
    logic signed [33:0] div_rem;
    logic [5:0] div_count;

    // Combinational mul helpers.
    logic [63:0] pp_comb [0:NUM_PP-1];
    logic [63:0] csa_sum_comb;
    logic [63:0] csa_carry_comb;
    logic [63:0] mul_product_add;

    // Combinational div helpers.
    logic signed [33:0] div_rem_next;
    logic [`XLEN-1:0] div_quot_next;
    logic signed [33:0] div_rem_restored_next;
    logic [`XLEN-1:0] div_quot_final_next;
    logic [`XLEN-1:0] div_rem_final_next;

    wire op_is_mul = (muldiv_op == `MULDIV_OP_MUL) ||
                     (muldiv_op == `MULDIV_OP_MULH) ||
                     (muldiv_op == `MULDIV_OP_MULHU) ||
                     (muldiv_op == `MULDIV_OP_MULHSU);

    wire op_is_div = (muldiv_op == `MULDIV_OP_DIV) ||
                     (muldiv_op == `MULDIV_OP_DIVU) ||
                     (muldiv_op == `MULDIV_OP_REM) ||
                     (muldiv_op == `MULDIV_OP_REMU);

    wire start_div_signed = (muldiv_op == `MULDIV_OP_DIV) ||
                            (muldiv_op == `MULDIV_OP_REM);
    wire start_div_sel_rem = (muldiv_op == `MULDIV_OP_REM) ||
                             (muldiv_op == `MULDIV_OP_REMU);
    wire start_div_zero = (muldiv_b == {`XLEN{1'b0}});
    wire start_div_overflow = start_div_signed &&
                              (muldiv_a == SIGN_MIN) &&
                              (muldiv_b == ALL_ONES);
    wire [`XLEN-1:0] start_dividend_abs =
        start_div_signed && muldiv_a[`XLEN-1] ? (~muldiv_a + 32'd1) : muldiv_a;
    wire [`XLEN-1:0] start_divisor_abs =
        start_div_signed && muldiv_b[`XLEN-1] ? (~muldiv_b + 32'd1) : muldiv_b;

    function automatic signed [34:0] booth_partial;
        input [2:0] code;
        input signed [32:0] x;
        reg signed [34:0] x1;
        reg signed [34:0] x2;
        begin
            x1 = {{2{x[32]}}, x};
            x2 = {{1{x[32]}}, x, 1'b0};
            case (code)
                3'b000, 3'b111: booth_partial = 35'sd0;
                3'b001, 3'b010: booth_partial = x1;
                3'b011: booth_partial = x2;
                3'b100: booth_partial = -x2;
                3'b101, 3'b110: booth_partial = -x1;
                default: booth_partial = 35'sd0;
            endcase
        end
    endfunction

    always_comb begin
        int idx;
        logic [32:0] a_ext;
        logic [32:0] b_ext;
        logic [34:0] b_booth;
        logic [2:0] booth_bits;
        logic signed [34:0] pp_raw;
        logic signed [63:0] pp_ext;

        a_ext = {1'b0, mul_a_mag_reg};
        b_ext = {1'b0, mul_b_mag_reg};
        b_booth = {b_ext[32], b_ext, 1'b0};

        for (idx = 0; idx < NUM_PP; idx = idx + 1) begin
            booth_bits = b_booth[2*idx+2 -: 3];
            pp_raw = booth_partial(booth_bits, a_ext);
            pp_ext = {{(64-35){pp_raw[34]}}, pp_raw};
            pp_comb[idx] = pp_ext <<< (2*idx);
        end
    end

    always_comb begin
        int idx;
        logic [63:0] sum;
        logic [63:0] carry;
        logic [63:0] tmp_sum;
        logic [63:0] tmp_carry;
        logic [63:0] carry_shift;

        sum = 64'b0;
        carry = 64'b0;
        for (idx = 0; idx < NUM_PP; idx = idx + 1) begin
            carry_shift = carry << 1;
            tmp_sum = sum ^ carry_shift ^ mul_pp[idx];
            tmp_carry = (sum & carry_shift) |
                        (sum & mul_pp[idx]) |
                        (carry_shift & mul_pp[idx]);
            sum = tmp_sum;
            carry = tmp_carry;
        end
        csa_sum_comb = sum;
        csa_carry_comb = carry;
    end

    assign mul_product_add = mul_sum + (mul_carry << 1);

    always_comb begin
        logic signed [33:0] rem_shift;
        logic [`XLEN-1:0] quot_shift;
        rem_shift = {div_rem[32:0], div_quot[`XLEN-1]};
        quot_shift = {div_quot[`XLEN-2:0], 1'b0};
        if (!rem_shift[33]) begin
            div_rem_next = rem_shift - {2'b0, div_divisor_abs};
        end else begin
            div_rem_next = rem_shift + {2'b0, div_divisor_abs};
        end
        if (!div_rem_next[33]) begin
            div_quot_next = quot_shift | {{(`XLEN-1){1'b0}}, 1'b1};
        end else begin
            div_quot_next = quot_shift;
        end
    end

    always_comb begin
        div_rem_restored_next = div_rem_next;
        if (div_rem_next[33]) begin
            div_rem_restored_next = div_rem_next + {2'b0, div_divisor_abs};
        end
        div_quot_final_next = div_sign_q ? (~div_quot_next + 32'd1) : div_quot_next;
        div_rem_final_next = div_sign_r ?
                             (~div_rem_restored_next[`XLEN-1:0] + 32'd1) :
                             div_rem_restored_next[`XLEN-1:0];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        int idx;
        if (!rst_n) begin
            state <= S_IDLE;
            result_reg <= {`XLEN{1'b0}};
            done_hart_id_reg <= {`HART_ID_W{1'b0}};
            done_rd_reg <= {`REG_ADDR_W{1'b0}};
            done_reg <= 1'b0;

            mul_a_mag_reg <= {`XLEN{1'b0}};
            mul_b_mag_reg <= {`XLEN{1'b0}};
            mul_sel_high <= 1'b0;
            mul_signfix <= 1'b0;
            mul_neg_reg <= 1'b0;
            for (idx = 0; idx < NUM_PP; idx = idx + 1) begin
                mul_pp[idx] <= 64'b0;
            end
            mul_sum <= 64'b0;
            mul_carry <= 64'b0;

            div_sel_rem <= 1'b0;
            div_sign_q <= 1'b0;
            div_sign_r <= 1'b0;
            div_divisor_abs <= {`XLEN{1'b0}};
            div_quot <= {`XLEN{1'b0}};
            div_rem <= 34'sd0;
            div_count <= 6'd0;
        end else begin
            done_reg <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (muldiv_start) begin
                        done_hart_id_reg <= muldiv_hart_id;
                        done_rd_reg <= muldiv_rd;
                        if (op_is_mul) begin
                            case (muldiv_op)
                                `MULDIV_OP_MUL: begin
                                    mul_sel_high <= 1'b0;
                                    mul_signfix <= 1'b0;
                                    mul_neg_reg <= 1'b0;
                                    mul_a_mag_reg <= muldiv_a;
                                    mul_b_mag_reg <= muldiv_b;
                                end
                                `MULDIV_OP_MULH: begin
                                    mul_sel_high <= 1'b1;
                                    mul_signfix <= 1'b1;
                                    mul_neg_reg <= muldiv_a[`XLEN-1] ^ muldiv_b[`XLEN-1];
                                    mul_a_mag_reg <= muldiv_a[`XLEN-1] ?
                                                     (~muldiv_a + 32'd1) : muldiv_a;
                                    mul_b_mag_reg <= muldiv_b[`XLEN-1] ?
                                                     (~muldiv_b + 32'd1) : muldiv_b;
                                end
                                `MULDIV_OP_MULHU: begin
                                    mul_sel_high <= 1'b1;
                                    mul_signfix <= 1'b0;
                                    mul_neg_reg <= 1'b0;
                                    mul_a_mag_reg <= muldiv_a;
                                    mul_b_mag_reg <= muldiv_b;
                                end
                                `MULDIV_OP_MULHSU: begin
                                    mul_sel_high <= 1'b1;
                                    mul_signfix <= 1'b1;
                                    mul_neg_reg <= muldiv_a[`XLEN-1];
                                    mul_a_mag_reg <= muldiv_a[`XLEN-1] ?
                                                     (~muldiv_a + 32'd1) : muldiv_a;
                                    mul_b_mag_reg <= muldiv_b;
                                end
                                default: begin
                                    mul_sel_high <= 1'b0;
                                    mul_signfix <= 1'b0;
                                    mul_neg_reg <= 1'b0;
                                    mul_a_mag_reg <= muldiv_a;
                                    mul_b_mag_reg <= muldiv_b;
                                end
                            endcase
                            state <= S_MUL_PP;
                        end else if (op_is_div) begin
                            if (start_div_zero) begin
                                result_reg <= start_div_sel_rem ? muldiv_a : ALL_ONES;
                                done_reg <= 1'b1;
                                state <= S_DONE;
                            end else if (start_div_overflow) begin
                                result_reg <= start_div_sel_rem ? {`XLEN{1'b0}} : SIGN_MIN;
                                done_reg <= 1'b1;
                                state <= S_DONE;
                            end else begin
                                div_sel_rem <= start_div_sel_rem;
                                div_sign_q <= start_div_signed &&
                                              (muldiv_a[`XLEN-1] ^ muldiv_b[`XLEN-1]);
                                div_sign_r <= start_div_signed && muldiv_a[`XLEN-1];
                                div_divisor_abs <= start_divisor_abs;
                                div_quot <= start_dividend_abs;
                                div_rem <= 34'sd0;
                                div_count <= 6'd0;
                                state <= S_DIV_RUN;
                            end
                        end
                    end
                end
                S_MUL_PP: begin
                    for (idx = 0; idx < NUM_PP; idx = idx + 1) begin
                        mul_pp[idx] <= pp_comb[idx];
                    end
                    state <= S_MUL_CSA;
                end
                S_MUL_CSA: begin
                    mul_sum <= csa_sum_comb;
                    mul_carry <= csa_carry_comb;
                    state <= S_MUL_ADD;
                end
                S_MUL_ADD: begin
                    logic [63:0] product_unsigned;
                    logic [63:0] product_final;
                    product_unsigned = mul_product_add;
                    if (mul_signfix && mul_neg_reg) begin
                        product_final = ~product_unsigned + 64'd1;
                    end else begin
                        product_final = product_unsigned;
                    end
                    result_reg <= mul_sel_high ? product_final[63:32] :
                                                product_final[31:0];
                    done_reg <= 1'b1;
                    state <= S_DONE;
                end
                S_DIV_RUN: begin
                    div_rem <= div_rem_next;
                    div_quot <= div_quot_next;
                    div_count <= div_count + 6'd1;
                    if (div_count == 6'd31) begin
                        result_reg <= div_sel_rem ? div_rem_final_next :
                                                    div_quot_final_next;
                        done_reg <= 1'b1;
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    assign muldiv_busy         = (state != S_IDLE);
    assign muldiv_done         = done_reg;
    assign muldiv_result       = result_reg;
    assign muldiv_done_hart_id = done_hart_id_reg;
    assign muldiv_done_rd      = done_rd_reg;
endmodule
