# 并行验证与板级回传汇总

## 1. 现状结论
- 仿真侧已经有**可展示的并行证据**：`tb_dma_muldiv_parallel` 的日志中出现 DMA busy 与 MULDIV busy 的明确重叠，并打印了重叠周期与计数器在 DMA busy 期间仍递增的记录（证明 CPU 与 DMA 并行）。
- MUL/DIV 功能在仿真中可完成并得到正确结果，DMA 复制也能完成（详情见下文 TB 记录）。
- 板级回传仍存在**波特率/帧同步导致的内容不稳定**与“先开脚本再复位才不丢帧”等现象；LED/数码管极性调整后仍需最终板级确认。

## 2. 仿真（TB）记录摘要
以下是“多次 TB”里具有代表性的结果与关键信息：

### 2.1 并行性证明（核心证据）
- TB：`tb/tb_dma_muldiv_parallel.sv`
- 输出节选（来自 `tcl.txt`）：
  ```
  MULDIV start: t=585000 cycle=56 op=0 hart=0 a=0x0000000a b=0x00000003
  DMA busy start: t=775000 cycle=75
  OVERLAP: DMA busy + MULDIV busy at t=775000 cycle=75
  COUNT update while DMA busy: t=905000 cycle=88 count=1
  ...
  DMA busy end  : t=3335000 cycle=331
  SUMMARY: dma_busy_cycles=256 muldiv_start=9 muldiv_done=9 overlap_cycles=196 first_overlap_cycle=75
  dma + muldiv parallel demo completed
  ```
- 说明：日志里明确记录“DMA busy + MULDIV busy”的重叠周期，以及 DMA busy 期间 CPU 计数器不断更新，属于**直接可展示的并行证据**。

### 2.2 DMA/CPU 与 MUL/DIV 相关 TB（补充）
- `tb/tb_dma_cpu_parallel.sv`：原先的 dma/cpu 并行 testbench，`summarize` log 里仍然会打印“dma/cpu parallel test passed” 和每个内存单元的 final 值；本轮 bring-up 没改该 tb，仅引用其运作证明 DMA 独立于 hart1 循环。
- `tb/tb_demo_muldiv.sv`：验证 hart0 MUL/DIV/REM 结果与 hart1 自旋递增 x10，日志里 `hart0 x3=30 x4=3 x5=1`，`hart1 x10` 不断增加，说明调度器允许 hart1 继续运行，muldiv handshake 可复原。
- `tb/tb_dma_muldiv_parallel.sv`：新增 testbench，结合 hart0 MUL/DIV 与 hart1 DMA 拷贝并打印“OVERLAP”、“COUNT update while DMA busy”、“SUMMARY” 等输出，为本轮并行证明提供直观 log。该 tb 依赖 `tb_dma_cpu_parallel.sv` 的内存/寄存器布局并扩展了周期监测。

### 2.3 关键失败/异常 TB（历史记录）
- `tb/tb_ifetch_bram_align.sv`：曾出现 `IF mismatch`（ifetch/ready 对齐问题），后续出现 “PASS: no IF mismatch observed over 176 fetches”。
- `tb/tb_uart_seq_imm.sv` / `tb/tb_uart_seq_imm_h0.sv`：多次遇到 `Fatal: hart0 never reached PC=0x00000008 (LUI)` 或 `UART byte mismatch`。
- `tb/tb_store_data_hazard.sv`：报告 `WARN: no hazard observed (unexpected)`，表示原先假设的 hazard 没被触发。

## 3. 板级 MEM 烧录与回传记录（重点现象）
以下为**多次烧录/回传的代表性现象**（节选，不含每一次重复）：

| mem 文件 | 现象/输出（节选） | 备注 |
|---|---|---|
| `mem/demo_dma_irq.mem` | LED0 常亮/不闪，LED1 不亮 | 早期 demo 表现一致 |
| `mem/demo_dma_uart.mem` | 回传内容多次变化，如 `83a38400e31e04fe...`、`0000ffffffff...`，不同波特率下变化明显 | 指向波特率/分频不一致问题 |
| `mem/uart_ramp.mem` / `mem/uart_ramp_nomht.mem` | 回传全 0 | 读写链路可能不生效 |
| `mem/uart_const_03_led.mem` | LED0/LED1 常亮；回传 `03` 重复 | 符合预期 |
| `mem/uart_dmem_src_nomht.mem` | 无回传 | 疑似未触发 UART 或程序未跑通 |
| `mem/uart_seq_imm.mem` | 输出长度不稳定，出现 `0011223344001122...` 或仅 32 字节 | 需帧头捕获逻辑 |
| `mem/uart_seq_imm_h0.mem` | 4 字节可得 `00112233`，完整帧曾确认为 `0011223344114477aaddff` | 有截断现象 |
| `mem/demo_uart_src.mem` | 回传全 0 | 源数据读取不正确 |
| `mem/demo_btn_uart_parallel_flat.mem` | S0 触发回传，内容如 `0002000004060000080a...`，按键触发有效 | 并行演示程序（仍需板级稳定性确认） |

