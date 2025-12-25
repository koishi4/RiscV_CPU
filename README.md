# RISC-V 双 Hart SoC (RV32I+M) 带 DMA + 中断 + LED/UART

本仓库实现了一个基于桶形调度（Barrel-scheduled）的双 Hart RV32 核心，配备多周期乘除（MUL/DIV）单元、DMA 引擎以及 DMA 完成中断。此外还包含一个简单的 LED/UART MMIO 模块，用于开发板演示。

## 快速仿真 (Vivado 2024.2)

* **Windows:**
* `E:\vivado\Vivado\2024.2\bin\vivado.bat -mode batch -source F:/Projects/VivadoProject/RiscV_CPU/tb/run_sims.tcl`


* **Linux:**
* `vivado -mode batch -source tb/run_sims.tcl`



## 开发板启动 / 上板测试 (EGO1)

默认的开发板演示程序使用 DMA + 中断（IRQ），并在中断服务程序（ISR）中点亮 LED0。

1. 打开 Vivado 2024.2。
2. 创建一个工程（或打开 `vivado_prj/vivado_prj.xpr`），将顶层（top）设置为 `soc_top`。
3. 添加源文件：
* `rtl/**/*.v`, `rtl/**/*.sv`
* `constraints/ego1.xdc`
* `mem/demo_dma_irq.mem`


4. 设置 Verilog 宏定义（Project Settings → Verilog Options）：
* `MEM_INIT_FILE="mem/demo_dma_irq.mem"`
* `MEM_RESET_CLEARS=0`


5. 生成比特流（Bitstream）并烧录到开发板。
6. 按下复位键。DMA 完成并运行 ISR 后，LED0 应当亮起。

**注意：**

* `rtl/defines.vh` 中的 `UART_DIV` 是针对 **100 MHz** 时钟 → **115200** 波特率设置的。如果您的时钟频率不同，请相应调整。
* `rst_n` 会清除 CPU 状态；设置 `MEM_RESET_CLEARS=0` 后，程序内存在复位时将保持初始化状态（不会被清除）。

## IO 内存映射（快速参考）

* DMA MMIO 基地址: `0x4000_0000` (详见 `docs/memory_map.md`)
* LED/UART MMIO 基地址: `0x4000_1000`
* `IO_LED`   @ `0x4000_1000` (读写, LED[15:0])
* `IO_UART_TX` @ `0x4000_1004` (写, 非忙状态下发送字节)
* `IO_UART_STAT` @ `0x4000_1008` (读, bit0 = TX 忙)



## 更新演示程序

开发板演示镜像文件为 `mem/demo_dma_irq.mem`（readmemh 格式）。如果您编译自己的程序，请生成 **32 位字宽**的 hex 文件，并将 `MEM_INIT_FILE` 设置为其路径。

## 文档

* 系统规范: `docs/SPEC.md`
* 内存映射: `docs/memory_map.md`
* 硬件综合设计方案: `docs/硬件综合设计方案.md`

