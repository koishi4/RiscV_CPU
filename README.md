# RISC-V 双 Hart SoC (RV32I+M) 带 DMA + 中断 + LED/UART

本仓库实现了一个基于桶形调度（Barrel-scheduled）的双 Hart RV32 核心，配备多周期乘除（MUL/DIV）单元、DMA 引擎以及 DMA 完成中断。此外还包含一个简单的 LED/UART MMIO 模块，用于开发板演示。




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
* 若综合/实现提示 LUT/FF 资源严重超标，请确认 **MEM_RESET_CLEARS=0** 且 `dualport_bram` 推断为 BRAM（避免将 64KB RAM 展开为触发器）。

## IO 内存映射（快速参考）

* DMA MMIO 基地址: `0x4000_0000` (详见 `docs/memory_map.md`)
* LED/UART MMIO 基地址: `0x4000_1000`
* `IO_LED`   @ `0x4000_1000` (读写, LED[15:0])
* `IO_UART_TX` @ `0x4000_1004` (写, 非忙状态下发送字节)
* `IO_UART_STAT` @ `0x4000_1008` (读, bit0 = TX 忙)
* `IO_SEG` @ `0x4000_100C` (写, 数码管 8 位十六进制显示，扫描输出，左起高位[31:28]到右起低位[3:0])
* `IO_BTN` @ `0x4000_1010` (读, 按键状态 [4:0])

**数码管说明：**
* EGO1 板上数码管为共阴极，段选高电平有效；`soc_top` 里默认 `SEG_ACTIVE_LOW=0`、`SEG_AN_ACTIVE_LOW=0`（见 `rtl/soc_top.v`）。若出现“全部显示 8、叠影”，请尝试把 `SEG_AN_ACTIVE_LOW` 取反。
* 当前 `soc_top` 设置 `SEG_UPDATE_DIV=0`（实时显示）。若显示变化过快，可增大该值以进行节流。
* 按键极性默认 **高有效**（`BTN_ACTIVE_LOW=0` + XDC 内部下拉）；若按键无响应，可切换为低有效并改回上拉。
* 若显示异常，请优先确认 AN0–AN7 约束是否正确，再尝试翻转极性参数。


## 更新演示程序

开发板演示镜像文件为 `mem/demo_dma_irq.mem`（readmemh 格式）。如果您编译自己的程序，请生成 **32 位字宽**的 hex 文件，并将 `MEM_INIT_FILE` 设置为其路径。

## 并行性演示（按键触发 UART 回传）

`mem/demo_btn_uart_parallel_flat.mem`：
- hart0：数码管递增显示 + LED0 心跳
- hart1：按下按钮触发 UART 回传固定字节序列
- 回传过程中 hart0 仍持续运行，体现双 hart 并行

## MUL/DIV + DMA + 数码管/LED 演示

`mem/demo_muldiv_dma_seg.mem`：
- hart0：持续 MUL/DIV 计算，把结果写入数码管（2 位十六进制）
- hart0：通过共享内存更新 LED0 心跳
- hart1：循环触发 DMA，LED1 显示 DMA busy 状态

## 斐波那契 + DMA + UART + 多位数码管

`mem/demo_fib_dma_uart_seg.mem`：
- hart0：计算 Fibonacci（32-bit），结果写入 IO_SEG（8 位十六进制显示）
- hart0：更新 LED0 心跳（共享内存位）
- hart1：按键触发 DMA（内存拷贝），LED1 在 DMA busy 时点亮
- hart1：按键触发 UART 回传 DMA 拷贝后的固定图案

## 文档

* 系统规范: `docs/SPEC.md`
* 内存映射: `docs/memory_map.md`
* 硬件综合设计方案: `docs/硬件综合设计方案.md`
