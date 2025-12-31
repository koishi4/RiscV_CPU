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
- 乘法实现：Radix-4 Booth + CSA 压缩树（Wallace/Dadda 风格），两拍完成（tree → final）。
- 乘法快路径：0/1/−1 等常见情况直接在接收 `start` 的同拍给出 `done`（busy 可能保持 0）。
- 除法实现：LZC 归一化后按 shift-sub 执行，每拍做 2 步（radix-4 类似），平均迭代显著减少。
- 除法快路径：除 0 / signed overflow / 2^k / a<b 直接同拍完成（busy 可能保持 0）。
- 典型延迟：MUL* 非快路径为 2 个处理拍；DIV/REM 为 `ceil((msb(a)-msb(b)+1)/2)` 拍。

Testbench: `tb/muldiv_tb.sv`（directed + 1000 random vectors，最新结果：PASS）。

## 2) dma_engine
File: `rtl/periph/dma_engine.sv`

- MMIO map per `docs/memory_map.md` (SRC/DST/LEN/CTRL/STAT/CLR).
- MMIO request is latched; `mmio_ready` pulses one cycle after `mmio_req` to avoid combinational loops.
- Optional demo throttle: `DMA_GAP_CYCLES` inserts idle cycles between read/write beats (default 0).
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
- Demo2 (mul/div latency hiding)：MUL 为两拍完成（tree→final），DIV/REM 为可变迭代；fast path 可在同拍完成，1 op in flight。
- Demo3 (DMA + IRQ)：DONE+IRQ_EN raises level `dma_irq`, cleared only by DMA_CLR。

## 5) Simulation Results (log snippets)
- `tb/tb_demo_muldiv.sv`：
  ```
  hart0 x3=30 x4=3 x5=1
  hart1 x10=34
  mul/div latency hiding demo passed
  ```
- `tb/tb_dma_cpu_parallel.sv`：
  ```
  dma/cpu parallel test passed
  ```
- `tb/tb_demo_dma_irq.sv`：
  ```
  dma_irq flag=1 led=0x0001
  dst[0]=0x11111111 dst[1]=0x22222222 dst[2]=0x33333333 dst[3]=0x44444444
  dma irq demo passed
  ```
- `tb/tb_demo_dual_hart.sv`：
  ```
  sum[0x100]=55 fib[0x200]=34
  dual-hart correctness demo passed
  ```
- `tb/tb_rv32i_basic.sv`：
  ```
  x1=0x00012000 x2=0x00001004 x3=0x0000000c
  x4=9 x5=0x00000028 x6=0x00000024 x7=0x00000033
  rv32i basic jal/jalr/lui/auipc passed
  ```
