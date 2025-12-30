# RISC-V 2-Hart SoC Spec (Skeleton)

## 1. One-line goal
Deliver a demonstrable SoC-like system where 2-hart barrel scheduling hides long latency (MUL/DIV, memory waits), DMA runs in parallel, and DMA-done raises a machine external interrupt.

## 2. CPU baseline
- ISA: RV32I + RV32M + minimal SYSTEM for machine-mode interrupt.
- Fixed 2 harts (hart0, hart1). Barrel scheduling round-robin; skip blocked hart(s).
- Per-hart architectural state: PC, RegFile[32], CSR/trap state (mepc/mcause/mstatus/mie/mip), mhartid=0/1.

## 3. CSR minimal set
Addresses are per RISC-V spec (see `rtl/defines.vh`).
- mhartid (RO)
- mtvec (direct mode only)
- mepc, mcause
- mstatus: implement MIE (bit 3)
- mie/mip: implement MEIE/MEIP (bit 11)
- Trap return: mret

## 4. External interfaces (contracts)
Signals are defined in `rtl/interface.vh` and widths/constants in `rtl/defines.vh`.

### 4.1 CPU <-> Memory (data/instruction)
- Request: `mem_req`, `mem_we`, `mem_addr`, `mem_wdata`
- Response: `mem_rdata`, `mem_ready`
- `mem_addr` is byte address; 32-bit word accesses are assumed aligned.
- `mem_ready=1` means read data is valid or write accepted in that cycle.

### 4.2 CPU <-> MUL/DIV
- Request: `start`, `op`, `a`, `b`, `hart_id`, `rd`
- Response: `busy`, `done`, `result`, `done_hart_id`, `done_rd`
- CPU policy: assert `start` for 1 cycle, set `blocked[hart]=1` immediately, clear on `done` and write result to RegFile.

### 4.3 CPU <-> IRQ (DMA done)
- `ext_irq` is a level-sensitive external interrupt pending signal.
- Trap is taken only if `mstatus.MIE=1` and `mie.MEIE=1`.
- `mcause` uses machine external interrupt encoding (0x8000000B).

### 4.4 DMA MMIO
- Memory-mapped at `DMA_BASE_ADDR` (see `docs/memory_map.md`).
- Registers: SRC/DST/LEN/CTRL/STAT/CLR.
  - Word-only MMIO writes (32-bit); byte/halfword writes are not supported.
  - `START` while DMA is busy is ignored.
  - `LEN==0` results in immediate DONE.
  - ERR is set for unaligned SRC/DST/LEN or if SRC/DST is within DMA MMIO range.
  - DONE/ERR are sticky until cleared by DMA_CLR (write-1-to-clear).
  - `dma_irq` is level-high when DONE and IRQ_EN; cleared only by DMA_CLR.

### 4.5 DMA <-> Memory
- Same memory interface shape as CPU (`mem_req/we/addr/wdata`, `mem_rdata/ready`).
- DMA copies 32-bit words; LEN is in bytes.
 - Ideal throughput: one word per 2 cycles (read then write).

### 4.6 LED/UART MMIO
- Memory-mapped at `IO_BASE_ADDR` (see `docs/memory_map.md`).
- IO_LED: read/write LED output register (drives `led[15:0]`).
- IO_UART_TX: write starts TX when not busy; ignored while busy.
- IO_UART_STAT: bit0 TX busy.
- IO_SEG: write 8-bit hex value (low nibble -> seg0, high nibble -> seg1).
- IO_BTN: read-only button state [4:0]; polarity may be inverted via `BTN_ACTIVE_LOW`.

## 5. Reset/clock
- Single system clock `clk`.
- Active-low reset `rst_n` (modules may treat as synchronous internally).
- Reset vector: `RESET_VECTOR` from `rtl/defines.vh`.

## 6. Module boundaries
- `rtl/core/*`: CPU pipeline, scheduler, CSR/trap (Member A)
- `rtl/accel/*`: muldiv unit (Member B)
- `rtl/periph/*`: DMA, MMIO decode, IRQ router (Member B)
- `rtl/mem/*`: memory subsystem (Member B)

## 8. Memory subsystem notes
- `dualport_bram` is a true dual-port RAM model with independent A/B ports.
- Same-cycle same-address writes resolve deterministically with port B priority.
- Optional init file support via `MEM_INIT_FILE`; set `MEM_RESET_CLEARS=0` to preserve contents across reset (board bring-up).

## 7. Open items
- Memory size is parameterized via `MEM_SIZE_BYTES` (default 64KB).

## 9. Demo programs
- Demo1: dual-hart correctness (independent loops -> separate memory -> check)
- Demo2: latency hiding (mul/div heavy on hart0, hart1 continues); optional memory-wait variant
- Demo3: DMA + interrupt (CPU config DMA, ISR clears DONE, mret)
