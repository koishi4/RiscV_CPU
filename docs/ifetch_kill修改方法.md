我把你 `uart_seq_imm_h0_deadlock.md` 里描述的“hart0 一直到不了 pc=0x08 / 最后 mem_req=0、ifid 全空”的现象，对着你现在这版 `cpu_top.v` 代码逐行对了一遍：你现在的 **sticky ifetch_req** 思路是对的，但你这里还有一个非常容易踩的坑——`ifetch_kill` 的“置位时机”会在某些对齐情况下把**下一条正确取指**也一起杀掉，尤其是 hart1 进入 `0x14c: beq x0,x0,0` 这种自环时最容易触发。

下面我给你一个“最小、直接可改”的补丁方案（不会推翻你现有结构），以及一个“强烈建议一起改”的 scheduler hold 方案（否则后面 UART busy 的 load/store 一定还会卡）。

---

## 1) 关键根因：`ifetch_kill` 被“误置位”，导致杀到下一次正确取指

你现在的 kill 逻辑是：

```verilog
if (exec_valid && !pipe_stall && (trap_set || trap_mret || branch_taken)) begin
    // Drop the next IFetch response for this hart to avoid stale sequential fetches.
    ifetch_kill[exec_hart] <= 1'b1;
end
```

问题在于：

* 你 **无条件** 在“控制流改变（branch/trap）”时把 `ifetch_kill[exec_hart]` 置 1。

* 但你的 IFetch 响应处理里，其实已经有一条 **“同周期 flush”** 的保护：

  ```verilog
  if (!ifetch_kill[ifetch_hart_d] &&
      !(ifetch_hart_d == exec_hart && (trap_set || trap_mret || branch_taken))) begin
      // accept fetch
  end
  ```

  也就是说：如果某个 IFetch 响应**刚好**在分支/陷入同一个周期返回，你已经会把它丢掉（不写 IFID、不推进 PC）。

* 关键坑：你是 **非阻塞赋值**（`<=`），因此在“同周期返回”的情况里：

  * 这一拍里 IFetch 响应丢掉了（靠的是 `branch_taken` 这条“同周期 flush”条件，而不是靠 `ifetch_kill`）
  * 但你后面仍然把 `ifetch_kill[exec_hart]` 置 1
  * `ifetch_kill` 的清除只发生在“某个 fetch 响应回来”的那个 always 里，而且清除判断用的是 **旧值**，于是这次新置位的 kill 不会立刻被清掉
  * 结果：`ifetch_kill` 会“溜到下一次取指响应”，把**下一次（很可能是正确的 target）**也干掉

在 hart1 的 `beq x0,x0,0` 自环里，这种“分支解析”和“顺序取指返回”对齐的概率很高，于是会出现你看到的那种：PC 看着对、但 IFID 怎么也填不起来、最后整个系统像“没请求了/死锁”。

---

## 2) 你应该怎么改：只在“确实有在途取指、且本周期不返回”时才置 `ifetch_kill`

把上面那段 kill 置位代码替换成下面这样（**这是最小修改**，基本不动你现在结构）：

```diff
- if (exec_valid && !pipe_stall && (trap_set || trap_mret || branch_taken)) begin
-     // Drop the next IFetch response for this hart to avoid stale sequential fetches.
-     ifetch_kill[exec_hart] <= 1'b1;
- end
+ if (exec_valid && !pipe_stall && (trap_set || trap_mret || branch_taken)) begin
+     // Drop the next IFetch response for this hart to avoid stale sequential fetches.
+     //
+     // 关键点：只有当“本 hart 的 IFetch 真的在途”且“这拍不会返回”时才 arm kill。
+     // 如果 cpu_mem_ready==1，说明响应这拍已经回来了，上面的 same-cycle flush 已经会丢掉它，
+     // 这里再 arm kill 会误杀下一次（通常是正确的 target fetch）。
+     if (ifetch_req && (ifetch_hart_d == exec_hart) && !cpu_mem_ready) begin
+         ifetch_kill[exec_hart] <= 1'b1;
+     end
+ end
```

这样改完以后：

