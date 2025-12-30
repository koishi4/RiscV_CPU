# muldiv_agent.md — muldiv_unit.sv 性能改进落地方案（先乘法后除法）

> 适用版本：当前工程 `muldiv_unit.sv`（XLEN=32，Radix-4 Booth 乘法 + 32-cycle non-restoring 除法，状态机含 S_DONE 气泡）

---

## 0. 目标与约束

### 0.1 目标（可量化）
- **乘法（MUL/MULH/MULHU/MULHSU）**
  - 去掉 `S_DONE` 额外气泡：busy 不再多占 1 拍
  - 乘法总体延迟从 **3 拍 done / 4 拍 busy** → 期望 **2 拍 done / 2 拍 busy**
  - 关键路径降低，**Fmax 明显提升**（核心来自：串行 CSA → Dadda/Wallace 压缩树）
- **除法（DIV/DIVU/REM/REMU）**
  - 去掉 `S_DONE` 气泡
  - 增加 **快路径**（除数为 2^k、被除数/除数特殊值）
  - 增加 **早停/可变迭代**（LZC 归一化，减少平均迭代次数）
  - 可选：Radix-4（最坏 16 iter）作为创新升级点

### 0.2 约束（尽量不动上层）
- 现有接口为 `start/op/a/b/hart_id/rd` + `busy/done/result/...`，**start 在 busy=1 时会被忽略**（上层 cpu_top 目前也是这样用的）。
- 第一阶段（乘法）**不修改接口**，确保 cpu_top / soc_top 无需改动即可收益。
- 第二阶段（除法）同样优先不改接口；若引入更激进的并行/队列，另开“可选增强”章节。

---

## 1. 现状瓶颈（针对你当前代码的点名）

### 1.1 乘法瓶颈
- Radix-4 Booth 产生 `NUM_PP=17` 个 64-bit 部分积；
- 现有 CSA 压缩在 `always_comb` 中做 **17 轮串行滚动**（sum/carry 每轮依赖上轮），组合深度 ~O(NUM_PP)；
- 乘法状态机：`S_MUL_PP → S_MUL_CSA → S_MUL_ADD → S_DONE`  
  `S_DONE` 只是回到 `S_IDLE`，导致 busy 多 1 拍（吞吐气泡）。

### 1.2 除法瓶颈
- non-restoring 固定 **32 次迭代**，无早停；
- 同样存在 `S_DONE` 额外 busy 气泡。

---

## 2. 第一阶段：先改乘法（建议按 M0→M3 逐步落地）

---

### M0. 乘法“白捡性能”：删除 `S_DONE` 气泡（同步也适用于除法）

**改动点**
- 删除状态 `S_DONE`（或保留枚举但不再进入）
- 在 `S_MUL_ADD` 计算出结果的同一拍：  
  - `done_reg <= 1'b1;`
  - `state <= S_IDLE;`（不再 `state <= S_DONE`）
- 同理：除法 `div_count==31` 的完成拍直接回 `S_IDLE`

**预期收益**
- 乘法 busy 从 4 拍 → 3 拍（done 不变）  
- 上层 `muldiv_issue` 能更早发下一条（少 1 拍气泡）

**注意**
- 你当前 `done_reg` 每拍开头会清 0（脉冲），保持不变即可。

---

### M1. 乘法核心提速：串行 CSA → Dadda/Wallace 压缩树（创新点主力）

#### 方案概要
- 仍保留 Radix-4 Booth 产生 17 个部分积（你现有 `booth_partial()` 可复用）
- 用 **Dadda tree 或 Wallace tree** 将 17 行部分积压到 **2 行（sum/carry）**：
  - 多层 (3:2) compressor（全加器阵列）/ (2:2) half-adder
  - 树深度约 **log2(17) ≈ 5 层**，显著短于串行 17 轮

#### 落地实现建议（可综合、可维护）
1. 新增一个“压缩树”模块/函数（推荐单独文件，或写在 muldiv_unit 内部 generate）：
   - 输入：`logic [63:0] pp[0:16]`
   - 输出：`logic [63:0] sum2, carry2`（carry 不移位或移位统一规范）
