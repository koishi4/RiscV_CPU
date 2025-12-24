# Member B Delivery Notes

Scope: `muldiv_unit`, `dma_engine`, `dualport_bram`, and DMA IRQ behavior.
Interfaces and constants are defined in `rtl/interface.vh` and `rtl/defines.vh`.

## 1) muldiv_unit
File: `rtl/accel/muldiv_unit.sv`

- Handshake: `start` is accepted only when not busy; `start` while busy is ignored.
- `busy` is high from accept(start) until `done`.
- `done` is a single-cycle pulse; `result`, `done_hart_id`, `done_rd` are stable when `done=1`.
- Supported ops: `MUL`, `MULH`, `MULHU`, `MULHSU`, `DIV`, `DIVU`, `REM`, `REMU`.
- Divide by zero and signed overflow behavior follows RV32M.
- Latency (fixed): `MUL` = 4 cycles, `DIV/REM` = 32 cycles (single-issue, not pipelined).

Testbench: `tb/muldiv_tb.sv` (directed + 1000 random vectors).

## 2) dma_engine
File: `rtl/periph/dma_engine.sv`

- MMIO map per `docs/memory_map.md` (SRC/DST/LEN/CTRL/STAT/CLR).
- Word-only MMIO writes; byte/halfword writes are not supported.
- Copy loop: read(src) -> write(dst) -> src+=4, dst+=4, len-=4 until len==0.
- `START` while busy is ignored.
- `LEN==0` results in immediate DONE.
- ERR conditions: unaligned SRC/DST/LEN or SRC/DST in DMA MMIO range.
- DONE/ERR are sticky until DMA_CLR (write-1-to-clear).
- IRQ pending (`dma_irq`) goes high when DONE and IRQ_EN, and stays high until DMA_CLR.
- Throughput (ideal memory ready=1): one word per 2 cycles (read + write).

Testbench: `tb/dma_tb.sv` (directed + randomized; includes IRQ sticky/clear checks).

## 3) dualport_bram
File: `rtl/mem/dualport_bram.sv`

- True dual-port RAM; ports A and B are independent.
- `*_ready` asserts when `*_req` is asserted (no combinational loops).
- Same-cycle same-address writes: port B has priority (deterministic).
- Memory is cleared on reset (testbench-friendly model).

Testbench: `tb/mem_concurrency_tb.sv`
- Directed: port A writes region A while port B copies region B.
- Deterministic: same-address write priority (B wins).
- Randomized: concurrent reads/writes in disjoint regions.

## 4) Demo Notes
- Demo2 (mul/div latency hiding): MUL=4 cycles, DIV/REM=32 cycles; 1 op in flight.
- Demo3 (DMA + IRQ): DONE+IRQ_EN raises level `dma_irq`, cleared only by DMA_CLR.
