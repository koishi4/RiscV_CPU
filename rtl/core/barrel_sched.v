`include "defines.vh"

module barrel_sched(
    input  clk,
    input  rst_n,
    input  [`HART_NUM-1:0] blocked,
    output [`HART_ID_W-1:0] cur_hart,
    output cur_valid
);
    // Round-robin scheduler with skip-on-blocked policy for 2 harts.
    reg [`HART_ID_W-1:0] last_hart;
    reg [`HART_ID_W-1:0] next_hart;
    reg next_valid;

    always @(*) begin
        if (blocked == {`HART_NUM{1'b1}}) begin
            next_valid = 1'b0;
            next_hart  = last_hart;
        end else begin
            next_valid = 1'b1;
            next_hart  = last_hart ^ {`HART_ID_W{1'b1}};
            if (blocked[next_hart]) begin
                next_hart = last_hart;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            last_hart <= {`HART_ID_W{1'b0}};
        end else if (next_valid) begin
            last_hart <= next_hart;
        end
    end

    assign cur_hart  = next_hart;
    assign cur_valid = next_valid;
endmodule
