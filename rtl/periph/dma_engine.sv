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
    // Word-only MMIO writes; start is ignored while busy.

    localparam [`ADDR_W-1:0] DMA_SRC_ADDR  = `DMA_BASE_ADDR + `DMA_SRC_OFFSET;
    localparam [`ADDR_W-1:0] DMA_DST_ADDR  = `DMA_BASE_ADDR + `DMA_DST_OFFSET;
    localparam [`ADDR_W-1:0] DMA_LEN_ADDR  = `DMA_BASE_ADDR + `DMA_LEN_OFFSET;
    localparam [`ADDR_W-1:0] DMA_CTRL_ADDR = `DMA_BASE_ADDR + `DMA_CTRL_OFFSET;
    localparam [`ADDR_W-1:0] DMA_STAT_ADDR = `DMA_BASE_ADDR + `DMA_STAT_OFFSET;
    localparam [`ADDR_W-1:0] DMA_CLR_ADDR  = `DMA_BASE_ADDR + `DMA_CLR_OFFSET;

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_READ      = 3'd1;
    localparam [2:0] STATE_READ_GAP  = 3'd2;
    localparam [2:0] STATE_WRITE     = 3'd3;
    localparam [2:0] STATE_WRITE_GAP = 3'd4;

    localparam integer DMA_GAP_INIT = (DMA_GAP_CYCLES > 0) ? (DMA_GAP_CYCLES - 1) : 0;

    reg [2:0] state;
    reg [2:0] state_n;
    reg read_req_d;
    reg write_req_d;

    reg [`ADDR_W-1:0] src_reg;
    reg [`ADDR_W-1:0] dst_reg;
    reg [`XLEN-1:0]   len_reg;
    reg              irq_en_reg;
    reg              done_reg;
    reg              err_reg;
    reg              irq_pending_reg;

    reg [`ADDR_W-1:0] cur_src;
    reg [`ADDR_W-1:0] cur_dst;
    reg [`XLEN-1:0]   cur_len;
    reg [`XLEN-1:0]   read_data;

    reg [`XLEN-1:0]   mmio_rdata_reg;

    reg [`ADDR_W-1:0] src_reg_n;
    reg [`ADDR_W-1:0] dst_reg_n;
    reg [`XLEN-1:0]   len_reg_n;
    reg              irq_en_reg_n;
    reg              done_reg_n;
    reg              err_reg_n;
    reg              irq_pending_reg_n;

    reg [`ADDR_W-1:0] cur_src_n;
    reg [`ADDR_W-1:0] cur_dst_n;
    reg [`XLEN-1:0]   cur_len_n;
    reg [`XLEN-1:0]   read_data_n;
    reg [31:0]        gap_cnt;
    reg [31:0]        gap_cnt_n;

    reg mmio_pending;
    reg mmio_we_d;
    reg [`ADDR_W-1:0] mmio_addr_d;
    reg [`XLEN-1:0] mmio_wdata_d;
    wire mmio_accept = mmio_req && !mmio_pending;
    wire mmio_fire = mmio_pending;
    wire mmio_wr = mmio_fire && mmio_we_d;
    wire mmio_rd = mmio_fire && !mmio_we_d;

    wire start_pulse = mmio_wr &&
                       (mmio_addr_d == DMA_CTRL_ADDR) &&
                       mmio_wdata_d[`DMA_CTRL_START_BIT];

    wire busy = (state != STATE_IDLE);

    // ERR on unaligned length/address or MMIO-range addresses.
    wire addr_unaligned = (src_reg[1:0] != 2'b00) || (dst_reg[1:0] != 2'b00);
    wire len_unaligned  = (len_reg[1:0] != 2'b00);
    wire src_hits_mmio  = ((src_reg & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);
    wire dst_hits_mmio  = ((dst_reg & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);
    wire bad_param = addr_unaligned || len_unaligned || src_hits_mmio || dst_hits_mmio;

    wire mem_ready_read = dma_mem_ready && read_req_d;
    wire mem_ready_write = dma_mem_ready && write_req_d;

    always @(*) begin
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

        if (mmio_wr) begin
            if (mmio_addr_d == DMA_SRC_ADDR) begin
                src_reg_n = mmio_wdata_d;
            end else if (mmio_addr_d == DMA_DST_ADDR) begin
                dst_reg_n = mmio_wdata_d;
            end else if (mmio_addr_d == DMA_LEN_ADDR) begin
                len_reg_n = mmio_wdata_d;
            end else if (mmio_addr_d == DMA_CTRL_ADDR) begin
                irq_en_reg_n = mmio_wdata_d[`DMA_CTRL_IRQ_EN_BIT];
            end else if (mmio_addr_d == DMA_CLR_ADDR) begin
                if (mmio_wdata_d[`DMA_CLR_DONE_BIT]) begin
                    done_reg_n = 1'b0;
                    irq_pending_reg_n = 1'b0;
                end
                if (mmio_wdata_d[`DMA_CLR_ERR_BIT]) begin
                    err_reg_n = 1'b0;
                end
            end
        end

        if (start_pulse && !busy) begin
            cur_src_n = src_reg;
            cur_dst_n = dst_reg;
            cur_len_n = len_reg;
            if (len_reg == {`XLEN{1'b0}}) begin
                done_reg_n = 1'b1;
            end else if (bad_param) begin
                done_reg_n = 1'b1;
                err_reg_n = 1'b1;
            end else begin
                state_n = STATE_READ;
            end
        end

        case (state)
            STATE_IDLE: begin
            end
            STATE_READ: begin
                if (mem_ready_read) begin
                    read_data_n = dma_mem_rdata;
                    if (DMA_GAP_CYCLES > 0) begin
                        gap_cnt_n = DMA_GAP_INIT[31:0];
                        state_n = STATE_READ_GAP;
                    end else begin
                        state_n = STATE_WRITE;
                    end
                end
            end
            STATE_READ_GAP: begin
                if (gap_cnt == 32'd0) begin
                    state_n = STATE_WRITE;
                end else begin
                    gap_cnt_n = gap_cnt - 32'd1;
                end
            end
            STATE_WRITE: begin
                if (mem_ready_write) begin
                    if (cur_len <= 32'd4) begin
                        cur_len_n = {`XLEN{1'b0}};
                        done_reg_n = 1'b1;
                        state_n = STATE_IDLE;
                    end else begin
                        cur_len_n = cur_len - 32'd4;
                        cur_src_n = cur_src + 32'd4;
                        cur_dst_n = cur_dst + 32'd4;
                        if (DMA_GAP_CYCLES > 0) begin
                            gap_cnt_n = DMA_GAP_INIT[31:0];
                            state_n = STATE_WRITE_GAP;
                        end else begin
                            state_n = STATE_READ;
                        end
                    end
                end
            end
            STATE_WRITE_GAP: begin
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

        if (done_reg_n && irq_en_reg_n) begin
            irq_pending_reg_n = 1'b1;
        end
    end

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
            read_req_d <= (state == STATE_READ);
            write_req_d <= (state == STATE_WRITE);
            if (mmio_accept) begin
                mmio_pending <= 1'b1;
                mmio_we_d <= mmio_we;
                mmio_addr_d <= mmio_addr;
                mmio_wdata_d <= mmio_wdata;
            end else if (mmio_fire) begin
                mmio_pending <= 1'b0;
            end
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_rdata_reg <= {`XLEN{1'b0}};
        end else if (mmio_accept && !mmio_we) begin
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

    assign mmio_rdata = mmio_rdata_reg;
    assign mmio_ready = mmio_fire;

    assign dma_mem_req = (state == STATE_READ) || (state == STATE_WRITE);
    assign dma_mem_we = (state == STATE_WRITE);
    assign dma_mem_addr = (state == STATE_READ) ? cur_src :
                          (state == STATE_WRITE) ? cur_dst : {`ADDR_W{1'b0}};
    assign dma_mem_wdata = read_data;

    assign dma_irq = irq_pending_reg;
endmodule
