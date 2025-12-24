`include "defines.vh"

module csr_file(
    input  clk,
    input  rst_n,
    input  [`HART_ID_W-1:0] hart_id,
    input  [11:0] csr_addr,
    input  csr_we,
    input  [`XLEN-1:0] csr_wdata,
    input  csr_re,
    output reg [`XLEN-1:0] csr_rdata,
    input  ext_irq,
    input  trap_set,
    input  [`HART_ID_W-1:0] trap_hart_id,
    input  [`XLEN-1:0] trap_mepc,
    input  [`XLEN-1:0] trap_mcause,
    input  trap_mret,
    output [`XLEN-1:0] mstatus_o,
    output [`XLEN-1:0] mie_o,
    output [`XLEN-1:0] mip_o,
    output [`XLEN-1:0] mtvec_o,
    output [`XLEN-1:0] mepc_o,
    output [`XLEN-1:0] mcause_o
);
    reg [`XLEN-1:0] mstatus[`HART_NUM-1:0];
    reg [`XLEN-1:0] mie[`HART_NUM-1:0];
    reg [`XLEN-1:0] mtvec[`HART_NUM-1:0];
    reg [`XLEN-1:0] mepc[`HART_NUM-1:0];
    reg [`XLEN-1:0] mcause[`HART_NUM-1:0];
    reg mstatus_mie_prev[`HART_NUM-1:0];

    integer h;

    wire [`XLEN-1:0] mip_hw = {{20{1'b0}}, ext_irq, {11{1'b0}}};

    always @(posedge clk) begin
        if (!rst_n) begin
            for (h = 0; h < `HART_NUM; h = h + 1) begin
                mstatus[h] <= {`XLEN{1'b0}};
                mie[h]     <= {`XLEN{1'b0}};
                mtvec[h]   <= {`XLEN{1'b0}};
                mepc[h]    <= {`XLEN{1'b0}};
                mcause[h]  <= {`XLEN{1'b0}};
                mstatus_mie_prev[h] <= 1'b0;
            end
        end else if (trap_set) begin
            mepc[trap_hart_id]   <= trap_mepc;
            mcause[trap_hart_id] <= trap_mcause;
            mstatus_mie_prev[trap_hart_id] <= mstatus[trap_hart_id][`MSTATUS_MIE_BIT];
            mstatus[trap_hart_id][`MSTATUS_MIE_BIT] <= 1'b0;
        end else if (trap_mret) begin
            mstatus[trap_hart_id][`MSTATUS_MIE_BIT] <= mstatus_mie_prev[trap_hart_id];
        end else if (csr_we) begin
            case (csr_addr)
                `CSR_MSTATUS: mstatus[hart_id] <= (csr_wdata & (32'h1 << `MSTATUS_MIE_BIT));
                `CSR_MIE:     mie[hart_id]     <= (csr_wdata & (32'h1 << `MIE_MEIE_BIT));
                `CSR_MTVEC:   mtvec[hart_id]   <= csr_wdata;
                `CSR_MEPC:    mepc[hart_id]    <= csr_wdata;
                `CSR_MCAUSE:  mcause[hart_id]  <= csr_wdata;
                default: ;
            endcase
        end
    end

    always @(*) begin
        csr_rdata = {`XLEN{1'b0}};
        if (csr_re) begin
            case (csr_addr)
                `CSR_MSTATUS: csr_rdata = mstatus[hart_id];
                `CSR_MIE:     csr_rdata = mie[hart_id];
                `CSR_MTVEC:   csr_rdata = mtvec[hart_id];
                `CSR_MEPC:    csr_rdata = mepc[hart_id];
                `CSR_MCAUSE:  csr_rdata = mcause[hart_id];
                `CSR_MIP:     csr_rdata = mip_hw;
                `CSR_MHARTID: csr_rdata = {{(`XLEN-1){1'b0}}, hart_id};
                default:      csr_rdata = {`XLEN{1'b0}};
            endcase
        end
    end

    assign mstatus_o = mstatus[hart_id];
    assign mie_o     = mie[hart_id];
    assign mtvec_o   = mtvec[hart_id];
    assign mepc_o    = mepc[hart_id];
    assign mcause_o  = mcause[hart_id];
    assign mip_o     = mip_hw;
endmodule
