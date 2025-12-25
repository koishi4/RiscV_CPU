`timescale 1ns/1ps
`include "defines.vh"

module tb_hazard_fwd;
    reg [`REG_ADDR_W-1:0] rs1_addr;
    reg [`REG_ADDR_W-1:0] rs2_addr;
    reg [`XLEN-1:0] rs1_val_in;
    reg [`XLEN-1:0] rs2_val_in;
    reg exmem_wb_en;
    reg [`REG_ADDR_W-1:0] exmem_rd;
    reg [`XLEN-1:0] exmem_wb_data;
    reg exwb_wb_en;
    reg [`REG_ADDR_W-1:0] exwb_rd;
    reg [`XLEN-1:0] exwb_wb_data;

    wire [`XLEN-1:0] rs1_val_out;
    wire [`XLEN-1:0] rs2_val_out;

    hazard_fwd dut (
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_val_in(rs1_val_in),
        .rs2_val_in(rs2_val_in),
        .exmem_wb_en(exmem_wb_en),
        .exmem_rd(exmem_rd),
        .exmem_wb_data(exmem_wb_data),
        .exwb_wb_en(exwb_wb_en),
        .exwb_rd(exwb_rd),
        .exwb_wb_data(exwb_wb_data),
        .rs1_val_out(rs1_val_out),
        .rs2_val_out(rs2_val_out)
    );

    task automatic check_expected;
        reg [`XLEN-1:0] exp1;
        reg [`XLEN-1:0] exp2;
        begin
            exp1 = rs1_val_in;
            exp2 = rs2_val_in;
            if (exmem_wb_en && (exmem_rd != 0) && (exmem_rd == rs1_addr)) begin
                exp1 = exmem_wb_data;
            end else if (exwb_wb_en && (exwb_rd != 0) && (exwb_rd == rs1_addr)) begin
                exp1 = exwb_wb_data;
            end
            if (exmem_wb_en && (exmem_rd != 0) && (exmem_rd == rs2_addr)) begin
                exp2 = exmem_wb_data;
            end else if (exwb_wb_en && (exwb_rd != 0) && (exwb_rd == rs2_addr)) begin
                exp2 = exwb_wb_data;
            end
            #1;
            if (rs1_val_out !== exp1) begin
                $fatal(1, "rs1 forward mismatch exp=%h got=%h", exp1, rs1_val_out);
            end
            if (rs2_val_out !== exp2) begin
                $fatal(1, "rs2 forward mismatch exp=%h got=%h", exp2, rs2_val_out);
            end
        end
    endtask

    initial begin
        rs1_addr = 0;
        rs2_addr = 0;
        rs1_val_in = 32'h0;
        rs2_val_in = 32'h0;
        exmem_wb_en = 1'b0;
        exmem_rd = 0;
        exmem_wb_data = 32'h0;
        exwb_wb_en = 1'b0;
        exwb_rd = 0;
        exwb_wb_data = 32'h0;

        // Directed: EX/MEM priority.
        rs1_addr = 5'd3;
        rs2_addr = 5'd4;
        rs1_val_in = 32'h1111_1111;
        rs2_val_in = 32'h2222_2222;
        exmem_wb_en = 1'b1;
        exmem_rd = 5'd3;
        exmem_wb_data = 32'hAAAA_AAAA;
        exwb_wb_en = 1'b1;
        exwb_rd = 5'd3;
        exwb_wb_data = 32'hBBBB_BBBB;
        check_expected();

        // Directed: MEM/WB fallback.
        exmem_wb_en = 1'b0;
        exmem_rd = 5'd0;
        exwb_wb_en = 1'b1;
        exwb_rd = 5'd4;
        exwb_wb_data = 32'hCCCC_CCCC;
        check_expected();

        // Directed: x0 should not forward.
        rs1_addr = 5'd0;
        rs1_val_in = 32'h1234_5678;
        exmem_wb_en = 1'b1;
        exmem_rd = 5'd0;
        exmem_wb_data = 32'hFFFF_FFFF;
        exwb_wb_en = 1'b1;
        exwb_rd = 5'd0;
        exwb_wb_data = 32'hEEEE_EEEE;
        check_expected();

        // Randomized cases.
        begin : rand_cases
            integer i;
            for (i = 0; i < 1000; i = i + 1) begin
                rs1_addr = $urandom % 32;
                rs2_addr = $urandom % 32;
                rs1_val_in = $urandom;
                rs2_val_in = $urandom;
                exmem_wb_en = $urandom % 2;
                exmem_rd = $urandom % 32;
                exmem_wb_data = $urandom;
                exwb_wb_en = $urandom % 2;
                exwb_rd = $urandom % 32;
                exwb_wb_data = $urandom;
                check_expected();
            end
        end

        $display("hazard_fwd_tb PASS");
        $finish;
    end
endmodule
