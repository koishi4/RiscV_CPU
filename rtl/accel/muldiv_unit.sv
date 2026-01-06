`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module muldiv_unit(
    input  logic clk,
    input  logic rst_n,
    `MULDIV_REQ_PORTS(input, muldiv),
    `MULDIV_RSP_PORTS(output, muldiv)
);
    // 约定：仅在 busy=0 时接受 start；busy=1 时的 start 被忽略。

    localparam int NUM_PP = 17; // Booth Radix-4 部分积数量（32bit -> 17 组）
    localparam [`XLEN-1:0] ALL_ONES = {`XLEN{1'b1}}; // 0xFFFF_FFFF
    localparam [`XLEN-1:0] SIGN_MIN = {1'b1, {(`XLEN-1){1'b0}}}; // 0x8000_0000

    // 状态机：两拍乘法（TREE/FINAL）+ 迭代除法（DIV_RUN）。
    typedef enum logic [2:0] {
        S_IDLE      = 3'd0,
        S_MUL_TREE  = 3'd1,
        S_MUL_FINAL = 3'd2,
        S_DIV_RUN   = 3'd3
    } state_t;

    state_t state; // 当前状态机状态

    logic [`XLEN-1:0] result_reg;         // 结果寄存器（写回数据）
    logic [`HART_ID_W-1:0] done_hart_id_reg; // 完成时对应的 hart_id
    logic [`REG_ADDR_W-1:0] done_rd_reg;  // 完成时对应的 rd
    logic done_reg;                       // 完成脉冲寄存器

    // 乘法相关状态寄存。
    // mul_sum/mul_carry 为压缩树输出寄存，供下一拍 CPA 收敛。
    logic [`XLEN-1:0] mul_a_mag_reg; // 乘数 A 的绝对值
    logic [`XLEN-1:0] mul_b_mag_reg; // 乘数 B 的绝对值
    logic mul_sel_high;              // 是否选择高 32 位（MULH/MULHU/MULHSU）
    logic mul_signfix;               // 是否需要符号修正（signed 乘法）
    logic mul_neg_reg;               // 结果是否取负
    logic [63:0] mul_sum;            // 压缩树 sum 寄存
    logic [63:0] mul_carry;          // 压缩树 carry 寄存（已左移）

    // 除法相关状态寄存。
    // div_shift 控制迭代步数，div_rem_u/div_quot 为中间余数/商。
    logic div_sel_rem;           // 选择输出 REM 还是 QUOT
    logic div_sign_q;            // 商是否需要符号修正
    logic div_sign_r;            // 余数是否需要符号修正
    logic [`XLEN-1:0] div_quot;  // 当前商（无符号）
    logic [63:0] div_rem_u;      // 当前余数（无符号，扩展 64 位）
    logic [63:0] div_divisor_u;  // 除数（无符号，扩展 64 位）
    logic [5:0] div_shift;       // 当前位对齐 shift（迭代次数）

    // 乘法组合逻辑：部分积 + 压缩树 + 最终加法。
    logic [63:0] pp_comb [0:NUM_PP-1]; // Booth 部分积数组
    logic [63:0] tree_sum_comb;        // 压缩树 sum 输出
    logic [63:0] tree_carry_comb;      // 压缩树 carry 输出
    logic [63:0] mul_product_add;      // 最终加法器输出（64-bit）

    // 除法组合逻辑：非恢复迭代与结果修正。
    logic [63:0] div_rem_next_u;        // 下一拍余数
    logic [`XLEN-1:0] div_quot_next_u;  // 下一拍商
    logic [5:0] div_shift_next_u;       // 下一拍 shift
    logic div_done_next;                // 是否完成标志
    logic [`XLEN-1:0] div_quot_final_next; // 符号修正后的最终商
    logic [`XLEN-1:0] div_rem_final_next;  // 符号修正后的最终余数

    wire op_is_mul = (muldiv_op == `MULDIV_OP_MUL) ||
                     (muldiv_op == `MULDIV_OP_MULH) ||
                     (muldiv_op == `MULDIV_OP_MULHU) ||
                     (muldiv_op == `MULDIV_OP_MULHSU);

    wire op_is_div = (muldiv_op == `MULDIV_OP_DIV) ||
                     (muldiv_op == `MULDIV_OP_DIVU) ||
                     (muldiv_op == `MULDIV_OP_REM) ||
                     (muldiv_op == `MULDIV_OP_REMU);

    wire mul_a_zero = (muldiv_a == {`XLEN{1'b0}}); // A == 0
    wire mul_b_zero = (muldiv_b == {`XLEN{1'b0}}); // B == 0
    wire mul_a_one = (muldiv_a == 32'd1);         // A == 1
    wire mul_b_one = (muldiv_b == 32'd1);         // B == 1
    wire mul_a_neg_one = (muldiv_a == ALL_ONES);  // A == -1
    wire mul_b_neg_one = (muldiv_b == ALL_ONES);  // B == -1
    wire [`XLEN-1:0] mul_neg_a = ~muldiv_a + 32'd1; // -A
    wire [`XLEN-1:0] mul_neg_b = ~muldiv_b + 32'd1; // -B

    logic mul_fast_valid;              // 乘法快路径是否命中
    logic [`XLEN-1:0] mul_fast_result; // 乘法快路径输出

    // 乘法快路径：0/1/-1 等特殊值直接给结果。
    always_comb begin
        mul_fast_valid = 1'b0;
        mul_fast_result = {`XLEN{1'b0}};
        case (muldiv_op)
            `MULDIV_OP_MUL: begin
                if (mul_a_zero || mul_b_zero) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = {`XLEN{1'b0}};
                end else if (mul_a_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = muldiv_b;
                end else if (mul_b_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = muldiv_a;
                end else if (mul_a_neg_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = mul_neg_b;
                end else if (mul_b_neg_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = mul_neg_a;
                end
            end
            `MULDIV_OP_MULH: begin
                if (mul_a_zero || mul_b_zero) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = {`XLEN{1'b0}};
                end else if (mul_a_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = muldiv_b[`XLEN-1] ? ALL_ONES : {`XLEN{1'b0}};
                end else if (mul_b_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = muldiv_a[`XLEN-1] ? ALL_ONES : {`XLEN{1'b0}};
                end else if (mul_a_neg_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = mul_neg_b[`XLEN-1] ? ALL_ONES : {`XLEN{1'b0}};
                end else if (mul_b_neg_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = mul_neg_a[`XLEN-1] ? ALL_ONES : {`XLEN{1'b0}};
                end
            end
            `MULDIV_OP_MULHU: begin
                if (mul_a_zero || mul_b_zero) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = {`XLEN{1'b0}};
                end else if (mul_a_one || mul_b_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = {`XLEN{1'b0}};
                end else if (mul_a_neg_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = (muldiv_b == {`XLEN{1'b0}}) ? {`XLEN{1'b0}} :
                                      (muldiv_b - 32'd1);
                end else if (mul_b_neg_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = (muldiv_a == {`XLEN{1'b0}}) ? {`XLEN{1'b0}} :
                                      (muldiv_a - 32'd1);
                end
            end
            `MULDIV_OP_MULHSU: begin
                if (mul_a_zero || mul_b_zero) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = {`XLEN{1'b0}};
                end else if (mul_b_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = muldiv_a[`XLEN-1] ? ALL_ONES : {`XLEN{1'b0}};
                end else if (mul_a_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = {`XLEN{1'b0}};
                end else if (mul_a_neg_one) begin
                    mul_fast_valid = 1'b1;
                    mul_fast_result = (muldiv_b == {`XLEN{1'b0}}) ? {`XLEN{1'b0}} : ALL_ONES;
                end else if (mul_b_neg_one) begin
                    mul_fast_valid = 1'b1;
                    if (muldiv_a[`XLEN-1]) begin
                        mul_fast_result = muldiv_a;
                    end else if (muldiv_a == {`XLEN{1'b0}}) begin
                        mul_fast_result = {`XLEN{1'b0}};
                    end else begin
                        mul_fast_result = muldiv_a - 32'd1;
                    end
                end
            end
            default: begin
                mul_fast_valid = 1'b0;
                mul_fast_result = {`XLEN{1'b0}};
            end
        endcase
    end

    // 除法输入准备：符号、特殊值判断。
    wire start_div_signed = (muldiv_op == `MULDIV_OP_DIV) ||
                            (muldiv_op == `MULDIV_OP_REM);
    wire start_div_sel_rem = (muldiv_op == `MULDIV_OP_REM) ||
                             (muldiv_op == `MULDIV_OP_REMU);
    wire start_div_zero = (muldiv_b == {`XLEN{1'b0}}); // 除数为 0
    wire start_div_overflow = start_div_signed &&
                              (muldiv_a == SIGN_MIN) &&
                              (muldiv_b == ALL_ONES);
    // 除法输入绝对值（signed 时取反+1）
    wire [`XLEN-1:0] start_dividend_abs =
        start_div_signed && muldiv_a[`XLEN-1] ? (~muldiv_a + 32'd1) : muldiv_a;
    wire [`XLEN-1:0] start_divisor_abs =
        start_div_signed && muldiv_b[`XLEN-1] ? (~muldiv_b + 32'd1) : muldiv_b;

    // ctz：统计最低位连续 0，用于 2^k 快路径。
    function automatic [5:0] ctz32;
        input [`XLEN-1:0] value;
        integer i;
        begin
            ctz32 = 6'd0;
            for (i = 0; i < `XLEN; i = i + 1) begin
                if (value[i]) begin
                    ctz32 = i[5:0];
                end
            end
        end
    endfunction

    // lzc：统计最高位连续 0，用于估计迭代次数。
    function automatic [5:0] lzc32;
        input [`XLEN-1:0] value;
        integer i;
        reg found;
        begin
            lzc32 = 6'd32;
            found = 1'b0;
            for (i = `XLEN-1; i >= 0; i = i - 1) begin
                if (!found && value[i]) begin
                    lzc32 = (`XLEN-1 - i);
                    found = 1'b1;
                end
            end
        end
    endfunction

    // 除数为 2^k 的快路径：直接移位/掩码得到商与余数。
    wire div_is_pow2 = (start_divisor_abs != {`XLEN{1'b0}}) &&
                       ((start_divisor_abs & (start_divisor_abs - 32'd1)) == {`XLEN{1'b0}});
    wire [5:0] div_pow2_k = ctz32(start_divisor_abs);           // k = log2(divisor)
    wire [`XLEN-1:0] div_pow2_mask = (32'h1 << div_pow2_k) - 32'h1; // 低 k 位掩码
    wire [`XLEN-1:0] div_pow2_quot = start_dividend_abs >> div_pow2_k; // 商
    wire [`XLEN-1:0] div_pow2_rem = start_dividend_abs & div_pow2_mask; // 余数
    wire div_pow2_sign_q = start_div_signed && (muldiv_a[`XLEN-1] ^ muldiv_b[`XLEN-1]); // 商符号
    wire div_pow2_sign_r = start_div_signed && muldiv_a[`XLEN-1]; // 余数符号
    wire [`XLEN-1:0] div_pow2_quot_signed =
        div_pow2_sign_q ? (~div_pow2_quot + 32'd1) : div_pow2_quot;
    wire [`XLEN-1:0] div_pow2_rem_signed =
        div_pow2_sign_r ? (~div_pow2_rem + 32'd1) : div_pow2_rem;

    // lzc 用于估算 msb，控制 div_shift_init 的初始值。
    wire [5:0] lzc_a = lzc32(start_dividend_abs); // A 的 leading zeros
    wire [5:0] lzc_b = lzc32(start_divisor_abs);  // B 的 leading zeros
    wire [5:0] msb_a = (start_dividend_abs == {`XLEN{1'b0}}) ? 6'd0 : (6'd31 - lzc_a);
    wire [5:0] msb_b = (start_divisor_abs == {`XLEN{1'b0}}) ? 6'd0 : (6'd31 - lzc_b);
    wire div_a_lt_b = (start_dividend_abs < start_divisor_abs); // |A| < |B|
    wire [5:0] div_shift_init = msb_a - msb_b; // 最高位对齐后的初始 shift

    // Booth 编码部分积生成（Radix-4）。
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

    // 3:2 压缩（carry 左移 1bit），便于 CPA 直接相加。
    function automatic [127:0] csa3_shift;
        input [63:0] a;
        input [63:0] b;
        input [63:0] c;
        reg [63:0] sum;
        reg [63:0] carry;
        begin
            sum = a ^ b ^ c;
            carry = (a & b) | (a & c) | (b & c);
            csa3_shift = { (carry << 1), sum };
        end
    endfunction

    // 单步迭代：更新余数与商位。
    function automatic [95:0] div_step;
        input [63:0] rem_in;
        input [`XLEN-1:0] quot_in;
        input [5:0] shift_in;
        input [63:0] divisor_in;
        reg [63:0] divisor_shifted;
        reg [63:0] rem_out;
        reg [`XLEN-1:0] quot_out;
        begin
            divisor_shifted = divisor_in << shift_in;
            rem_out = rem_in;
            quot_out = quot_in;
            if (rem_in >= divisor_shifted) begin
                rem_out = rem_in - divisor_shifted;
                quot_out = quot_in | (32'h1 << shift_in);
            end
            div_step = {rem_out, quot_out};
        end
    endfunction

    // 生成 Booth 部分积：pp_comb[idx] 对应第 idx 组编码。
    // 每组取 B 的 3-bit 窗口，生成 0/A/2A/-A/-2A 的部分积，并左移对齐。
    always_comb begin
        int idx;
        logic [32:0] a_ext;
        logic [32:0] b_ext;
        logic [34:0] b_booth;
        logic [2:0] booth_bits;
        logic signed [34:0] pp_raw;
        logic signed [63:0] pp_ext;

        a_ext = {1'b0, mul_a_mag_reg}; // A 扩展为 33 位（防止 x2 时溢出）
        b_ext = {1'b0, mul_b_mag_reg};
        b_booth = {b_ext[32], b_ext, 1'b0}; // B 扩展为 35 位

        // booth_bits 取 b_booth 的 3-bit 编码，pp_raw 为带符号部分积。
        for (idx = 0; idx < NUM_PP; idx = idx + 1) begin
            booth_bits = b_booth[2*idx+2 -: 3]; // 1. 滑动窗口采样
            pp_raw = booth_partial(booth_bits, a_ext); // 2. 生成当前行的基础值 (0, A, 2A, -A, -2A)
            pp_ext = {{(64-35){pp_raw[34]}}, pp_raw}; // 3. 符号扩展至 64 位
            pp_comb[idx] = pp_ext <<< (2*idx); // 4. 移位对齐 (Shift)
        end
    end

    // 压缩树层级：l0~l4 逐层压缩到 2 行。
    // 每级把 3 行压缩成 2 行，最后得到 tree_sum/tree_carry。
    always_comb begin
        logic [63:0] l0 [0:11];
        logic [63:0] l1 [0:7];
        logic [63:0] l2 [0:5];
        logic [63:0] l3 [0:3];
        logic [63:0] l4 [0:2];

        {l0[1], l0[0]} = csa3_shift(pp_comb[0], pp_comb[1], pp_comb[2]);
        {l0[3], l0[2]} = csa3_shift(pp_comb[3], pp_comb[4], pp_comb[5]);
        {l0[5], l0[4]} = csa3_shift(pp_comb[6], pp_comb[7], pp_comb[8]);
        {l0[7], l0[6]} = csa3_shift(pp_comb[9], pp_comb[10], pp_comb[11]);
        {l0[9], l0[8]} = csa3_shift(pp_comb[12], pp_comb[13], pp_comb[14]);
        l0[10] = pp_comb[15];
        l0[11] = pp_comb[16];

        {l1[1], l1[0]} = csa3_shift(l0[0], l0[1], l0[2]);
        {l1[3], l1[2]} = csa3_shift(l0[3], l0[4], l0[5]);
        {l1[5], l1[4]} = csa3_shift(l0[6], l0[7], l0[8]);
        {l1[7], l1[6]} = csa3_shift(l0[9], l0[10], l0[11]);

        {l2[1], l2[0]} = csa3_shift(l1[0], l1[1], l1[2]);
        {l2[3], l2[2]} = csa3_shift(l1[3], l1[4], l1[5]);
        l2[4] = l1[6];
        l2[5] = l1[7];

        {l3[1], l3[0]} = csa3_shift(l2[0], l2[1], l2[2]);
        {l3[3], l3[2]} = csa3_shift(l2[3], l2[4], l2[5]);

        {l4[1], l4[0]} = csa3_shift(l3[0], l3[1], l3[2]);
        l4[2] = l3[3];

        {tree_carry_comb, tree_sum_comb} = csa3_shift(l4[0], l4[1], l4[2]);
    end

    // 末端 CPA：sum + carry（carry 已左移）。
    assign mul_product_add = mul_sum + mul_carry;

    // 除法两步迭代组合逻辑：每拍做 2 次 div_step。
    // 若 shift 为 0/1，则本拍结束并置 div_done_next。
    always_comb begin
        logic [63:0] rem1;
        logic [`XLEN-1:0] quot1;
        logic [63:0] rem2;
        logic [`XLEN-1:0] quot2;

        div_rem_next_u = div_rem_u;
        div_quot_next_u = div_quot;
        div_shift_next_u = div_shift;
        div_done_next = 1'b0;

        {rem1, quot1} = div_step(div_rem_u, div_quot, div_shift, div_divisor_u);
        if (div_shift == 6'd0) begin
            div_rem_next_u = rem1;
            div_quot_next_u = quot1;
            div_done_next = 1'b1;
        end else begin
            {rem2, quot2} = div_step(rem1, quot1, div_shift - 6'd1, div_divisor_u);
            div_rem_next_u = rem2;
            div_quot_next_u = quot2;
            if (div_shift == 6'd1) begin
                div_done_next = 1'b1;
            end else begin
                div_shift_next_u = div_shift - 6'd2;
            end
        end

        div_quot_final_next = div_sign_q ? (~div_quot_next_u + 32'd1) : div_quot_next_u;
        div_rem_final_next = div_sign_r ?
                             (~div_rem_next_u[`XLEN-1:0] + 32'd1) :
                             div_rem_next_u[`XLEN-1:0];
    end

    // 主状态机：S_IDLE 接收 start；乘法/除法完成后回到 IDLE。
    always_ff @(posedge clk or negedge rst_n) begin
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
            mul_sum <= 64'b0;
            mul_carry <= 64'b0;

            div_sel_rem <= 1'b0;
            div_sign_q <= 1'b0;
            div_sign_r <= 1'b0;
            div_quot <= {`XLEN{1'b0}};
            div_rem_u <= 64'd0;
            div_divisor_u <= 64'd0;
            div_shift <= 6'd0;
        end else begin
            done_reg <= 1'b0;
            case (state)
                // 空闲态：等待 start，并锁存 rd/hart 等信息。
                S_IDLE: begin
                    if (muldiv_start) begin
                        done_hart_id_reg <= muldiv_hart_id;
                        done_rd_reg <= muldiv_rd;
                        if (op_is_mul) begin
                            // 乘法路径：先做符号处理，再进入 TREE/FINAL 两拍。
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
                            // 乘法快路径：无需进入多拍状态。
                            if (mul_fast_valid) begin
                                result_reg <= mul_fast_result;
                                done_reg <= 1'b1;
                                state <= S_IDLE;
                            end else begin
                                state <= S_MUL_TREE;
                            end
                        end else if (op_is_div) begin
                            // 除法路径：优先走快路径（除 0/溢出/2^k/a<b）。
                            if (start_div_zero) begin
                                result_reg <= start_div_sel_rem ? muldiv_a : ALL_ONES;
                                done_reg <= 1'b1;
                                state <= S_IDLE;
                            end else if (start_div_overflow) begin
                                result_reg <= start_div_sel_rem ? {`XLEN{1'b0}} : SIGN_MIN;
                                done_reg <= 1'b1;
                                state <= S_IDLE;
                            end else if (div_is_pow2) begin
                                result_reg <= start_div_sel_rem ?
                                              div_pow2_rem_signed :
                                              div_pow2_quot_signed;
                                done_reg <= 1'b1;
                                state <= S_IDLE;
                            end else begin
                                // 设置符号与输出类型（商/余数）
                                div_sel_rem <= start_div_sel_rem;
                                div_sign_q <= start_div_signed &&
                                              (muldiv_a[`XLEN-1] ^ muldiv_b[`XLEN-1]);
                                div_sign_r <= start_div_signed && muldiv_a[`XLEN-1];
                                if (div_a_lt_b) begin
                                    // |A| < |B|：商为 0，余数为 A（符号修正后）
                                    result_reg <= start_div_sel_rem ?
                                                  (start_div_signed && muldiv_a[`XLEN-1] ?
                                                   (~start_dividend_abs + 32'd1) :
                                                   start_dividend_abs) :
                                                  {`XLEN{1'b0}};
                                    done_reg <= 1'b1;
                                    state <= S_IDLE;
                                end else begin
                                    // 初始化除法迭代寄存器
                                    div_divisor_u <= {32'd0, start_divisor_abs};
                                    div_rem_u <= {32'd0, start_dividend_abs};
                                    div_quot <= {`XLEN{1'b0}};
                                    div_shift <= div_shift_init;
                                    state <= S_DIV_RUN;
                                end
                            end
                        end
                    end
                end
                // 乘法第 1 拍：压缩树输出寄存。
                S_MUL_TREE: begin
                    mul_sum <= tree_sum_comb;
                    mul_carry <= tree_carry_comb;
                    state <= S_MUL_FINAL;
                end
                // 乘法第 2 拍：CPA 收敛 + 符号修正 + 写结果。
                S_MUL_FINAL: begin
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
                    state <= S_IDLE;
                end
                // 除法迭代：每拍 2 步，直到 div_done_next。
                S_DIV_RUN: begin
                    div_rem_u <= div_rem_next_u; // 锁存经过两轮计算后的余数
                    div_quot <= div_quot_next_u; // 锁存经过两轮计算后的商
                    div_shift <= div_shift_next_u; // 锁存减了 2 之后的计数器
                    if (div_done_next) begin
                        result_reg <= div_sel_rem ? div_rem_final_next :
                                                    div_quot_final_next;
                        done_reg <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // 输出握手：busy 表示单元占用，done 为单周期脉冲。
    assign muldiv_busy         = (state != S_IDLE);
    assign muldiv_done         = done_reg;
    assign muldiv_result       = result_reg;
    assign muldiv_done_hart_id = done_hart_id_reg;
    assign muldiv_done_rd      = done_rd_reg;
endmodule
