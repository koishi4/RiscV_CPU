`timescale 1ns/1ps
`include "defines.vh"
`include "interface.vh"

module dma_engine(
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

    localparam [1:0] STATE_IDLE  = 2'd0;
    localparam [1:0] STATE_READ  = 2'd1;
    localparam [1:0] STATE_WRITE = 2'd2;

    reg [1:0] state;
    reg [1:0] state_n;

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

    wire mmio_wr = mmio_req && mmio_we;
    wire mmio_rd = mmio_req && !mmio_we;

    wire start_pulse = mmio_wr &&
                       (mmio_addr == DMA_CTRL_ADDR) &&
                       mmio_wdata[`DMA_CTRL_START_BIT];

    wire busy = (state != STATE_IDLE);

    // ERR on unaligned length/address or MMIO-range addresses.
    wire addr_unaligned = (src_reg[1:0] != 2'b00) || (dst_reg[1:0] != 2'b00);
    wire len_unaligned  = (len_reg[1:0] != 2'b00);
    wire src_hits_mmio  = ((src_reg & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);
    wire dst_hits_mmio  = ((dst_reg & `DMA_ADDR_MASK) == `DMA_ADDR_MATCH);
    wire bad_param = addr_unaligned || len_unaligned || src_hits_mmio || dst_hits_mmio;

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

        if (mmio_wr) begin
            if (mmio_addr == DMA_SRC_ADDR) begin
                src_reg_n = mmio_wdata;
            end else if (mmio_addr == DMA_DST_ADDR) begin
                dst_reg_n = mmio_wdata;
            end else if (mmio_addr == DMA_LEN_ADDR) begin
                len_reg_n = mmio_wdata;
            end else if (mmio_addr == DMA_CTRL_ADDR) begin
                irq_en_reg_n = mmio_wdata[`DMA_CTRL_IRQ_EN_BIT];
            end else if (mmio_addr == DMA_CLR_ADDR) begin
                if (mmio_wdata[`DMA_CLR_DONE_BIT]) begin
                    done_reg_n = 1'b0;
                    irq_pending_reg_n = 1'b0;
                end
                if (mmio_wdata[`DMA_CLR_ERR_BIT]) begin
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
                if (dma_mem_ready) begin
                    read_data_n = dma_mem_rdata;
                    state_n = STATE_WRITE;
                end
            end
            STATE_WRITE: begin
                if (dma_mem_ready) begin
                    if (cur_len <= 32'd4) begin
                        cur_len_n = {`XLEN{1'b0}};
                        done_reg_n = 1'b1;
                        state_n = STATE_IDLE;
                    end else begin
                        cur_len_n = cur_len - 32'd4;
                        cur_src_n = cur_src + 32'd4;
                        cur_dst_n = cur_dst + 32'd4;
                        state_n = STATE_READ;
                    end
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
        end else begin
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
        end
    end

    always @(*) begin
        mmio_rdata_reg = {`XLEN{1'b0}};
        if (mmio_rd) begin
            if (mmio_addr == DMA_SRC_ADDR) begin
                mmio_rdata_reg = src_reg;
            end else if (mmio_addr == DMA_DST_ADDR) begin
                mmio_rdata_reg = dst_reg;
            end else if (mmio_addr == DMA_LEN_ADDR) begin
                mmio_rdata_reg = len_reg;
            end else if (mmio_addr == DMA_CTRL_ADDR) begin
                mmio_rdata_reg = {30'b0, irq_en_reg, 1'b0};
            end else if (mmio_addr == DMA_STAT_ADDR) begin
                mmio_rdata_reg = {29'b0, err_reg, done_reg, busy};
            end else begin
                mmio_rdata_reg = {`XLEN{1'b0}};
            end
        end
    end

    assign mmio_rdata = mmio_rdata_reg;
    assign mmio_ready = mmio_req;

    assign dma_mem_req = (state == STATE_READ) || (state == STATE_WRITE);
    assign dma_mem_we = (state == STATE_WRITE);
    assign dma_mem_addr = (state == STATE_READ) ? cur_src :
                          (state == STATE_WRITE) ? cur_dst : {`ADDR_W{1'b0}};
    assign dma_mem_wdata = read_data;

    assign dma_irq = irq_pending_reg;
endmodule