2. 压缩树写法推荐：
   - 用“列压缩”思想：每一位 column 收集当前层的 bit 列表，再用 3:2 压缩到下一层；
   - 或者用固定层级的数组实现（更容易一次写对）。
3. 输出规范：
   - 保持与你现有末端加法一致：`product = sum2 + (carry2 << 1)`

#### 里程碑验收（必须做）
- 保持现有功能一致：MUL/MULH/MULHU/MULHSU 结果对拍通过；
- 用综合报告对比：
  - 关键路径显著降低（压缩树层数少）
  - 面积略增（正常），但性能提升明显。

---

### M2. 乘法进一步减拍：重构状态机为“两拍完成”（建议在 M1 后做）

**目标**：从当前 `S_MUL_PP → S_MUL_CSA → S_MUL_ADD`（3拍 done）改为 **2拍 done**。

#### 当前结构为什么多一拍
- 你把 `pp_comb` 先寄存到 `mul_pp[]`（S_MUL_PP），下一拍才压缩（S_MUL_CSA）。

#### 重构方式（推荐）
- **取消 `mul_pp[]` 寄存阵列**（或保留但不再作为主路径）
- 在进入乘法运算后：
  - 第 1 拍：Booth 生成 `pp_comb[]` + 压缩树得到 `sum2/carry2`，寄存到 `mul_sum/mul_carry`（或新命名 `mul_sum2_reg/mul_car2_reg`）
  - 第 2 拍：CPA + signfix + 选择高/低 32 位，写 `result_reg` 并 `done_reg=1`，同时 `state<=S_IDLE`

#### 新状态机建议
- `S_IDLE`
- `S_MUL_TREE`：寄存压缩树输出
- `S_MUL_FINAL`：末端 CPA + 符号修正 + done 回 idle
- `S_DIV_RUN`（后续再动）

> 如果你担心 Booth+Tree 组合仍长：可以把 Booth 生成与 Tree 分开成两拍，但那会回到 3 拍 done；建议先做 Tree 再评估时序。

---

### M3. 乘法快路径（降低平均延迟，风险低，作为锦上添花）
在 `S_IDLE` 接收到 start 时（已经锁存 a/b/op 后）加快速判定：
- `muldiv_a==0 || muldiv_b==0`：结果直接 0
- `muldiv_b==1`：结果=muldiv_a（注意 MULH/高位时等价于符号扩展后的高位）
- `muldiv_b==ALL_ONES`（-1）：结果=-muldiv_a（有符号类）
- `muldiv_a==1` 类似可做

**实现策略**
- 只对最常见的 `MUL` / `MULHU` / `MULH` 做快路径也行；
- 快路径命中：直接 `result_reg <= ...; done_reg<=1; state<=S_IDLE;`（busy不拉高）

---

### （可选增强）M4. 参数化“高频版/低延迟版”
如果你希望报告里更“工程化”：
- `parameter MUL_PIPE = 0/1`：
  - 0：两拍完成（M2）
  - 1：三拍/四拍但更高 Fmax（Tree 中间插一层寄存）

---

## 3. 第二阶段：再改除法（在乘法稳定后按 D0→D3 走）

> 推荐顺序：**D0（1小时）→ D1（半天）→ D2（1天）→ D3（2~4天，可选）**

---

### D0. 删除 `S_DONE` 气泡（同 M0）
- `div_count==31` 的完成拍直接 `state<=S_IDLE`，不再进 `S_DONE`。

---

### D1. 除法快路径（立刻提升平均性能）
在开始除法时（`S_IDLE` 接收到 DIV/REM start）增加：
1. **除数为 0**：你已有处理（保持）
2. **有符号溢出**（MIN_INT / -1）：你已有处理（保持）
3. **除数为 2^k**（重点新增）
   - `is_pow2 = (b_abs & (b_abs-1)) == 0`
   - `k = ctz(b_abs)`（ctz 可用循环或小查表）
   - DIVU：`q = a_abs >> k`，REMU：`r = a_abs & ((1<<k)-1)`
   - 有符号：对 `q/r` 再按现有 signfix（你已有 sign_q/sign_r 框架）