* 分支那拍如果顺序 fetch 响应也回来了：你会靠 same-cycle flush 丢掉它，但 **不会** 额外把 `ifetch_kill` 留到下一拍
* 分支那拍如果顺序 fetch 响应还没回来（真正需要 kill 的情况）：你会把 `ifetch_kill` 置位，等响应回来再丢掉并清 kill

这能把你现在这种“kill 漏到下一次正确取指”现象直接堵住。

---

## 3) 强烈建议再改一个：让 scheduler 在 data/MMIO stall 时“别切 hart”

这个测试后半段会做 UART MMIO 轮询与写 TX：`mmio_ready` 可能会拉低（busy），你现在 `mem_req_data` 是组合信号，**如果 barrel scheduler 继续切 hart，数据请求可能会被“切没了”**，从而出现另一个经典死锁：ready 脉冲来时 req 不在，req 再来时 ready 已经走了。

你当前 `barrel_sched` 输出 `cur_hart = next_hart`，并且每拍都更新 `last_hart`。这意味着 stall 时也会切换 hart。

### 3.1 修改 `barrel_sched.v`：加一个 `hold` 输入，stall 时不更新 last_hart

在 `barrel_sched.v` 里加一个端口：

```diff
 module barrel_sched #(
     parameter HART_NUM  = 2,
     parameter HART_ID_W = 1
 )(
     input  wire                    clk,
     input  wire                    rst_n,
     input  wire [HART_NUM-1:0]     blocked,
+    input  wire                    hold,
     output reg  [HART_ID_W-1:0]    cur_hart,
     output reg                     cur_valid
 );
```

把 last_hart 更新改成：

```diff
 always @(posedge clk) begin
     if (!rst_n) begin
         last_hart <= {HART_ID_W{1'b0}};
-    end else if (next_valid) begin
+    end else if (next_valid && !hold) begin
         last_hart <= next_hart;
     end
 end
```

这样当 `hold=1` 时，scheduler 会“保持当前 hart 不切换”。

### 3.2 在 `cpu_top.v` 里接上 hold：建议用 `mem_stall`（或 `mem_stall | wb_stall`）

* 你需要在 scheduler 实例化之前**前向声明** `mem_stall`（因为你现在 `mem_stall` 声明在后面）
* 然后把 `mem_stall` 接到 `hold`

示例（你按你文件位置挪一下声明即可）：

```verilog
// 放在 u_sched 之前
wire mem_stall;   // forward declare

barrel_sched #(
    .HART_NUM(`HART_NUM),
    .HART_ID_W(`HART_ID_W)
) u_sched (
    .clk(clk),
    .rst_n(rst_n),
    .blocked(blocked_vec),
    .hold(mem_stall),      // 关键：data/MMIO stall 时别切 hart
    .cur_hart(exec_hart),
    .cur_valid(exec_valid)
);
```

> 如果你担心 wb_stage 的结构 hazard（`wb_stall`）也会出类似问题，可以用 `.hold(mem_stall | wb_stall)`；但不要把 muldiv_wait 也塞进 hold（你已经用 blocked 做了“让另一个 hart 跑”的设计）。

---

## 4) 我建议你改完后怎么验证（不用改 TB）

你现在 tb 的关键观察点是：

* `exec_hart==0 && idex_valid_cur && idex_pc_cur==0x08` 必须出现
* 并且最终 UART 发送需要满足 tb 的 `uart_tx_log`

改完第 2 节的 kill gating 后，`hart1` 的 `0x14c` 自环不会再导致“误杀 target fetch”；再改第 3 节的 scheduler hold 后，后半段 UART busy 的 load/store 也不会因为切 hart 把 req 切没。

---

## 5) 如果你只想先做“最小改动”，优先顺序

1. **先做第 2 节的 `ifetch_kill` 置位条件收紧**（这是你现在这个 `uart_seq_imm_h0_deadlock` 最像的根因）
2. 如果后面又卡在 UART busy 轮询或 store：再做第 3 节 scheduler hold

---

如果你愿意，我也可以直接按你工程现在的文件组织方式，把 `cpu_top.v` / `barrel_sched.v` 的**完整补丁版本**（可直接替换的文件内容）整理出来给你对比粘贴（你只要告诉我你实际源文件名是不是就是这两个，还是 `*.v` 而不是 `*.v.txt` 这类）。
