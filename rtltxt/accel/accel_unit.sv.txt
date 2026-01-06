`timescale 1ns/1ps
`include "defines.vh"

module accel_unit(
    input  logic clk,
    input  logic rst_n,
    input  logic accel_start,
    input  logic [2:0] accel_op,
    input  logic [`XLEN-1:0] accel_a,
    input  logic [`XLEN-1:0] accel_b,
    input  logic [`HART_ID_W-1:0] accel_hart_id,
    input  logic [`REG_ADDR_W-1:0] accel_rd,
    output logic accel_busy,
    output logic accel_done,
    output logic [`XLEN-1:0] accel_result,
    output logic [`HART_ID_W-1:0] accel_done_hart_id,
    output logic [`REG_ADDR_W-1:0] accel_done_rd
);
    localparam [7:0] JOB_LATENCY = 8'd64;

    logic cmd_pending;
    logic [2:0] cmd_op;
    logic [`XLEN-1:0] cmd_a;
    logic [`XLEN-1:0] cmd_b;
    logic [`HART_ID_W-1:0] cmd_hart_id;
    logic [`REG_ADDR_W-1:0] cmd_rd;
    logic cmd_start_ok;
    logic [7:0] cmd_job_id;

    logic job_active;
    logic job_done;
    logic job_err;
    logic [7:0] job_id;
    logic [7:0] job_count;

    logic [`XLEN-1:0] cfg_reg [0:3];
    integer i;

    wire [31:0] status_word = {29'd0, job_err, job_done, job_active};

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cmd_pending <= 1'b0;
            cmd_op <= 3'b0;
            cmd_a <= {`XLEN{1'b0}};
            cmd_b <= {`XLEN{1'b0}};
            cmd_hart_id <= {`HART_ID_W{1'b0}};
            cmd_rd <= {`REG_ADDR_W{1'b0}};
            cmd_start_ok <= 1'b0;
            cmd_job_id <= 8'd0;
            job_active <= 1'b0;
            job_done <= 1'b0;
            job_err <= 1'b0;
            job_id <= 8'd0;
            job_count <= 8'd0;
            accel_done <= 1'b0;
            accel_result <= {`XLEN{1'b0}};
            accel_done_hart_id <= {`HART_ID_W{1'b0}};
            accel_done_rd <= {`REG_ADDR_W{1'b0}};
            for (i = 0; i < 4; i = i + 1) begin
                cfg_reg[i] <= {`XLEN{1'b0}};
            end
        end else begin
            accel_done <= 1'b0;

            if (job_active) begin
                if (job_count != 8'd0) begin
                    job_count <= job_count - 8'd1;
                end
                if (job_count == 8'd1) begin
                    job_active <= 1'b0;
                    job_done <= 1'b1;
                end
            end

            if (accel_start && !cmd_pending) begin
                cmd_pending <= 1'b1;
                cmd_op <= accel_op;
                cmd_a <= accel_a;
                cmd_b <= accel_b;
                cmd_hart_id <= accel_hart_id;
                cmd_rd <= accel_rd;
                cmd_start_ok <= 1'b0;
                cmd_job_id <= 8'd0;

                if (accel_op == `CUST1_START) begin
                    if (!job_active) begin
                        job_active <= 1'b1;
                        job_done <= 1'b0;
                        job_err <= 1'b0;
                        job_count <= JOB_LATENCY;
                        job_id <= job_id + 8'd1;
                        cmd_start_ok <= 1'b1;
                        cmd_job_id <= job_id + 8'd1;
                    end
                end else if (accel_op == `CUST1_CANCEL) begin
                    job_active <= 1'b0;
                    job_done <= 1'b1;
                    job_err <= 1'b1;
                end else if (accel_op == `CUST1_SETCFG) begin
                    case (accel_a[1:0])
                        2'd0: cfg_reg[0] <= accel_b;
                        2'd1: cfg_reg[1] <= accel_b;
                        2'd2: cfg_reg[2] <= accel_b;
                        2'd3: cfg_reg[3] <= accel_b;
                        default: cfg_reg[0] <= cfg_reg[0];
                    endcase
                end
            end

            if (cmd_pending) begin
                if (cmd_op == `CUST1_WAIT && job_active) begin
                    cmd_pending <= 1'b1;
                end else begin
                    accel_done <= 1'b1;
                    accel_done_hart_id <= cmd_hart_id;
                    accel_done_rd <= cmd_rd;
                    case (cmd_op)
                        `CUST1_START: accel_result <= cmd_start_ok ? {24'd0, cmd_job_id} : {`XLEN{1'b0}};
                        `CUST1_POLL: accel_result <= status_word;
                        `CUST1_WAIT: accel_result <= status_word;
                        `CUST1_CANCEL: accel_result <= status_word;
                        `CUST1_FENCE: accel_result <= {`XLEN{1'b0}};
                        `CUST1_GETERR: accel_result <= {31'd0, job_err};
                        `CUST1_SETCFG: accel_result <= {`XLEN{1'b0}};
                        `CUST1_GETCFG: begin
                            case (cmd_a[1:0])
                                2'd0: accel_result <= cfg_reg[0];
                                2'd1: accel_result <= cfg_reg[1];
                                2'd2: accel_result <= cfg_reg[2];
                                2'd3: accel_result <= cfg_reg[3];
                                default: accel_result <= {`XLEN{1'b0}};
                            endcase
                        end
                        default: accel_result <= {`XLEN{1'b0}};
                    endcase
                    cmd_pending <= 1'b0;
                end
            end
        end
    end

    assign accel_busy = cmd_pending;
endmodule
