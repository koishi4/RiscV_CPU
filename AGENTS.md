# AGENTS.md (Project)
> Scope: Entire repository
> Target: Codex-assisted development for a 2-hart RV32 core with MUL/DIV, DMA, and DMA-done interrupt.

## 0. One-line Goal
Deliver a demonstrable SoC-like system where:
- 2-hart barrel scheduling hides long latency (MUL/DIV, memory waits)
- DMA runs in parallel and raises an interrupt on completion
- The whole system is easy to explain, verify, and demo.

## 1. System Architecture (Authoritative)
### 1.1 CPU threading model
- Fixed 2 hardware threads ("harts"): hart0 and hart1
- Each hart has independent architectural state:
  - PC[2]
  - RegFile[2][32] (x0 hardwired to 0)
  - Per-hart CSR/trap state (at least: mepc/mcause/mstatus/mie/mip; mhartid=0/1)
- Barrel scheduling:
  - Default round-robin (0→1→0→1...)
  - If blocked[hart]==1 (e.g., MUL/DIV in-flight), skip that hart and continue issuing the other hart.

### 1.2 ISA / CSR minimal spec (do not drift)
- ISA baseline: RV32I + RV32M + minimal SYSTEM for machine-mode interrupt
- CSR minimal set (machine mode):
  - mhartid (RO, returns 0/1)
  - mtvec (direct mode only is acceptable)
  - mepc, mcause
  - mstatus: implement MIE bit (bit 3)
  - mie/mip: implement MEIE/MEIP (bit 11) for DMA-done external interrupt
- Trap return: mret

### 1.3 Multi-cycle MUL/DIV unit (handshake is contract)
- A dedicated muldiv_unit with handshake:
  - in: start, op, a, b, hart_id, rd
  - out: busy, done, result, done_hart_id, done_rd
- CPU policy:
  - On decode/execute of MUL/DIV: assert start, set blocked[hart]=1 immediately
  - Scheduler must skip blocked hart(s)
  - On done: write result into RegFile[done_hart_id][done_rd], clear blocked

### 1.4 DMA (MMIO + FSM) and interrupt contract
- DMA is memory-mapped at a fixed base (recommend: 0x4000_0000).
- Registers (32-bit, word aligned):
  - +0x00 DMA_SRC  (byte address)
  - +0x04 DMA_DST
  - +0x08 DMA_LEN  (bytes; word copy is OK but LEN is bytes)
  - +0x0C DMA_CTRL (bit0 START, bit1 IRQ_EN)
  - +0x10 DMA_STAT (bit0 BUSY, bit1 DONE, bit2 ERR)
  - +0x14 DMA_CLR  (write-1-to-clear DONE/ERR)
- DMA copy FSM (minimum):
  - read(src) → write(dst) → src+=4, dst+=4, len-=4 until len==0
- DMA done interrupt:
  - When DONE and IRQ_EN, raise external interrupt pending (MEIP in mip)
  - CPU takes trap only if mie.MEIE=1 and mstatus.MIE=1
  - ISR clears DMA done via DMA_CLR, then mret

## 2. Repository rules for Codex
### 2.1 “Interfaces are contracts”
Codex MUST NOT change interfaces silently.
Any change to:
- interface.vh / defines.vh
- MMIO map
- muldiv handshake
- CSR semantics
requires:
1) Update docs (SPEC/memory_map)
2) Update unit tests & demo tests
3) Mention in PR description / commit message

### 2.2 Ownership & boundaries
- CPU core control path / scheduling / CSR/trap: owned by Member A
- muldiv_unit, DMA engine, memory subsystem: owned by Member B
- Cross-editing other owner’s module internals is forbidden unless:
  - bug is proven with a minimal reproducible test, AND
  - owner is tagged in the PR description

### 2.3 Coding standards (RTL)
- SystemVerilog preferred (sv), Verilog acceptable if consistent
- Strongly recommended:
  - Use `logic` and `always_ff/always_comb`
  - One module per file, filename == module name
  - Explicit reset values for all stateful regs
  - No implicit latches (full assignment in comb blocks)
- Parameterize widths via a single header (e.g., `defines.vh`)

### 2.4 Test standards
Every feature PR must include:
- A unit testbench for the new module or new behavior
- At least one directed test AND one randomized/regression test (where feasible)
- A “golden check” (end-of-sim dump for reg/mem compare)

### 2.5 Definition of Done (DoD)
A change is “done” only if:
- RTL compiles
- Core RV32I smoke tests pass
- Dual-hart correctness test passes
- muldiv directed test passes (M extension subset you implement)
- DMA memcpy test passes
- DMA-done interrupt demo passes (mtvec + enable + ISR + mret)

## 3. Suggested directory layout (Codex should follow existing repo if present)
If the repo does not already define structure, prefer:
rtl/
  core/      (cpu, scheduler, regfile, csr, trap)
  accel/     (muldiv_unit)
  periph/    (dma, mmio decode, irq router)
  mem/       (dualport_bram or arbiter)
tb/
  tb_top.sv
  tests/     (rv32i_basic.S, demo_thread.S, demo_muldiv.S, demo_dma_irq.S)
docs/
  SPEC.md
  memory_map.md

## 4. Demo programs (non-negotiable for final)
- Demo1: dual-hart correctness (independent loops → write separate memory → check)
- Demo2: latency hiding (hart0 heavy mul/div; hart1 continues IO/counter)
- Demo3: DMA + interrupt (CPU config DMA, do work, ISR sets flag, mret)

## 5. How Codex should behave in this repo
- Prefer minimal changes, incremental commits
- When uncertain about an existing signal/semantics:
  - Search the repo first
  - Follow existing naming & handshake conventions
- Provide a short “what changed / why / how tested” note with each patch
- Never “paper over” a failing test; fix root cause or revert.