**收益**
- 常见“除以常量/对齐”的代码段直接变成 1 拍完成。

---

### D2. LZC 归一化 + 可变迭代次数（把“固定32拍”改成“按需拍数”）
**关键思想**
- 只需要迭代 `iter = msb(a_abs) - msb(b_abs) + 1` 次（若负则 0）
- 用 LZC（leading zero count）得到 msb 位置：`msb = 31 - lzc(x)`

**落地做法**
1. 增加 `lzc32()` 函数（组合优先编码即可）
2. start 时计算：
   - `a_msb, b_msb`
   - `iter_max = (a_msb >= b_msb) ? (a_msb - b_msb + 1) : 0`
3. `S_DIV_RUN` 循环从 `count=0` 跑到 `iter_max-1` 即可提前结束。

**收益**
- 当 `b` 比 `a` 大很多时，可能只需 1~几次迭代，平均 cycles 大幅下降。

---

### （创新升级，可选）D3. Radix-4 non-restoring / SRT4（最坏 16 iter）
如果你希望除法也“性能很能打”，在 D1/D2 稳定后可以做：
- 每拍生成 2-bit quotient digit（-2/-1/0/+1/+2）之一；
- 余数按 radix-4 更新；
- 最坏 16 拍完成（对比现有 32 拍）。

> 这块实现复杂度明显上升，建议作为“可选创新增强”，在论文/答辩里很加分。

---

## 4. 验证与回归（强烈建议同步做，不然后面很难定位）

### 4.1 单元测试（必须）
- 随机测试（至少 10k 向量/每类 op）
- 覆盖 corner cases：
  - `0, 1, -1, 0x80000000, 0x7fffffff`
  - DIV/REM：除数为 0、溢出 MIN/-1
  - MULH/MULHSU 符号组合

### 4.2 对拍参考模型
- 乘法：用 64-bit 扩展算出 full product，再截高/低
- 除法：按 RISC-V M 扩展规则（你当前逻辑已包含 div0/overflow 的约定）

### 4.3 关键断言（建议）
- `muldiv_done` 只能在 `muldiv_busy` 的最后一拍或 busy=0 快路径时出现
- `done_hart_id/done_rd` 必须等于 start 时锁存的值
- start 在 busy=1 时不改变内部状态（保持你原注释语义）

---

## 5. 交付清单（你可以按这个打勾）

### 乘法（第一阶段交付）
- [ ] M0：删除 S_DONE 气泡（乘法完成拍回 idle）
- [ ] M1：Dadda/Wallace tree 替换串行 CSA（功能对拍通过）
- [ ] M2：两拍乘法状态机（done 延迟降到 2 拍）
- [ ] M3：快路径（0/1/-1 等）

### 除法（第二阶段交付）
- [ ] D0：删除 S_DONE 气泡（除法完成拍回 idle）
- [ ] D1：pow2 快路径（ctz + shift/mask）
- [ ] D2：LZC 早停（可变 iter）
- [ ] D3：Radix-4（可选创新）

---

## 6. 回退策略（工程上很重要）
- 若 M2 合并拍导致时序不收敛：保留 M1 的 tree，但把 Booth 与 tree 分两拍（3拍 done），仍然比原版快且更高 Fmax。
- 若 D2 早停逻辑有 bug：先只上 D1 快路径 + D0 去气泡，保证正确性，再逐步加 LZC。

---

## 7. 你下一步该怎么做（最短路径）
1) 先做 M0（10 行以内改动）验证 busy 气泡消失  
2) 再做 M1（tree 替换串行 CSA）验证结果正确 + Fmax 提升  
3) 再做 M2（两拍完成）验证周期缩短  
4) 乘法稳定后开始 D0→D2