补充现象：
- 若先烧录再开脚本，UART 会“过早输出导致错过帧”，**必须先开脚本再复位**。
- 波特率测试下回传模式差异明显（例如 115200/57600/230400 等均呈现不同花样），估算波特率约 **~54 kbps**，与预期不一致。

## 4. docs 内相关更新情况
与这轮 bring-up/排查相关的文档已更新（重点说明具体内容）：
- `docs/memory_map.md`：精确列出 `IO_LED`, `IO_UART_TX`, `IO_UART_STAT`, `IO_SEG`, `IO_BTN` 的偏移与行为，还补充了 `DMA` 及 `IO` 寄存器的 access 约束（字/半字/字节区分、DONE/ERR 的清除逻辑）。
- `docs/SPEC.md`：扩写了 CPU ↔ DMA/IRQ/IO 接口的 contract，明确了 `muldiv` handshake/policy、DMA MMIO 的 ERR/DONE/IRQ 行为、LED + UART + BTN 的 MMIO 阅读/写入约定，确保硬件与软件都知道各寄存器作用。
- `docs/csr_load_hazard_issue.md`：汇总了 UART 相关 tb/mem 的失败日志（如 `uart_seq_imm` 中 `Fatal: hart0 never reached PC=0x00000008`、`tb_store_data_hazard` 预期未出现 hazard），以便 A 侧复查风险。
- `docs/uart_seq_imm_h0_deadlock.md`：详细记录 `uart_seq_imm_h0` 硬件上回传不稳定、脚本需先启动再复位的时序问题，提供检查点与排查方向。
- `README.md`/`docs/DELIVERY_MEMBER_B.md`：更新了 flash 流程（如先启动监听脚本再复位）、按钮触发 DMA UART（S0 控制逻辑）、LED/SEG 心跳描述，以及依赖的 python 脚本说明。

## 5. A 侧内容修改清单（需 A review/确认）
以下属于 A 侧（CPU core 控制/调度/CSR/trap）或共享接口相关文件。这里按“实际功能改动”与“格式/无功能改动”区分说明：

### 5.1 有明确功能改动的内容
- `rtl/core/barrel_sched.v`：
  - 新增 `hold` 输入；当 `hold=1` 时不更新 `last_hart`，避免 mem_stall 时错误切换 hart。
  - 调度逻辑仍为 2-hart round-robin + blocked skip，但加入 `hold` gating。
- `rtl/core/cpu_top.v`：
  - 增加 IFetch in-flight 追踪：`ifetch_req/ifetch_hart_d/ifetch_pc_d`，以及 per-hart `ifetch_kill`。
  - 当 trap/mret/branch 发生且 IFetch 尚未返回时，标记 `ifetch_kill`，确保“过期的取指响应”不会写回 ifid（修复 `tb_ifetch_bram_align` 对齐问题）。
  - 增加 `mem_req_d/mem_is_data_d`，把 `mem_ready` 对齐到上一拍发出的请求，区分 ifetch/data 两类返回。
  - 增加 `data_grant` 优先级：当 data 请求存在且当前没有 ifetch in-flight 时优先发出 data 访问，避免取指/数据冲突导致 ready 错配。
  - `fetch_issue` 选择逻辑改为“每 hart 独立若 ifid_valid 为空则可发起”，并在 trap/mret/branch 时阻止新的 fetch。
- `rtl/defines.vh`（共享接口）：
  - 新增 `IO_SEG_OFFSET` 与 `IO_BTN_OFFSET`，配合 LED/UART/MMIO 扩展（与文档/驱动一致）。

### 5.2 仅格式或无功能变化的内容
- `rtl/core/csr_file.v`
- `rtl/core/ex_stage.v`
- `rtl/core/hazard_fwd.v`
- `rtl/core/id_stage.v`
- `rtl/core/if_stage.v`
- `rtl/core/mem_stage.v`
- `rtl/core/regfile_bank.v`
- `rtl/core/trap_ctrl.v`
- `rtl/core/wb_stage.v`
- `rtl/interface.vh`

说明：5.2 列出的文件 diff 主要是换行/格式差异，本轮 bring-up 未引入新逻辑；但由于这些文件属于 A 侧或共享接口，仍建议 A review 以确认无意外副作用。

## 6. 证据文件位置
- 仿真输出：`tcl.txt`
- TB 文件：`tb/tb_dma_muldiv_parallel.sv` 等
- 板级记录：本文件第 3 节记录 + 你本地 UART 脚本/截图
