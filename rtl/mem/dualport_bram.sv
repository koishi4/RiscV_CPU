`include "defines.vh"
`include "interface.vh"

module dualport_bram(
    input  clk,
    input  rst_n,
    `MEM_REQ_PORTS(input, a_mem),
    `MEM_RSP_PORTS(output, a_mem),
    `MEM_REQ_PORTS(input, b_mem),
    `MEM_RSP_PORTS(output, b_mem)
);
    // True dual-port RAM model; concurrent writes to same address resolve to port B.

    localparam integer DEPTH = (`MEM_SIZE_BYTES / 4);
    localparam integer ADDR_IDX_W = $clog2(DEPTH);

    reg [`XLEN-1:0] mem [0:DEPTH-1];

    wire [ADDR_IDX_W-1:0] a_idx = a_mem_addr[ADDR_IDX_W+1:2];
    wire [ADDR_IDX_W-1:0] b_idx = b_mem_addr[ADDR_IDX_W+1:2];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {`XLEN{1'b0}};
            end
        end else begin
            if (a_mem_req && a_mem_we) begin
                mem[a_idx] <= a_mem_wdata;
            end
            if (b_mem_req && b_mem_we) begin
                mem[b_idx] <= b_mem_wdata;
            end
        end
    end

    assign a_mem_rdata = mem[a_idx];
    assign b_mem_rdata = mem[b_idx];

    assign a_mem_ready = a_mem_req;
    assign b_mem_ready = b_mem_req;
endmodule
