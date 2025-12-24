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

### 4.5 DMA <-> Memory
- Same memory interface shape as CPU (`mem_req/we/addr/wdata`, `mem_rdata/ready`).
- DMA copies 32-bit words; LEN is in bytes.

## 5. Reset/clock
- Single system clock `clk`.
- Active-low reset `rst_n` (modules may treat as synchronous internally).
- Reset vector: `RESET_VECTOR` from `rtl/defines.vh`.

## 6. Module boundaries
- `rtl/core/*`: CPU pipeline, scheduler, CSR/trap (Member A)
- `rtl/accel/*`: muldiv unit (Member B)
- `rtl/periph/*`: DMA, MMIO decode, IRQ router (Member B)
- `rtl/mem/*`: memory subsystem (Member B)

## 7. Open items
- Memory size is parameterized via `MEM_SIZE_BYTES` (default 64KB).
