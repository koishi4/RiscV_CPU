`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module led_uart_mmio #(
    parameter integer UART_DIV = `UART_DIV,
    parameter BTN_ACTIVE_LOW = 1'b1,     // 按键输入是否为低有效（板级约束相关）
    parameter SW_ACTIVE_LOW = 1'b0,      // 开关输入是否为低有效
    parameter SEG_ACTIVE_LOW = 1'b0,     // 段选是否为低有效
    parameter SEG_AN_ACTIVE_LOW = 1'b0,  // 位选是否为低有效
    parameter [7:0] SEG_AN_ENABLE = 8'hFF, // 哪些位可用（1=使能）
    parameter SEG_SCAN_EN = 1'b1,        // 是否启用位扫描（动态扫描）
    parameter integer SEG_SCAN_DIV = 50000, // 位扫描分频
    parameter integer SEG_UPDATE_DIV = 0    // 显示值更新分频（0=每次写立即更新）
) (
    input  clk,
    input  rst_n,
    `MMIO_REQ_PORTS(input, mmio),
    `MMIO_RSP_PORTS(output, mmio),
    output [`IO_LED_WIDTH-1:0] led_out,
    output [7:0] seg0,
    output [7:0] seg1,
    output [7:0] seg_an,
    input  [4:0] btn_in,
    input  [7:0] sw_in,
    output uart_tx
);
    // LED/UART/数码管 MMIO 模块：
    // - LED_ADDR：写 LED 输出
    // - UART_TX_ADDR：写 1 字节触发 UART 发送
    // - UART_STAT_ADDR：读 UART busy 状态
    // - SEG_ADDR：写入 32-bit 显示值（8 个 nibble）
    // - BTN_ADDR：读按钮/开关输入
    // MMIO 地址映射（基地址 + 偏移）。
    localparam [`ADDR_W-1:0] LED_ADDR       = `IO_BASE_ADDR + `IO_LED_OFFSET;       // LED 寄存器
    localparam [`ADDR_W-1:0] UART_TX_ADDR   = `IO_BASE_ADDR + `IO_UART_TX_OFFSET;   // UART 发送寄存器
    localparam [`ADDR_W-1:0] UART_STAT_ADDR = `IO_BASE_ADDR + `IO_UART_STAT_OFFSET; // UART 状态寄存器
    localparam [`ADDR_W-1:0] SEG_ADDR       = `IO_BASE_ADDR + `IO_SEG_OFFSET;       // 数码管显示值寄存器
    localparam [`ADDR_W-1:0] BTN_ADDR       = `IO_BASE_ADDR + `IO_BTN_OFFSET;       // 按键/开关输入寄存器

    reg mmio_pending;              // MMIO 请求已锁存，等待执行
    reg mmio_we_d;                 // 锁存的写使能
    reg [`ADDR_W-1:0] mmio_addr_d; // 锁存的地址
    reg [`XLEN-1:0] mmio_wdata_d;  // 锁存的写数据
    wire mmio_accept = mmio_req && !mmio_pending; // 接收新请求
    wire mmio_fire = mmio_pending;                // 执行已锁存请求
    wire mmio_wr = mmio_fire && mmio_we_d;        // 执行写
    wire mmio_rd = mmio_fire && !mmio_we_d;       // 执行读
    wire uart_write = mmio_wr && (mmio_addr_d == UART_TX_ADDR); // UART 发送触发

    reg [`IO_LED_WIDTH-1:0] led_reg; // LED 输出寄存器（每位对应一个 LED）
    reg [31:0] seg_val_reg;          // 当前显示值（8 个 nibble：从 [31:28] 到 [3:0]）
    reg [31:0] seg_pending;          // 待更新的显示值（延迟生效用）
    reg [`XLEN-1:0] mmio_rdata_reg;  // MMIO 读数据寄存器（读请求锁存）

    reg uart_busy;            // UART 正在发送
    reg [9:0] uart_shift;     // UART 移位寄存器（1 停止位 + 8 数据位 + 1 起始位）
    reg [3:0] uart_bits_left; // 剩余发送位数（10->0）
    reg [15:0] uart_div_cnt;  // UART 波特率分频计数（每位维持的时钟数）
    reg [31:0] seg_scan_cnt;  // 数码管扫描分频计数（到 0 切换位）
    reg [2:0] seg_digit_idx;  // 当前显示的位索引（0-7）
    reg [31:0] seg_update_cnt; // 显示值更新分频计数（0 时更新 seg_val_reg）
    reg [7:0] seg0_reg;       // seg0 段选输出寄存器（左 4 位）
    reg [7:0] seg1_reg;       // seg1 段选输出寄存器（右 4 位）
    reg [7:0] seg_an_reg;     // 位选输出寄存器（1-hot 或单 bit）

    wire seg_scan_tick = SEG_SCAN_EN && (seg_scan_cnt == 32'd0); // 扫描到期

    wire [4:0] btn_sample = BTN_ACTIVE_LOW ? ~btn_in : btn_in; // 按键采样（极性修正）
    wire [7:0] sw_sample = SW_ACTIVE_LOW ? ~sw_in : sw_in;     // 开关采样（极性修正）

    function automatic [6:0] hex_to_seg(input [3:0] nibble);
        // 4-bit nibble -> 7 段编码（共阴极：1 表示点亮，a~g 对应 bit0~bit6）
        begin
            case (nibble)
                4'h0: hex_to_seg = 7'h3F;
                4'h1: hex_to_seg = 7'h06;
                4'h2: hex_to_seg = 7'h5B;
                4'h3: hex_to_seg = 7'h4F;
                4'h4: hex_to_seg = 7'h66;
                4'h5: hex_to_seg = 7'h6D;
                4'h6: hex_to_seg = 7'h7D;
                4'h7: hex_to_seg = 7'h07;
                4'h8: hex_to_seg = 7'h7F;
                4'h9: hex_to_seg = 7'h6F;
                4'hA: hex_to_seg = 7'h77;
                4'hB: hex_to_seg = 7'h7C;
                4'hC: hex_to_seg = 7'h39;
                4'hD: hex_to_seg = 7'h5E;
                4'hE: hex_to_seg = 7'h79;
                4'hF: hex_to_seg = 7'h71;
                default: hex_to_seg = 7'b0000000;
            endcase
        end
    endfunction

    // 主时序：MMIO 请求锁存 + LED/SEG/UART 状态机更新 + 扫描逻辑。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_reg <= {`IO_LED_WIDTH{1'b0}};
            seg_val_reg <= 32'h0000_0000;
            seg_pending <= 32'h0000_0000;
            mmio_pending <= 1'b0;
            mmio_we_d <= 1'b0;
            mmio_addr_d <= {`ADDR_W{1'b0}};
            mmio_wdata_d <= {`XLEN{1'b0}};
            uart_busy <= 1'b0;
            uart_shift <= 10'h3FF;
            uart_bits_left <= 4'd0;
            uart_div_cnt <= 16'd0;
            seg_scan_cnt <= 32'd0;
            seg_digit_idx <= 3'd0;
            seg_update_cnt <= 32'd0;
            seg0_reg <= 8'b0000_0000;
            seg1_reg <= 8'b0000_0000;
            seg_an_reg <= 8'b0000_0000;
        end else begin
            // MMIO 请求锁存
            if (mmio_accept) begin
                mmio_pending <= 1'b1;
                mmio_we_d <= mmio_we;
                mmio_addr_d <= mmio_addr;
                mmio_wdata_d <= mmio_wdata;
            end else if (mmio_fire) begin
                mmio_pending <= 1'b0;
            end

            // MMIO 写：LED / SEG
            if (mmio_wr && (mmio_addr_d == LED_ADDR)) begin
                led_reg <= mmio_wdata_d[`IO_LED_WIDTH-1:0];
            end else if (mmio_wr && (mmio_addr_d == SEG_ADDR)) begin
                seg_pending <= mmio_wdata_d;
            end

            // UART 发送：写 UART_TX_ADDR 触发一次发送。
            // 发送格式：1 start(0) + 8 data(LSB first) + 1 stop(1)。
            if (uart_write && !uart_busy) begin
                uart_shift <= {1'b1, mmio_wdata_d[7:0], 1'b0};
                uart_bits_left <= 4'd10;
                uart_div_cnt <= UART_DIV - 16'd1;
                uart_busy <= 1'b1;
            end else if (uart_busy) begin
                if (uart_div_cnt == 16'd0) begin
                    uart_shift <= {1'b1, uart_shift[9:1]};
                    if (uart_bits_left == 4'd1) begin
                        uart_bits_left <= 4'd0;
                        uart_busy <= 1'b0;
                    end else begin
                        uart_bits_left <= uart_bits_left - 1'b1;
                    end
                    uart_div_cnt <= UART_DIV - 16'd1;
                end else begin
                    uart_div_cnt <= uart_div_cnt - 1'b1;
                end
            end

            // 数码管扫描计数：控制位选轮询频率。
            // SEG_SCAN_DIV 越大，扫描越慢；SEG_SCAN_EN=0 时固定显示最低位。
            if (SEG_SCAN_EN) begin
                if (seg_scan_cnt == 32'd0) begin
                    seg_scan_cnt <= SEG_SCAN_DIV - 1;
                    seg_digit_idx <= seg_digit_idx + 1'b1;
                end else begin
                    seg_scan_cnt <= seg_scan_cnt - 1'b1;
                end
            end else begin
                seg_scan_cnt <= SEG_SCAN_DIV - 1;
                seg_digit_idx <= 3'd0;
            end

            // 显示值更新：支持写入后延迟生效。
            // SEG_UPDATE_DIV=0 -> 写 SEG_ADDR 立即更新 seg_val_reg。
            if (SEG_UPDATE_DIV == 0) begin
                if (mmio_wr && (mmio_addr_d == SEG_ADDR)) begin
                    seg_val_reg <= mmio_wdata_d;
                end
                seg_update_cnt <= 32'd0;
            end else begin
                if (seg_update_cnt == 32'd0) begin
                    seg_update_cnt <= SEG_UPDATE_DIV - 1;
                    seg_val_reg <= seg_pending;
                end else begin
                    seg_update_cnt <= seg_update_cnt - 1'b1;
                end
            end

            // 数码管段选/位选输出：按当前位索引选择 nibble。
            // 映射关系：digit0=[31:28] ... digit7=[3:0]。
            if (SEG_SCAN_EN) begin
                if (seg_scan_tick) begin
                    seg_an_reg <= 8'b0000_0000;
                    seg0_reg <= 8'b0000_0000;
                    seg1_reg <= 8'b0000_0000;
                    case (seg_digit_idx)
                        3'd0: begin
                            // digit0 -> seg0，高 4 位
                            seg_an_reg[0] <= 1'b1;
                            seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[31:28])};
                        end
                        3'd1: begin
                            // digit1
                            seg_an_reg[1] <= 1'b1;
                            seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[27:24])};
                        end
                        3'd2: begin
                            // digit2
                            seg_an_reg[2] <= 1'b1;
                            seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[23:20])};
                        end
                        3'd3: begin
                            // digit3
                            seg_an_reg[3] <= 1'b1;
                            seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[19:16])};
                        end
                        3'd4: begin
                            // digit4 -> seg1，高 4 位
                            seg_an_reg[4] <= 1'b1;
                            seg1_reg <= {1'b0, hex_to_seg(seg_val_reg[15:12])};
                        end
                        3'd5: begin
                            // digit5
                            seg_an_reg[5] <= 1'b1;
                            seg1_reg <= {1'b0, hex_to_seg(seg_val_reg[11:8])};
                        end
                        3'd6: begin
                            // digit6
                            seg_an_reg[6] <= 1'b1;
                            seg1_reg <= {1'b0, hex_to_seg(seg_val_reg[7:4])};
                        end
                        default: begin
                            // digit7（默认）
                            seg_an_reg[7] <= 1'b1;
                            seg1_reg <= {1'b0, hex_to_seg(seg_val_reg[3:0])};
                        end
                    endcase
                end
            end else begin
                seg_an_reg <= SEG_AN_ENABLE;
                seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[3:0])};
                seg1_reg <= {1'b0, hex_to_seg(seg_val_reg[7:4])};
            end
        end
    end

    // MMIO 读：在 accept 当拍锁存，ready 拉高时输出。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_rdata_reg <= {`XLEN{1'b0}};
        end else if (mmio_accept && !mmio_we) begin
            // 读地址解码：返回对应寄存器/状态。
            if (mmio_addr == LED_ADDR) begin
                // LED：低位返回 LED 状态
                mmio_rdata_reg <= {{(`XLEN-`IO_LED_WIDTH){1'b0}}, led_reg};
            end else if (mmio_addr == UART_STAT_ADDR) begin
                // UART_STAT：bit0=busy
                mmio_rdata_reg <= {31'b0, uart_busy};
            end else if (mmio_addr == SEG_ADDR) begin
                // SEG：返回 pending 显示值
                mmio_rdata_reg <= seg_pending;
            end else if (mmio_addr == BTN_ADDR) begin
                // BTN：{sw[7:0], btn[4:0]} 合并
                mmio_rdata_reg <= {19'b0, sw_sample, btn_sample};
            end else begin
                mmio_rdata_reg <= {`XLEN{1'b0}};
            end
        end
    end

    // 输出映射：LED/数码管/UART
    assign led_out = led_reg;
    wire [7:0] seg_an_masked = seg_an_reg & SEG_AN_ENABLE;
    assign seg0 = SEG_ACTIVE_LOW ? ~seg0_reg : seg0_reg;          // 段选极性
    assign seg1 = SEG_ACTIVE_LOW ? ~seg1_reg : seg1_reg;          // 段选极性
    assign seg_an = SEG_AN_ACTIVE_LOW ? ~seg_an_masked : seg_an_masked; // 位选极性
    assign uart_tx = uart_busy ? uart_shift[0] : 1'b1;            // UART 空闲为高电平
    assign mmio_rdata = mmio_rdata_reg;
    // MMIO ready：始终在 fire 时应答；UART busy 时写会被忽略。
    assign mmio_ready = mmio_fire;
endmodule
