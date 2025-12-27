# CSR / Load 冒险导致 UART/DMA Demo 失效（给 A 的问题说明）

## 现象与证据
- `mem/uart_const_03_led.mem` 正常：LED0+LED1 常亮，UART 持续回传 `0x03`。
- 任何依赖 `mhartid` 或 dmem 读取的程序都失败：
  - `mem/demo_dma_uart.mem`
  - `mem/demo_uart_src.mem`
  - `mem/uart_ramp*.mem`
- 失败时 UART 回传内容表现为**固定常量**（例如全 `0x00` / `0xA5` / `0x55`），且 LED1 不亮。
- 相同硬件、相同 `uart.py`，`0x03` 程序可用 → **UART、LED、时钟、bitstream 基本正常**。

## 初步结论
问题不在外设或脚本，**在 CPU 核心的 CSR 读/分支 或 dmem 同步读数据的冒险处理**。

## 最可能根因（至少命中一项）
1) **CSR 读（`csrrs mhartid`）结果未及时写回/转发**
- 程序常见模式：`csrrs a0, mhartid` 后立即 `bnez a0, ...`。
- 若 CSR 结果下一拍才有效，而分支用旧值（常为 0），则两 hart 都走 hart0 分支。
- 这可以解释：LED1 永远不亮、DMA/UART 走错路径、缓冲区地址错误。

2) **dmem 为同步读，但核心当成组合读**
- `dualport_bram` 读数据在下一拍才有效。
- 若 `lbu/lw` 当拍就用 `rdata`，会得到旧值/默认填充值（常见 0x00 或 0xA5/0x55）。
- 这与“UART 回传全常量”的现象一致。

3) **load-use 冒险未 stall/forward**
- `lbu` 后紧跟 `sb` UART，若无冒险处理会拿到旧寄存器值。

## 可复现最小用例（定位用）
```asm
csrrs a0, mhartid
bnez  a0, hart1
# hart0 分支：LED=1 循环
hart1:
# hart1 分支：LED=2 循环
```
现象：LED1 永远不亮 → `mhartid` 读值/分支比较存在冒险。

## 建议的快速验证（不用改硬件）
- 在 `csrrs` 后插入 1-2 条 `nop`：如果 LED1 开始亮，说明 CSR 冒险确实存在。
- 在 `lbu/lw` 后插入 1-2 条 `nop` 再 `sb` UART：如果数据正确，说明 load-use 冒险或同步读未处理。

## 需要 A 检查的核心点
- CSR 读结果的写回时序、EX 分支比较是否拿到最新值。
- dmem 读通路是否为同步读；是否在流水中正确延迟 1 拍。
- 是否缺少对 CSR / load 的前递或停顿。

## 结论一句话
外设正常，问题在核心对 **CSR 读/分支或同步 dmem 读** 的冒险处理，导致 hart 分支错误和 UART 输出恒定值。
