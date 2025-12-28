# UART/DMA Demo 失效定位记录（IF/内存接口时序问题优先）

## 背景
用于向 A 汇报板上现象与仿真证据，定位导致 UART/DMA demo 失败的核心原因。

## 板上复现与 mem 反馈（按测试顺序）
- `mem/demo_dma_irq.mem`：LED0 常亮（与 demo 预期一致），LED1 未亮。
- `mem/demo_dma_uart.mem`：UART 有输出但内容异常（出现 0x93+全 0 / 0x55 / 0xF0 / 0xA5 等常量），非棋盘格。
- `mem/uart_ramp.mem`：期望 00..FF，实测全 00。
- `mem/uart_const_5a.mem`：期望 0x5A，实测全 00（如需可复核）。
- `mem/uart_const_03_led.mem`：LED0+LED1 常亮，UART 回传全 0x03（基准正常）。
- `mem/uart_ramp_nomht.mem`：去除 mhartid 后仍全 00。
- `mem/uart_dmem_src_nomht.mem`：期望 64B 00..3F，脚本 size=64 仍无输出。
- `mem/uart_seq_imm.mem`：期望 00 11 22 .. FF，实测 `00` 后全 `FF`。

## 排查过程（如何定位）
- 指令解码核查：所有 demo/调试镜像仅用 LW/SW，没有 LB/SB。
- 去除 mhartid 分支：仍失败 → 排除 CSR 分支路径。
- 只用“立即数→sw”的串口序列测试：仍失败 → 聚焦 store-data 路径。
- 仿真 TB 复现：`tb/tb_uart_seq_imm.sv` 捕获 UART 写入，第二个字节错误。

## 仿真证据（关键）
- `tb_uart_seq_imm` 输出：
  - `uart[0]=0x00`
  - `uart[1]=0x00`（期望 0x11）
  - 触发 `$fatal`
- 说明**执行到第二条 `addi x6,0x11` 时，UART 实际仍写出旧值**，与板上“00 后全 FF/全 00”一致。

## 新增仿真（排除通用 store-data hazard）
- 新增 `tb/tb_store_data_hazard.sv`（不依赖 UART/MMIO，仅对 RAM 连续 SW）。
- 结果：**无 NOP 情况也写入正确**（mem[0x200..0x20c] 均为 00/11/22/33）。
- 结论：**通用 store-data hazard 在 RAM 路径未复现**，问题更可能与 **MMIO 交互或指令取值时序**相关。

## 新增仿真（IFetch 与 BRAM 时序对齐）
- 新增 `tb/tb_ifetch_bram_align.sv`（soc_top + dualport_bram，检查 ifid_pc 对应指令是否一致）。
- 结果：出现 **ifid_pc 与 ifid_inst 不一致**。
- 实测日志：
  - `IF mismatch: pc=0x00000004 inst=0x00000063 exp=0x00200013`
  - `0x00000063` 为 hart1 在 `0x0000_0200` 的自旋指令（`beq x0,x0,0`），说明**当前 hart0 取指时读到了上一拍/另一 hart 的 BRAM 数据**。
- 说明：**同步 BRAM 的读数在下一拍有效，但 mem_ready 同拍返回**，CPU 在 `if_inst_valid` 为 1 时采到的是“上一拍的指令”，导致指令流错位。
- 运行方式：Vivado 设 `tb_ifetch_bram_align` 为 top，`launch_simulation` 即可复现。

## 仿真输出记录（原始日志）
### tb_uart_seq_imm（UART 第二字节错误）
```
uart[0]=0x00
uart[1]=0x00
Fatal: UART byte[1] mismatch: got 0x00 expected 0x11
Time: 326095 ns  Iteration: 0  Process: /tb_uart_seq_imm/Always35_32  Scope: tb_uart_seq_imm  File: D:/riscv_cpu/RiscV_CPU/tb/tb_uart_seq_imm.sv Line: 48
$finish called at time : 326095 ns
```

### tb_store_data_hazard（RAM 路径无 hazard）
```
mem[0x200]=0x00000000 mem[0x204]=0x00000011 mem[0x208]=0x00000022 mem[0x20c]=0x00000033
WARN: no hazard observed (unexpected)
mem[0x200]=0x00000000 mem[0x204]=0x00000011 mem[0x208]=0x00000022 mem[0x20c]=0x00000033
No-NOP hazard fixed (NOP inserted)
store-data hazard check completed
$finish called at time : 4075 ns : File "D:/riscv_cpu/RiscV_CPU/tb/tb_store_data_hazard.sv" Line 169
```

### tb_ifetch_bram_align（IFetch/BRAM 对齐失败）
```
IF mismatch: pc=0x00000004 inst=0x00000063 exp=0x00200013
Fatal: IFetch pc/inst mismatch (BRAM ready/rdata misalignment)
Time: 60 ns  Iteration: 0  Process: /tb_ifetch_bram_align/Always73_35  Scope: tb_ifetch_bram_align.Block73_36  File: D:/riscv_cpu/RiscV_CPU/tb/tb_ifetch_bram_align.sv Line: 84
$finish called at time : 60 ns
```

## 结论
- 根因更可能是 **IF/内存接口的时序对齐问题**（同步 BRAM + MMIO 混合访问），导致指令流重复/错位，从而出现“第二个立即数未生效”的现象。
- 结合证据：`tb_uart_seq_imm` 在 soc_top + BRAM 环境失败，而纯 RAM 路径的 store-data hazard 仿真未复现。
- 新增证据：`tb_ifetch_bram_align` 直接复现 **ifid_pc/ifid_inst 不一致**，指向 mem_ready/BRAM 时序不匹配。
- 与 LB/SB 未实现无关；与 mhartid/CSR 分支无关；UART MMIO 本身可用（0x03 demo 证明）。

## A 需要关注的核心点
- **IF 与 mem_ready/mem_rdata 对齐**：当前 BRAM 为同步读，但 CPU 逻辑按“当拍返回”使用；需要统一为“请求-响应”时序。
- **MMIO 读写与 IF 共享单口的时序**：确认 data access 抑制 IF 时，PC/IFID 是否保持，避免指令重复/丢失。
- 如需快速验证：统一 MMIO/BRAM 都加 1-cycle response 或为 load-use 插入固定 stall。
