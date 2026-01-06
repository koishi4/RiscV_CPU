`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module dma_engine #(
    parameter integer DMA_GAP_CYCLES = 0
)(
    input  clk,
    input  rst_n,
    `MMIO_REQ_PORTS(input, mmio),
    `MMIO_RSP_PORTS(output, mmio),
    `MEM_REQ_PORTS(output, dma_mem),
    `MEM_RSP_PORTS(input, dma_mem),
    output dma_irq
);
    // DMA 引擎：MMIO 配置 + FSM 复制（读->写），支持可选 gap 延迟。
    // 约定：MMIO 只支持 32-bit 写；busy 时的 start 被忽略。

    localparam [`ADDR_W-1:0] DMA_SRC_ADDR  = `DMA_BASE_ADDR + `DMA_SRC_OFFSET;
    localparam [`ADDR_W-1:0] DMA_DST_ADDR  = `DMA_BASE_ADDR + `DMA_DST_OFFSET;
    localparam [`ADDR_W-1:0] DMA_LEN_ADDR  = `DMA_BASE_ADDR + `DMA_LEN_OFFSET;
    localparam [`ADDR_W-1:0] DMA_CTRL_ADDR = `DMA_BASE_ADDR + `DMA_CTRL_OFFSET;
    localparam [`ADDR_W-1:0] DMA_STAT_ADDR = `DMA_BASE_ADDR + `DMA_STAT_OFFSET;
    localparam [`ADDR_W-1:0] DMA_CLR_ADDR  = `DMA_BASE_ADDR + `DMA_CLR_OFFSET;

    // FSM 状态：READ 取数 -> WRITE 写回，中间可插入 gap。
    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_READ      = 3'd1;
    localparam [2:0] STATE_READ_GAP  = 3'd2;
    localparam [2:0] STATE_WRITE     = 3'd3;
    localparam [2:0] STATE_WRITE_GAP = 3'd4;

    localparam integer DMA_GAP_INIT = (DMA_GAP_CYCLES > 0) ? (DMA_GAP_CYCLES - 1) : 0;

    reg [2:0] state;       // FSM 当前状态。
    reg [2:0] state_n;     // FSM 下一状态（组合逻辑）。
    reg read_req_d;        // READ 请求打一拍，用于与 ready 对齐。
    reg write_req_d;       // WRITE 请求打一拍，用于与 ready 对齐。

    // MMIO 寄存器影子：SRC/DST/LEN/CTRL/STAT。
    reg [`ADDR_W-1:0] src_reg;         // DMA_SRC：源地址寄存器影子。
    reg [`ADDR_W-1:0] dst_reg;         // DMA_DST：目的地址寄存器影子。
    reg [`XLEN-1:0]   len_reg;         // DMA_LEN：剩余长度（字节）。
    reg              irq_en_reg;       // DMA_CTRL.IRQ_EN 位影子。
    reg              done_reg;         // DMA_STAT.DONE 置位（完成）。
    reg              err_reg;          // DMA_STAT.ERR 置位（参数错误）。
    reg              irq_pending_reg;  // 外部中断 pending（DONE 且 IRQ_EN）。

    // 运行时寄存：当前 src/dst/len 与读出的数据。
    reg [`ADDR_W-1:0] cur_src;    // 运行时源地址游标。
    reg [`ADDR_W-1:0] cur_dst;    // 运行时目的地址游标。
    reg [`XLEN-1:0]   cur_len;    // 运行时剩余长度。
    reg [`XLEN-1:0]   read_data;  // 最近一次读回的数据缓冲。

    reg [`XLEN-1:0]   mmio_rdata_reg; // MMIO 读数据寄存器（读请求锁存）。

    reg [`ADDR_W-1:0] src_reg_n;        // src_reg 的下一值。
    reg [`ADDR_W-1:0] dst_reg_n;        // dst_reg 的下一值。
    reg [`XLEN-1:0]   len_reg_n;        // len_reg 的下一值。
    reg              irq_en_reg_n;      // irq_en_reg 的下一值。
    reg              done_reg_n;        // done_reg 的下一值。
    reg              err_reg_n;         // err_reg 的下一值。
    reg              irq_pending_reg_n; // irq_pending_reg 的下一值。

    reg [`ADDR_W-1:0] cur_src_n;   // cur_src 的下一值。
    reg [`ADDR_W-1:0] cur_dst_n;   // cur_dst 的下一值。
    reg [`XLEN-1:0]   cur_len_n;   // cur_len 的下一值。
    reg [`XLEN-1:0]   read_data_n; // read_data 的下一值。
    reg [31:0]        gap_cnt;     // gap 计数器当前值。
    reg [31:0]        gap_cnt_n;   // gap 计数器下一值。

    // MMIO 单拍握手缓存：把 req 锁存到 pending，再在下一拍执行。
    reg mmio_pending;          // MMIO 请求已锁存，等待下一拍执行。
    reg mmio_we_d;             // 锁存的写使能。
    reg [`ADDR_W-1:0] mmio_addr_d;  // 锁存的地址。
    reg [`XLEN-1:0] mmio_wdata_d;   // 锁存的写数据。
    wire mmio_accept = mmio_req && !mmio_pending; // 接收新请求。
    wire mmio_fire = mmio_pending;                // 执行已锁存请求。
    wire mmio_wr = mmio_fire && mmio_we_d;        // 执行写操作。
    wire mmio_rd = mmio_fire && !mmio_we_d;       // 执行读操作。

    // 写 CTRL.START 触发 DMA（busy 时忽略）。
    wire start_pulse = mmio_wr &&
                       (mmio_addr_d == DMA_CTRL_ADDR) &&
                       mmio_wdata_d[`DMA_CTRL_START_BIT];

    // busy 反映 FSM 是否在执行复制。
    wire busy = (state != STATE_IDLE); // DMA 处于工作态。

    // ERR 条件：未对齐或访问到 DMA MMIO 地址区间。
    wire addr_unaligned = (src_reg[1:0] != 2'b00) || (dst_reg[1:0] != 2'b00); // 地址未字对齐。
    wire len_unaligned  = (len_reg[1:0] != 2'b00);                            // 长度未 4B 对齐。
    wire src_hits_mmio  = ((src_reg & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);    // 源地址落在 DMA MMIO 区间。
    wire dst_hits_mmio  = ((dst_reg & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);    // 目的地址落在 DMA MMIO 区间。
    wire bad_param = addr_unaligned || len_unaligned || src_hits_mmio || dst_hits_mmio; // 参数非法。

    // 读/写请求的 ready 只在对应阶段有效。
    wire mem_ready_read = dma_mem_ready && read_req_d;   // READ 阶段的 ready。
    wire mem_ready_write = dma_mem_ready && write_req_d; // WRITE 阶段的 ready。

    always @(*) begin
        // 默认保持：先用当前值做默认赋值，避免组合逻辑产生锁存。
        state_n = state;
        src_reg_n = src_reg;
        dst_reg_n = dst_reg;
        len_reg_n = len_reg;
        irq_en_reg_n = irq_en_reg;
        done_reg_n = done_reg;
        err_reg_n = err_reg;
        irq_pending_reg_n = irq_pending_reg;
        cur_src_n = cur_src;
        cur_dst_n = cur_dst;
        cur_len_n = cur_len;
        read_data_n = read_data;
        gap_cnt_n = gap_cnt;

        // MMIO 写：更新配置/控制/清除状态（写 CTRL 只更新 IRQ_EN）。
        if (mmio_wr) begin
            if (mmio_addr_d == DMA_SRC_ADDR) begin
                // DMA_SRC：源地址
                src_reg_n = mmio_wdata_d;
            end else if (mmio_addr_d == DMA_DST_ADDR) begin
                // DMA_DST：目的地址
                dst_reg_n = mmio_wdata_d;
            end else if (mmio_addr_d == DMA_LEN_ADDR) begin
                // DMA_LEN：长度（字节）
                len_reg_n = mmio_wdata_d;
            end else if (mmio_addr_d == DMA_CTRL_ADDR) begin
                // DMA_CTRL：仅使用 IRQ_EN 位，START 由 start_pulse 处理
                irq_en_reg_n = mmio_wdata_d[`DMA_CTRL_IRQ_EN_BIT];
            end else if (mmio_addr_d == DMA_CLR_ADDR) begin
                // DMA_CLR：写 1 清 DONE/ERR
                if (mmio_wdata_d[`DMA_CLR_DONE_BIT]) begin
                    done_reg_n = 1'b0;
                    irq_pending_reg_n = 1'b0;
                end
                if (mmio_wdata_d[`DMA_CLR_ERR_BIT]) begin
                    err_reg_n = 1'b0;
                end
            end
        end

        // start：锁存运行时寄存并进入 READ（busy 时忽略）。
        if (start_pulse && !busy) begin
            // 起始参数快照：避免运行中被 MMIO 改写
            cur_src_n = src_reg;
            cur_dst_n = dst_reg;
            cur_len_n = len_reg;
            if (len_reg == {`XLEN{1'b0}}) begin
                // 长度为 0：直接 DONE（不触发 DMA 访问）
                done_reg_n = 1'b1;
            end else if (bad_param) begin
                // 参数非法：DONE+ERR
                done_reg_n = 1'b1;
                err_reg_n = 1'b1;
            end else begin
                // 进入读阶段，开始复制
                state_n = STATE_READ;
            end
        end

        case (state)
            STATE_IDLE: begin
            end
            STATE_READ: begin
                // 读阶段：发起一次读，等待 mem_ready_read。
                if (mem_ready_read) begin // 等待内存传回数据
                    read_data_n = dma_mem_rdata; // 锁存读回数据
                    if (DMA_GAP_CYCLES > 0) begin // 读后 gap
                        gap_cnt_n = DMA_GAP_INIT[31:0];
                        state_n = STATE_READ_GAP;
                    end else begin
                        state_n = STATE_WRITE; // 直接进入写阶段
                    end
                end
            end
            STATE_READ_GAP: begin
                // 读后 gap（可选），用于拉开读写节拍。
                if (gap_cnt == 32'd0) begin
                    state_n = STATE_WRITE;
                end else begin
                    gap_cnt_n = gap_cnt - 32'd1;
                end
            end
            STATE_WRITE: begin
                // 写阶段：发起一次写，等待 mem_ready_write。
                if (mem_ready_write) begin
                    if (cur_len <= 32'd4) begin // 检查是否搬完
                        cur_len_n = {`XLEN{1'b0}};
                        done_reg_n = 1'b1; // 搬完Done置为1
                        state_n = STATE_IDLE;
                    end else begin
                        // 未完成：更新游标并回到 READ
                        cur_len_n = cur_len - 32'd4; // 长度减4
                        cur_src_n = cur_src + 32'd4; // 源地址加4
                        cur_dst_n = cur_dst + 32'd4; // 目的地址加4
                        if (DMA_GAP_CYCLES > 0) begin 
                            gap_cnt_n = DMA_GAP_INIT[31:0];
                            state_n = STATE_WRITE_GAP;
                        end else begin
                            state_n = STATE_READ; // 回去读下一个
                        end
                    end
                end
            end
            STATE_WRITE_GAP: begin
                // 写后 gap（可选），用于拉开写->读节拍。
                if (gap_cnt == 32'd0) begin
                    state_n = STATE_READ;
                end else begin
                    gap_cnt_n = gap_cnt - 32'd1;
                end
            end
            default: begin
                state_n = STATE_IDLE;
            end
        endcase

        // DONE 且 IRQ_EN 时置中断 pending（保持到 CLR 清除）。
        if (done_reg_n && irq_en_reg_n) begin
            irq_pending_reg_n = 1'b1;
        end
    end

    // 时序寄存：状态/寄存器/握手缓存。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            read_req_d <= 1'b0;
            write_req_d <= 1'b0;
            mmio_pending <= 1'b0;
            mmio_we_d <= 1'b0;
            mmio_addr_d <= {`ADDR_W{1'b0}};
            mmio_wdata_d <= {`XLEN{1'b0}};
            src_reg <= {`ADDR_W{1'b0}};
            dst_reg <= {`ADDR_W{1'b0}};
            len_reg <= {`XLEN{1'b0}};
            irq_en_reg <= 1'b0;
            done_reg <= 1'b0;
            err_reg <= 1'b0;
            irq_pending_reg <= 1'b0;
            cur_src <= {`ADDR_W{1'b0}};
            cur_dst <= {`ADDR_W{1'b0}};
            cur_len <= {`XLEN{1'b0}};
            read_data <= {`XLEN{1'b0}};
            gap_cnt <= 32'd0;
        end else begin
            // 读/写请求打一拍，和同步内存 ready 对齐。
            read_req_d <= (state == STATE_READ);
            write_req_d <= (state == STATE_WRITE);
            // MMIO 请求锁存：先 accept，再下一拍 fire。
            if (mmio_accept) begin
                mmio_pending <= 1'b1;     // 标记挂起
                mmio_we_d <= mmio_we;     // 锁存写使能
                mmio_addr_d <= mmio_addr; // 锁存地址
                mmio_wdata_d <= mmio_wdata; // 锁存写数据
            end else if (mmio_fire) begin
                mmio_pending <= 1'b0;     // 请求已执行
            end
            // 寄存器/状态更新（使用 *_n 下一值）。
            state <= state_n;
            src_reg <= src_reg_n;
            dst_reg <= dst_reg_n;
            len_reg <= len_reg_n;
            irq_en_reg <= irq_en_reg_n;
            done_reg <= done_reg_n;
            err_reg <= err_reg_n;
            irq_pending_reg <= irq_pending_reg_n;
            cur_src <= cur_src_n;
            cur_dst <= cur_dst_n;
            cur_len <= cur_len_n;
            read_data <= read_data_n;
            gap_cnt <= gap_cnt_n;
        end
    end

    // MMIO 读数据寄存：读请求在 accept 当拍锁存，返回在 fire 时送出。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_rdata_reg <= {`XLEN{1'b0}};
        end else if (mmio_accept && !mmio_we) begin
            // 读地址解码：返回当前寄存器值或状态。
            if (mmio_addr == DMA_SRC_ADDR) begin
                mmio_rdata_reg <= src_reg;
            end else if (mmio_addr == DMA_DST_ADDR) begin
                mmio_rdata_reg <= dst_reg;
            end else if (mmio_addr == DMA_LEN_ADDR) begin
                mmio_rdata_reg <= len_reg;
            end else if (mmio_addr == DMA_CTRL_ADDR) begin
                mmio_rdata_reg <= {30'b0, irq_en_reg, 1'b0};
            end else if (mmio_addr == DMA_STAT_ADDR) begin
                mmio_rdata_reg <= {29'b0, err_reg, done_reg, busy};
            end else begin
                mmio_rdata_reg <= {`XLEN{1'b0}};
            end
        end
    end

    // MMIO 响应：fire 表示完成一次请求。
    assign mmio_rdata = mmio_rdata_reg;
    assign mmio_ready = mmio_fire;

    // DMA -> 内存接口：
    // - READ 状态发起读请求，地址为 cur_src。
    // - WRITE 状态发起写请求，地址为 cur_dst，写数据为 read_data。
    assign dma_mem_req = (state == STATE_READ) || (state == STATE_WRITE);
    assign dma_mem_we = (state == STATE_WRITE);
    assign dma_mem_addr = (state == STATE_READ) ? cur_src :
                          (state == STATE_WRITE) ? cur_dst : {`ADDR_W{1'b0}};
    assign dma_mem_wdata = read_data;

    // 中断输出：DONE 且 IRQ_EN 后保持，直到 CLR 清除。
    assign dma_irq = irq_pending_reg;
endmodule
