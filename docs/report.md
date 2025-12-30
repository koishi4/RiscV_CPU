# 项目更新报告 (2025-12-26)

## 目标与结论
- 已完成仿真链路、DMA/中断/双 Hart 演示与板级外设（LED/UART）的集成。
- Bitstream 已成功生成，上板验证待完成。

## 主要功能新增/增强
- 新增 LED/UART MMIO 外设与地址解码：
  - `rtl/periph/led_uart_mmio.sv`：LED 寄存器 + UART TX（固定分频 `UART_DIV`）。
  - `rtl/periph/mmio_fabric.v`：在原 DMA MMIO 解码基础上新增 IO 区域。
  - `rtl/soc_top.v`：新增 `led` 与 `uart_tx` 顶层端口并连接外设。
- 新增板级演示镜像：
  - `mem/demo_dma_irq.mem`：DMA 完成中断触发 ISR 点亮 LED0。
- 扩展仿真用例与脚本：
  - 新增测试：`tb/tb_ex_stage.sv`、`tb/tb_hazard_fwd.sv`、`tb/tb_forwarding.sv`、`tb/tb_demo_mem_wait.sv`、`tb/led_uart_mmio_tb.sv` 等。
  - `tb/run_sims.tcl`、`tb/run_all.tcl` 更新为批量覆盖新增测试。

## 关键问题修复
- **BRAM 推断与资源超标**：
  - `rtl/mem/dualport_bram.sv` 改为双 always（每端口独立写），同步读/ready，并添加 `ram_style="block"`。
  - 解决 Vivado 无法推断 RAM 导致 LUT/FF 资源爆表的问题。
  - `tb/mem_concurrency_tb.sv` 读写任务改为等待 `*_mem_ready`，匹配同步 RAM 时序。
- **组合环（Combinatorial Loop）**：
  - `rtl/core/cpu_top.v` 将取指 `if_valid` 从 `pipe_stall/trap_set` 组合依赖中解耦，使用 `trap_set_raw` 直接门控，切断 `mem_ready` 组合回环。

## 文档与可用性更新
- `docs/memory_map.md`：新增 LED/UART MMIO 区域说明。
- `docs/SPEC.md`：补充 LED/UART MMIO 访问语义、内存初始化宏说明。
- `docs/硬件综合设计方案.md`：补充 demo2 变体与 IO LED 行为描述。
- `README.md`：
  - 增加 GUI 上板流程与宏定义说明。
  - 强调 `MEM_RESET_CLEARS=0` 以确保 BRAM 推断与程序保留。

## 重要编译/综合宏
- `MEM_INIT_FILE="mem/demo_dma_irq.mem"`：加载演示程序。
- `MEM_RESET_CLEARS=0`：复位不清 RAM（避免推断失败/资源爆炸）。

## 仿真与验证状态
- 用户多次运行 `tb/run_sims.tcl`：**ALL PASSED**（包含 demo/回归测试）。
- Bitstream 已生成：**通过**。
- 板级验证：**待进行**（LED0 点亮 + DMA IRQ）。

## 待办与风险
- 板级验证：确认 LED0 亮、DMA 拷贝数据正确、UART TX 输出可观测。
- 如仍遇到综合时资源异常，请确认：
  - 工程使用最新 `rtl/mem/dualport_bram.sv`。
  - `MEM_RESET_CLEARS=0` 已正确设置。

## 文件变更摘要（关键）
- RTL：`rtl/soc_top.v`, `rtl/periph/mmio_fabric.v`, `rtl/periph/led_uart_mmio.sv`,
  `rtl/mem/dualport_bram.sv`, `rtl/core/cpu_top.v`
- TB：`tb/run_sims.tcl`, `tb/run_all.tcl`, `tb/mem_concurrency_tb.sv`,
  `tb/tb_demo_dma_irq.sv`, `tb/led_uart_mmio_tb.sv`, `tb/tb_demo_mem_wait.sv`, 等
- Docs：`docs/SPEC.md`, `docs/memory_map.md`, `docs/硬件综合设计方案.md`
- Program：`mem/demo_dma_irq.mem`
