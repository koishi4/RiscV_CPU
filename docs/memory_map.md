# Memory Map (Skeleton)

All addresses are byte addresses. 32-bit accesses are assumed word-aligned.

## 1. RAM
- Base: 0x0000_0000
- Size: `MEM_SIZE_BYTES` (default 0x0001_0000 = 64KB)
- End : Base + Size - 1

## 2. DMA MMIO (base 0x4000_0000)
| Address Offset | Name     | Description                       |
|---------------|----------|-----------------------------------|
| 0x00          | DMA_SRC  | Source address (byte address)     |
| 0x04          | DMA_DST  | Destination address (byte address)|
| 0x08          | DMA_LEN  | Length in bytes                   |
| 0x0C          | DMA_CTRL | bit0 START, bit1 IRQ_EN           |
| 0x10          | DMA_STAT | bit0 BUSY, bit1 DONE, bit2 ERR    |
| 0x14          | DMA_CLR  | write-1-to-clear DONE/ERR         |

DMA MMIO address range: 0x4000_0000 - 0x4000_001F.

Notes:
- MMIO registers are word-only writes; byte/halfword writes are not supported.
- When DMA_LEN == 0, a START is treated as a no-op and DONE is set immediately.
- Unaligned SRC/DST/LEN or a SRC/DST within DMA MMIO range causes ERR and immediate DONE.
