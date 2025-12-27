# UART/DMA Demo 失效定位记录（store-data hazard 已证实）

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
- 说明 `addi x6,0x11` 紧跟 `sw x6, UART_TX` 时，`sw` 读到的仍是旧的 x6。

## 结论
- 根因是 **store-data hazard/forwarding 缺失或时序不对**：`sw` 的 rs2 数据没有拿到前一条指令的新值。
- 与 LB/SB 未实现无关；与 mhartid/CSR 分支无关；UART MMIO 本身可用（0x03 demo 证明）。
- 可能仍存在 load-use/同步读对齐问题，但单就 store-data hazard 已足以解释当前失败现象。

## A 需要关注的核心点
- `rtl/core/hazard_fwd.v`：是否对 store 的 rs2 做了正确前递（EX/MEM/WB）。
- `rtl/core/cpu_top.v`：`exmem_rs2_val` 是否真正使用了前递值。
- 若必要：对 “写后紧跟 store” 插入 1-cycle stall 或实现 EX->store 前递。
