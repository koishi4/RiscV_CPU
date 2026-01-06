`ifndef DEFINES_VH
`define DEFINES_VH

// Global widths
`define XLEN            32
`define ADDR_W          32
`define REG_ADDR_W       5
`define HART_NUM         2
`define HART_ID_W         1

// Reset
`define RESET_VECTOR 32'h0000_0000

// Memory
`define MEM_SIZE_BYTES 32'h0001_0000  // 64KB default

// DMA MMIO base and offsets
`define DMA_BASE_ADDR   32'h4000_0000
`define DMA_SRC_OFFSET  32'h0000_0000
`define DMA_DST_OFFSET  32'h0000_0004
`define DMA_LEN_OFFSET  32'h0000_0008
`define DMA_CTRL_OFFSET 32'h0000_000C
`define DMA_STAT_OFFSET 32'h0000_0010
`define DMA_CLR_OFFSET  32'h0000_0014

`define DMA_ADDR_MASK   32'hFFFF_FFE0
`define DMA_ADDR_MATCH  32'h4000_0000

`define DMA_CTRL_START_BIT 0
`define DMA_CTRL_IRQ_EN_BIT 1

`define DMA_STAT_BUSY_BIT 0
`define DMA_STAT_DONE_BIT 1
`define DMA_STAT_ERR_BIT  2

`define DMA_CLR_DONE_BIT 0
`define DMA_CLR_ERR_BIT  1

// LED/UART MMIO base and offsets
`define IO_BASE_ADDR       32'h4000_1000
`define IO_LED_OFFSET      32'h0000_0000
`define IO_UART_TX_OFFSET  32'h0000_0004
`define IO_UART_STAT_OFFSET 32'h0000_0008
`define IO_SEG_OFFSET      32'h0000_000C
`define IO_BTN_OFFSET      32'h0000_0010

`define IO_ADDR_MASK   32'hFFFF_FFE0
`define IO_ADDR_MATCH  32'h4000_1000

`define IO_LED_WIDTH 16
`define IO_UART_STAT_BUSY_BIT 0
`define UART_DIV 868

`ifndef MEM_INIT_FILE
`define MEM_INIT_FILE ""
`endif

`ifndef MEM_RESET_CLEARS
`define MEM_RESET_CLEARS 1
`endif


// CSR addresses
`define CSR_MSTATUS 12'h300
`define CSR_MIE     12'h304
`define CSR_MTVEC   12'h305
`define CSR_MEPC    12'h341
`define CSR_MCAUSE  12'h342
`define CSR_MIP     12'h344
`define CSR_MHARTID 12'hF14

// CSR bits
`define MSTATUS_MIE_BIT 3
`define MIE_MEIE_BIT    11
`define MIP_MEIP_BIT    11

// mcause encoding
`define MCAUSE_MEI 32'h8000_000B

// MUL/DIV op encoding
`define MULDIV_OP_MUL    3'd0
`define MULDIV_OP_MULH   3'd1
`define MULDIV_OP_MULHU  3'd2
`define MULDIV_OP_MULHSU 3'd3
`define MULDIV_OP_DIV    3'd4
`define MULDIV_OP_DIVU   3'd5
`define MULDIV_OP_REM    3'd6
`define MULDIV_OP_REMU   3'd7

// Custom-0 opcode and sub-encoding (RV32 custom extension).
`define OPCODE_CUSTOM0 7'b0001011
// Custom-1 opcode (offload/control).
`define OPCODE_CUSTOM1 7'b0101011

`define CUST3_DOTMAC 3'b000
`define CUST3_ADDSUB 3'b001
`define CUST3_MISC   3'b010
`define CUST3_SHIFT  3'b011
`define CUST3_PACK   3'b100
`define CUST3_PERM   3'b101
`define CUST3_RELU   3'b110

// Custom-0 funct7 sub-ops (R-type unless noted).
`define CUST7_DOT4_SS   7'b0000000
`define CUST7_DOT4_SU   7'b0000001
`define CUST7_DOT4_UU   7'b0000010

`define CUST7_ADD8      7'b0000000
`define CUST7_SUB8      7'b0000001
`define CUST7_ADDSAT8   7'b0000010
`define CUST7_SUBSAT8   7'b0000011

`define CUST7_MAX8      7'b0000000
`define CUST7_MIN8      7'b0000001
`define CUST7_ABS8      7'b0000010
`define CUST7_AVG8      7'b0000011
`define CUST7_ADD16     7'b0000100
`define CUST7_ADDSAT16  7'b0000101

// Shift/round/clamp (I-type, funct3=CUST3_SHIFT, sub-op in imm[11:5]/funct7).
`define CUST7_SHL8I     7'b0000000
`define CUST7_SHR8I     7'b0000001
`define CUST7_SRU8I     7'b0000010
`define CUST7_RSHR8I    7'b0000011
`define CUST7_CLAMP8I   7'b0000100

`define CUST7_PACKB     7'b0000000
`define CUST7_UNPK8L_S  7'b0000001
`define CUST7_UNPK8H_S  7'b0000010
`define CUST7_PACKH     7'b0000011

`define CUST7_REV8      7'b0000000
`define CUST7_SWAP16    7'b0000001

`define CUST7_RELU8     7'b0000000

// Custom-1 funct3 sub-ops (offload/control).
`define CUST1_START  3'b000
`define CUST1_POLL   3'b001
`define CUST1_WAIT   3'b010
`define CUST1_CANCEL 3'b011
`define CUST1_FENCE  3'b100
`define CUST1_GETERR 3'b101
`define CUST1_SETCFG 3'b110
`define CUST1_GETCFG 3'b111

`endif
