`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module led_uart_mmio #(
    parameter integer UART_DIV = `UART_DIV,
    parameter BTN_ACTIVE_LOW = 1'b1,
    parameter SEG_ACTIVE_LOW = 1'b0,
    parameter SEG_AN_ACTIVE_LOW = 1'b1,
    parameter [7:0] SEG_AN_ENABLE = 8'hFF,
    parameter SEG_SCAN_EN = 1'b1,
    parameter integer SEG_SCAN_DIV = 50000
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
    output uart_tx
);
    localparam [`ADDR_W-1:0] LED_ADDR       = `IO_BASE_ADDR + `IO_LED_OFFSET;
    localparam [`ADDR_W-1:0] UART_TX_ADDR   = `IO_BASE_ADDR + `IO_UART_TX_OFFSET;
    localparam [`ADDR_W-1:0] UART_STAT_ADDR = `IO_BASE_ADDR + `IO_UART_STAT_OFFSET;
    localparam [`ADDR_W-1:0] SEG_ADDR       = `IO_BASE_ADDR + `IO_SEG_OFFSET;
    localparam [`ADDR_W-1:0] BTN_ADDR       = `IO_BASE_ADDR + `IO_BTN_OFFSET;

    wire mmio_wr = mmio_req && mmio_we;
    wire mmio_rd = mmio_req && !mmio_we;
    wire uart_write = mmio_wr && (mmio_addr == UART_TX_ADDR);

    reg [`IO_LED_WIDTH-1:0] led_reg;
    reg [31:0] seg_val_reg;
    reg [`XLEN-1:0] mmio_rdata_reg;

    reg uart_busy;
    reg [9:0] uart_shift;
    reg [3:0] uart_bits_left;
    reg [15:0] uart_div_cnt;
    reg [31:0] seg_scan_cnt;
    reg [2:0] seg_digit_idx;

    wire [4:0] btn_sample = BTN_ACTIVE_LOW ? ~btn_in : btn_in;

    function automatic [6:0] hex_to_seg(input [3:0] nibble);
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_reg <= {`IO_LED_WIDTH{1'b0}};
            seg_val_reg <= 32'h0000_0000;
            uart_busy <= 1'b0;
            uart_shift <= 10'h3FF;
            uart_bits_left <= 4'd0;
            uart_div_cnt <= 16'd0;
            seg_scan_cnt <= 32'd0;
            seg_digit_idx <= 3'd0;
        end else begin
            if (mmio_wr && (mmio_addr == LED_ADDR)) begin
                led_reg <= mmio_wdata[`IO_LED_WIDTH-1:0];
            end else if (mmio_wr && (mmio_addr == SEG_ADDR)) begin
                seg_val_reg <= mmio_wdata;
            end

            if (uart_write && !uart_busy) begin
                uart_shift <= {1'b1, mmio_wdata[7:0], 1'b0};
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
        end
    end

    // Synchronous MMIO read to align with one-cycle mem_ready behavior.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_rdata_reg <= {`XLEN{1'b0}};
        end else if (mmio_rd) begin
            if (mmio_addr == LED_ADDR) begin
                mmio_rdata_reg <= {{(`XLEN-`IO_LED_WIDTH){1'b0}}, led_reg};
            end else if (mmio_addr == UART_STAT_ADDR) begin
                mmio_rdata_reg <= {31'b0, uart_busy};
            end else if (mmio_addr == SEG_ADDR) begin
                mmio_rdata_reg <= seg_val_reg;
            end else if (mmio_addr == BTN_ADDR) begin
                mmio_rdata_reg <= {27'b0, btn_sample};
            end else begin
                mmio_rdata_reg <= {`XLEN{1'b0}};
            end
        end
    end

    assign led_out = led_reg;
    // seg raw bit order: [6]=G ... [0]=A (A is LSB)
    reg [3:0] seg0_nibble;
    reg [3:0] seg1_nibble;
    reg seg0_blank;
    reg seg1_blank;
    reg [7:0] seg_an_raw;
    always @* begin
        seg0_nibble = seg_val_reg[3:0];
        seg1_nibble = seg_val_reg[7:4];
        seg0_blank = 1'b0;
        seg1_blank = 1'b0;
        seg_an_raw = SEG_AN_ENABLE;
        if (SEG_SCAN_EN) begin
            seg0_blank = 1'b1;
            seg1_blank = 1'b1;
            case (seg_digit_idx)
                3'd0: begin seg0_nibble = seg_val_reg[3:0];   seg0_blank = 1'b0; end
                3'd1: begin seg0_nibble = seg_val_reg[7:4];   seg0_blank = 1'b0; end
                3'd2: begin seg0_nibble = seg_val_reg[11:8];  seg0_blank = 1'b0; end
                3'd3: begin seg0_nibble = seg_val_reg[15:12]; seg0_blank = 1'b0; end
                3'd4: begin seg1_nibble = seg_val_reg[19:16]; seg1_blank = 1'b0; end
                3'd5: begin seg1_nibble = seg_val_reg[23:20]; seg1_blank = 1'b0; end
                3'd6: begin seg1_nibble = seg_val_reg[27:24]; seg1_blank = 1'b0; end
                default: begin seg1_nibble = seg_val_reg[31:28]; seg1_blank = 1'b0; end
            endcase
            seg_an_raw = (8'b1 << seg_digit_idx);
        end
    end

    wire [6:0] seg0_raw = seg0_blank ? 7'b0000000 : hex_to_seg(seg0_nibble);
    wire [6:0] seg1_raw = seg1_blank ? 7'b0000000 : hex_to_seg(seg1_nibble);
    wire [7:0] seg0_full = {1'b0, seg0_raw};
    wire [7:0] seg1_full = {1'b0, seg1_raw};
    wire [7:0] seg_an_masked = seg_an_raw & SEG_AN_ENABLE;
    assign seg0 = SEG_ACTIVE_LOW ? ~seg0_full : seg0_full;
    assign seg1 = SEG_ACTIVE_LOW ? ~seg1_full : seg1_full;
    assign seg_an = SEG_AN_ACTIVE_LOW ? ~seg_an_masked : seg_an_masked;
    assign uart_tx = uart_busy ? uart_shift[0] : 1'b1;
    assign mmio_rdata = mmio_rdata_reg;
    // Always acknowledge MMIO; UART drops writes while busy (no global stall).
    assign mmio_ready = mmio_req;
endmodule
