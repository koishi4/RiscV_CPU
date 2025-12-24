`include "defines.vh"

module regfile_bank(
    input  clk,
    input  rst_n,
    input  [`HART_ID_W-1:0] r_hart_id,
    input  [`REG_ADDR_W-1:0] raddr1,
    input  [`REG_ADDR_W-1:0] raddr2,
    output reg [`XLEN-1:0] rdata1,
    output reg [`XLEN-1:0] rdata2,
    input  w_en,
    input  [`HART_ID_W-1:0] w_hart_id,
    input  [`REG_ADDR_W-1:0] waddr,
    input  [`XLEN-1:0] wdata
);
    // 2-bank regfile, x0 hardwired to 0 for each hart.
    reg [`XLEN-1:0] regs[`HART_NUM-1:0][31:0];
    integer h;
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (h = 0; h < `HART_NUM; h = h + 1) begin
                for (i = 0; i < 32; i = i + 1) begin
                    regs[h][i] <= {`XLEN{1'b0}};
                end
            end
        end else if (w_en && (waddr != {`REG_ADDR_W{1'b0}})) begin
            regs[w_hart_id][waddr] <= wdata;
        end
    end

    always @(*) begin
        rdata1 = {`XLEN{1'b0}};
        rdata2 = {`XLEN{1'b0}};

        if (raddr1 != {`REG_ADDR_W{1'b0}}) begin
            if (w_en && (w_hart_id == r_hart_id) && (waddr == raddr1)) begin
                rdata1 = wdata;
            end else begin
                rdata1 = regs[r_hart_id][raddr1];
            end
        end

        if (raddr2 != {`REG_ADDR_W{1'b0}}) begin
            if (w_en && (w_hart_id == r_hart_id) && (waddr == raddr2)) begin
                rdata2 = wdata;
            end else begin
                rdata2 = regs[r_hart_id][raddr2];
            end
        end
    end
endmodule
