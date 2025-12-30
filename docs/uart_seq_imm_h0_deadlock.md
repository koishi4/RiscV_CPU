# UART Seq Imm H0 仿真死锁问题记录（供接手修复）

## 背景与目标
目标是验证 `uart_seq_imm_h0.mem` 仅由 hart0 发送 16 字节 `00,11,22...FF`。  
当前在 `tb_uart_seq_imm_h0` 仿真中反复失败，UART 0 字节，且 hart0 未进入 LUI@0x00000008。

## 复现方法
1) 仿真 top：`tb_uart_seq_imm_h0`  
2) 运行：`run 6000us`（默认 tcl）  
3) 观察 UART 与 fatal 输出（tcl.txt）

## 期望 vs 实际
- 期望：  
  - hart0 执行到 PC=0x00000008（LUI）  
  - UART 输出 16 字节，最终 `uart seq imm h0 gating passed`
- 实际：  
  - hart0 未执行到 LUI  
  - UART 0 字节  
  - 仿真直接触发 fatal

## 关键仿真日志（最新）
```
CSRRs mhartid: hart1 pc=0x00000000 csr=0x00000001
CSRRs mhartid: hart0 pc=0x00000000 csr=0x00000000
BNE: hart1 pc=0x00000004 rs1=0x00000001 rs2=0x00000000 taken=1
BNE: hart0 pc=0x00000004 rs1=0x00000000 rs2=0x00000000 taken=0
Fatal: hart0 never reached PC=0x00000008 (LUI).
  exec_valid=1 exec_hart=1 blocked=0x0
  pc0=0x00000008 pc1=0x0000014c
  ifid_valid0=0 ifid_valid1=0
  seen_ifid0=1 seen_mem_req=1 seen_mem_ready=1
  ifetch_hart_d=1 ifetch_pc_d=0x0000014c
  mem_req=0 mem_ready=0 mem_addr=0x0000014c
```

## 现象解读（重要）
- **BNE 结果正确**：hart1 跳转、hart0 不跳转。
- **IF/ID 全空**：`ifid_valid0=0, ifid_valid1=0`，说明当前没有可执行指令。
- **曾经有过取指与响应**：`seen_mem_req=1, seen_mem_ready=1, seen_ifid0=1`。
- **当前取指请求消失**：`mem_req=0` 且 `ifetch_hart_d=1` 停留在 hart1 的地址 0x14c。

结论：**取指请求在某个时刻被“饿死/消失”，CPU 进入死锁**。  
此问题已经稳定复现，并非偶发。

## 已尝试的修复（当前仍失败）
### 1) Sticky IFetch 请求
目标：一旦发起 IFetch，就保持到 `mem_ready` 返回。  
做法：移除 per‑hart inflight，用单一 `ifetch_req` 维持请求。  
状态：**失败**（仍出现 mem_req=0 且 IF/ID 为空）

### 2) 取指仲裁调整（避免 exec_hart 偏置）
目标：取指不依赖 exec_hart，IF/ID 空就发起。  
做法：根据 `ifid_valid` 选择 hart0/1；优先 hart0，否则 hart1。  
状态：**失败**（同样死锁）

## 重要线索（可直接用于定位）
1) **取指请求在死锁时为 0**  
   - 说明 `if_req` 未被拉高  
   - 重点检查：取指发起条件是否被异常门控
2) **exec_hart 长期停在 1（hart1）**  
   - hart1 为自旋分支，可能导致取指请求只围绕 hart1  
3) **IF/ID 全空但仍不发新取指**  
   - 应重点检查 IFetch 触发条件与 IF/ID 清空时序

## 可能的根因方向（供接手者排查）
- 取指触发条件被错误门控（例如 branch/trap/mem_is_data 逻辑在无效周期仍为 1）。  
- IFetch 发起条件用到了 **过期的 ifid_valid** 或 **错误的 hart 选择**。  
- 取指与数据访问仲裁导致 if_req 被拉低，但没有重新拉起。  
- 取指请求在同一周期被“清除再发起”时序不一致，导致 mem_req 断档。

## 建议的后续调试（不需要上板）
1) 打开波形查看以下信号（关键）：  
   - `ifetch_req`, `if_req`, `if_mem_req`, `cpu_mem_req`, `cpu_mem_ready`  
   - `ifetch_hart_d`, `ifetch_pc_d`  
   - `ifid_valid[0]`, `ifid_valid[1]`, `ifid_pc`, `ifid_inst`  
   - `mem_req_data`, `mem_is_data`, `mem_stall`  
   - `branch_taken`, `trap_set_raw`
2) 核对：在 IF/ID 为空时，是否**连续周期**维持取指请求直到 mem_ready 返回。  
3) 若仍无法定位，考虑把取指发起条件**独立成寄存器**，避免组合逻辑门控导致请求丢失。

## 备注
此问题发生在 CPU 核心取指与仲裁路径（Member A 所属范围），建议由 A 接手修复。  
我已停止进一步板级实验，当前全部基于仿真定位。
