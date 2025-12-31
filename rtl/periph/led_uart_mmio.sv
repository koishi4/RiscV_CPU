`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module led_uart_mmio #(
    parameter integer UART_DIV = `UART_DIV,
    parameter BTN_ACTIVE_LOW = 1'b1,
    parameter SW_ACTIVE_LOW = 1'b0,
    parameter SEG_ACTIVE_LOW = 1'b0,
    parameter SEG_AN_ACTIVE_LOW = 1'b0,
    parameter [7:0] SEG_AN_ENABLE = 8'hFF,
    parameter SEG_SCAN_EN = 1'b1,
    parameter integer SEG_SCAN_DIV = 50000,
    parameter integer SEG_UPDATE_DIV = 0
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
    localparam [`ADDR_W-1:0] LED_ADDR       = `IO_BASE_ADDR + `IO_LED_OFFSET;
    localparam [`ADDR_W-1:0] UART_TX_ADDR   = `IO_BASE_ADDR + `IO_UART_TX_OFFSET;
    localparam [`ADDR_W-1:0] UART_STAT_ADDR = `IO_BASE_ADDR + `IO_UART_STAT_OFFSET;
    localparam [`ADDR_W-1:0] SEG_ADDR       = `IO_BASE_ADDR + `IO_SEG_OFFSET;
    localparam [`ADDR_W-1:0] BTN_ADDR       = `IO_BASE_ADDR + `IO_BTN_OFFSET;

    reg mmio_pending;
    reg mmio_we_d;
    reg [`ADDR_W-1:0] mmio_addr_d;
    reg [`XLEN-1:0] mmio_wdata_d;
    wire mmio_accept = mmio_req && !mmio_pending;
    wire mmio_fire = mmio_pending;
    wire mmio_wr = mmio_fire && mmio_we_d;
    wire mmio_rd = mmio_fire && !mmio_we_d;
    wire uart_write = mmio_wr && (mmio_addr_d == UART_TX_ADDR);

    reg [`IO_LED_WIDTH-1:0] led_reg;
    reg [31:0] seg_val_reg;
    reg [31:0] seg_pending;
    reg [`XLEN-1:0] mmio_rdata_reg;

    reg uart_busy;
    reg [9:0] uart_shift;
    reg [3:0] uart_bits_left;
    reg [15:0] uart_div_cnt;
    reg [31:0] seg_scan_cnt;
    reg [2:0] seg_digit_idx;
    reg [31:0] seg_update_cnt;
    reg [7:0] seg0_reg;
    reg [7:0] seg1_reg;
    reg [7:0] seg_an_reg;

    wire seg_scan_tick = SEG_SCAN_EN && (seg_scan_cnt == 32'd0);

    wire [4:0] btn_sample = BTN_ACTIVE_LOW ? ~btn_in : btn_in;
    wire [7:0] sw_sample = SW_ACTIVE_LOW ? ~sw_in : sw_in;

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
            if (mmio_accept) begin
                mmio_pending <= 1'b1;
                mmio_we_d <= mmio_we;
                mmio_addr_d <= mmio_addr;
                mmio_wdata_d <= mmio_wdata;
            end else if (mmio_fire) begin
                mmio_pending <= 1'b0;
            end

            if (mmio_wr && (mmio_addr_d == LED_ADDR)) begin
                led_reg <= mmio_wdata_d[`IO_LED_WIDTH-1:0];
            end else if (mmio_wr && (mmio_addr_d == SEG_ADDR)) begin
                seg_pending <= mmio_wdata_d;
            end

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

            if (SEG_SCAN_EN) begin
                if (seg_scan_tick) begin
                    seg_an_reg <= 8'b0000_0000;
                    seg0_reg <= 8'b0000_0000;
                    seg1_reg <= 8'b0000_0000;
                    case (seg_digit_idx)
                        3'd0: begin
                            seg_an_reg[0] <= 1'b1;
                            seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[31:28])};
                        end
                        3'd1: begin
                            seg_an_reg[1] <= 1'b1;
                            seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[27:24])};
                        end
                        3'd2: begin
                            seg_an_reg[2] <= 1'b1;
                            seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[23:20])};
                        end
                        3'd3: begin
                            seg_an_reg[3] <= 1'b1;
                            seg0_reg <= {1'b0, hex_to_seg(seg_val_reg[19:16])};
                        end
                        3'd4: begin
                            seg_an_reg[4] <= 1'b1;
                            seg1_reg <= {1'b0, hex_to_seg(seg_val_reg[15:12])};
                        end
                        3'd5: begin
                            seg_an_reg[5] <= 1'b1;
                            seg1_reg <= {1'b0, hex_to_seg(seg_val_reg[11:8])};
                        end
                        3'd6: begin
                            seg_an_reg[6] <= 1'b1;
                            seg1_reg <= {1'b0, hex_to_seg(seg_val_reg[7:4])};
                        end
                        default: begin
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

    // Synchronous MMIO read: capture on accept so data is valid when ready pulses.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_rdata_reg <= {`XLEN{1'b0}};
        end else if (mmio_accept && !mmio_we) begin
            if (mmio_addr == LED_ADDR) begin
                mmio_rdata_reg <= {{(`XLEN-`IO_LED_WIDTH){1'b0}}, led_reg};
            end else if (mmio_addr == UART_STAT_ADDR) begin
                mmio_rdata_reg <= {31'b0, uart_busy};
            end else if (mmio_addr == SEG_ADDR) begin
                mmio_rdata_reg <= seg_pending;
            end else if (mmio_addr == BTN_ADDR) begin
                mmio_rdata_reg <= {19'b0, sw_sample, btn_sample};
            end else begin
                mmio_rdata_reg <= {`XLEN{1'b0}};
            end
        end
    end

    assign led_out = led_reg;
    wire [7:0] seg_an_masked = seg_an_reg & SEG_AN_ENABLE;
    assign seg0 = SEG_ACTIVE_LOW ? ~seg0_reg : seg0_reg;
    assign seg1 = SEG_ACTIVE_LOW ? ~seg1_reg : seg1_reg;
    assign seg_an = SEG_AN_ACTIVE_LOW ? ~seg_an_masked : seg_an_masked;
    assign uart_tx = uart_busy ? uart_shift[0] : 1'b1;
    assign mmio_rdata = mmio_rdata_reg;
    // Always acknowledge MMIO; UART drops writes while busy (no global stall).
    assign mmio_ready = mmio_fire;
endmodule
