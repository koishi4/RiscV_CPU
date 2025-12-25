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

`endif
